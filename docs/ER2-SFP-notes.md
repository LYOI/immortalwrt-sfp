# 太乙 Plus ER2（JDCloud RE-CS-08）SFP 光口调试记录

测试环境：ImmortalWrt SNAPSHOT / 内核 6.18.55 / qualcommbe-ipq53xx
测试模块：诺基亚 3FE46541AA（2500BASE-X PON 猫棒）、FINISAR FCBG110SD2C07-1R（10GBASE-R AOC）

## 一、硬件与拓扑

- SoC：IPQ5332，四核 A53，WiFi7
- 交换芯片：QCA8386（DSA / qca8k），提供 wan + lan1 + lan2 + lan3 四个 2.5G 电口
- SFP 笼在现有 DTS 中挂在 `qcom_ppe` 的 `port@2`，`pcs-handle = <&pcs1_ch0>`
- `pcs1_ch0` 为 `qca8386_pcs1`（`pcs-phy@6`），实际驱动是 `drivers/net/phy/qcom/qca8084_serdes.c`
- 驱动内注释写明了这条链路的性质：`PCS1 is connected to the switch MAC, not to an external PHY.`
  即 PCS1 是 SoC 与 QCA8386 之间的 SGMII+ 2.5G 链路，时钟固定 312.5MHz

## 二、故障现象

插诺基亚猫棒：

```
sfp: autoneg setting not compatible with PCS
Module state: error
Signalling rate: 10313 kBd
rx_los: 0   tx_fault: 0   tx_disable: 1
carrier: 0
```

插 FINISAR 10G AOC：

```
sfp: configuring for inband/10gbase-r link mode
carrier: 0
```

注意 `configuring for ...` 只是 phylink 打印的配置意图，不代表链路已经 up。

## 三、根因一：phylink 带内自协商校验把模块拒绝了

`drivers/net/pcs/pcs-qcom-ipq9574.c` 的 `ipq_pcs_inband_caps()`：

```c
case SGMII / QSGMII / PSGMII / 1000BASEX / USXGMII / 10G_QXGMII:
    return LINK_INBAND_DISABLE | LINK_INBAND_ENABLE;
case 2500BASEX / 10GBASER:
    return LINK_INBAND_DISABLE;   /* 只有关闭 */
```

phylink 插入 SFP 模块时会校验“PCS 是否支持当前接口模式下所需的带内协商”（`phylink_validate_pcs_inband_autoneg()`）：

- 2500BASE-X 归类为 `INBAND_BASEX`，模块 EEPROM 又声明了 autoneg，于是要求 PCS 支持 `INBAND_ENABLE`，而 PCS 只给 `DISABLE`，校验不通过直接 `-EINVAL`，模块状态转 error、TX 被禁。
- 10GBASE-R 归类为 `INBAND_NONE`，phylink 会主动把 Autoneg 位清掉再校验，所以不报这个错。

**修复**：`patches-6.18/0403-net-phylink-use-forced-mode-when-pcs-lacks-inband-autoneg.patch`
校验失败时不再拒绝模块，改为清理 Autoneg 位并降级为强制模式。

验证结果（猫棒）：

```
sfp: PCS cannot do in-band autoneg for 2500base-x, using forced mode
sfp: switched to inband/2500base-x link mode
sfp: Link is Up - 2.5Gbps/Full - flow control rx/tx
```

接口状态：`sfp UP`、`speed 2500`、`duplex full`、`carrier 1`。

## 四、根因二：A2h 软状态字节读不到导致日志刷屏

诺基亚猫棒未实现 SFF-8472 A2h 页的 `SFP_STATUS` 字节（其 extended compliance code 也是非标准的 0x20），
SFP 轮询时每次读都会返回 `-ENXIO`，于是每 50ms 打一条：

```
sfp sfp-0: failed to read SFP soft status: -ENXIO
```

**修复**：`patches-6.18/0404-net-sfp-stop-polling-soft-status-if-module-cannot-provide-it.patch`
读到 `-ENXIO` 时把 `sfp->state_soft_mask` 清零，停止后续轮询（`sfp_soft_get_state()` 已在 `st_mutex` 内，因此直接清掩码而不是调 `sfp_soft_stop_poll()`，避免自锁）。

## 五、10G 为什么不行

第一层，PCS 接口模式。`qca8084_pcs_set_interface_mode()` 只认三种：

```c
SGMII          → MODE_CONTROL_SGMII
2500BASEX      → MODE_CONTROL_SGMII_PLUS
10G_QXGMII     → MODE_CONTROL_XPCS + USXGMII datapass
default        → return -EOPNOTSUPP
```

根本没有 10GBASE-R。而 SFP 光模块只会让 phylink 在 1000BASE-X / 2500BASE-X / 10GBASE-R 里选，选到 10GBASE-R 就撞在 default 上。

第二层，官方 QSDK 的拓扑和 OpenWrt 不一样。从官方原版镜像 `JDCOS-JDC09-4.5.3.r4533-...-sign.img` 里提取出的参考设计 dtb 显示：

```
ess-switch0@0 {
    compatible = "qcom,ess-switch-qca8386";
    qcom,port_phyinfo {
        port@0 { port_id = <1>; forced-speed = <2500>; forced-duplex = <1>; };
        port@1 { port_id = <2>; phy_address = <0x1e>; media-type = "sfp"; };
    };
};
```

即官方的 SFP 是 QCA8386 的第 2 号端口，由 ess-switch 硬件转发，SoC 只留一个 CPU 口上下行。

第三层，OpenWrt 的 DSA 驱动还不支持 10G 端口。`drivers/net/dsa/qca/qca8k-8xxx.c` 虽然实现了 phylink（`qca8k_phylink_mac_config` / `qca8k_phylink_get_caps` / `mac_select_pcs`），但：

- `phy-mode` 只实现到 `PHY_INTERFACE_MODE_2500BASEX`
- `mac_capabilities` 只到 `MAC_2500FD`
- 全文没有任何 usxgmii / 10gbase-r 处理

**结论：在 ImmortalWrt 现有 DSA 架构下，这个光口上限就是 2.5G。**
要做到 2.5G 与 10G 共存，必须给 `qca8k` 补上 10G 端口的 PHY 模式支持（USXGMII / 10G_QXGMII 的 mac_config 与 PCS 选择），或移植 QSDK 的 `ess-switch` 驱动，属于驱动开发工作量。

另外一点性能提醒：SFP 现在是挂在 SoC 的 PPE 口而不是交换芯片上，SFP 与 LAN 之间的流量需要经过 SoC 软件桥接，不享受 QCA8386 的硬件转发。

## 六、变更清单

| 文件 | 改动 |
| --- | --- |
| `dts/ipq5322-re-cs-08.dts` | SFP 口 `phy-mode` 由 `10gbase-r` 改为 `2500base-x`，补齐注释 |
| `patches-6.18/0403-...` | phylink 带内不支持时降级为强制模式 |
| `patches-6.18/0404-...` | 模块无 A2h 软状态时停止轮询 |
| `ipq53xx/base-files/etc/board.d/02_network` | SFP 归入 WAN，四个 2.5G 电口全归 LAN |
| `image/ipq53xx.mk` | 仅构建 `jdcloud_re-cs-08` |
| `image/ipq95xx.mk` | 关闭 ipq95xx 平台全部机型 |

## 七、后续可选方向

1. 给 `qca8k` 增加 10G 端口支持，把 SFP 移回交换芯片（同时恢复硬件转发）
2. 对照官方 dtb 重新梳理 QCA8386 → SoC 的 CPU 口配置
3. 换用带 QSDK 交换驱动的固件验证 10G 模块
