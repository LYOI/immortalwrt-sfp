# 太乙 Plus ER2（JDCloud RE-CS-08）SFP 光口调试记录

测试环境：ImmortalWrt SNAPSHOT / 内核 6.18.55 / qualcommbe-ipq53xx
测试模块：诺基亚 3FE46541AA（2500BASE-X PON 猫棒）、FINISAR FCBG110SD2C07-1R（10GBASE-R AOC）

## 一、硬件与拓扑

- SoC：IPQ5332，四核 A53，WiFi7
- 交换芯片：QCA8386（DSA / qca8k），提供 wan + lan1 + lan2 + lan3 四个 2.5G 电口
- SFP 笼在 DTS 中挂在 `qcom_ppe` 的 `port@2`，`pcs-handle = <&pcs1_ch0>`
- `pcs1_ch0` 为 `qca8386_pcs1`（`pcs-phy@6`），实际驱动是 `drivers/net/phy/qcom/qca8084_serdes.c`
- 驱动内注释写明了这条链路的性质：`PCS1 is connected to the switch MAC, not to an external PHY.`
- 相关 PCS 寄存器（`drivers/net/pcs/pcs-qcom-ipq9574.c`）：
  - `PCS_MODE_CTRL` bit12:8 选择接口：`0x8` = 2500BASE-X，`0x10` = XPCS
  - `PCS_MISC2` bit6:4 选择 SerDes 模式：`0x3` = SGMII，`0x5` = SGMII+，`0x7` = USXGMII

## 二、故障一：插模块即 error，carrier 恒 0

插诺基亚猫棒：

```
sfp: autoneg setting not compatible with PCS
Module state: error
Signalling rate: 10313 kBd
rx_los: 0   tx_fault: 0   tx_disable: 1
carrier: 0
```

`ipq_pcs_inband_caps()` 对 2500BASE-X / 10GBASE-R 只声明了 `LINK_INBAND_DISABLE`。
phylink 插入 SFP 时校验带内自协商能力（`phylink_validate_pcs_inband_autoneg()`）：
2500BASE-X 归 `INBAND_BASEX`，模块 EEPROM 又声明了 autoneg，于是要求 `INBAND_ENABLE`，
校验不通过直接 `-EINVAL`，模块转 error、TX 被禁。

**修复**：`patches-6.18/0403-net-phylink-use-forced-mode-when-pcs-lacks-inband-autoneg.patch`
校验失败时不再拒绝模块，改为清掉 Autoneg 位、降级为强制模式。

```
sfp: PCS cannot do in-band autoneg for 2500base-x, using forced mode
sfp: switched to inband/2500base-x link mode
sfp: Link is Up - 2.5Gbps/Full - flow control rx/tx
```

接口状态：`sfp UP`、`speed 2500`、`duplex full`、`carrier 1`。

## 三、故障二：A2h 软状态字节读不到导致日志刷屏

诺基亚猫棒未实现 SFF-8472 A2h 页的 `SFP_STATUS` 字节（extended compliance code 也是非标准的 0x20），
SFP 轮询每次读都返回 `-ENXIO`，每 50ms 打一条：

```
sfp sfp-0: failed to read SFP soft status: -ENXIO
```

**修复**：`patches-6.18/0404-net-sfp-stop-polling-soft-status-if-module-cannot-provide-it.patch`
读到 `-ENXIO` 时把 `sfp->state_soft_mask` 清零，停止后续轮询。`sfp_soft_get_state()` 已在
`st_mutex` 内，因此直接清掩码，不调 `sfp_soft_stop_poll()`，避免自锁。

## 四、故障三：10G 模块 PCS 数字侧与模拟侧速率不一致（关键）

插 FINISAR 10G AOC：

```
sfp: configuring for inband/10gbase-r link mode
PCS0  MODE_CTRL=0x00000820  MISC2=0x00000050   → SEL=2500BASEX, MODE=SGMII+
PCS1  MODE_CTRL=0x00001020  MISC2=0x00000030   → SEL=XPCS(正确), MODE=SGMII(错)
carrier: 0
```

`ipq_pcs_config_10gbaser()` 只写了 `val = PCS_MODE_XPCS`，从来没碰过 `MISC2`。
于是数字侧切到了 XPCS 按 10.3125G 跑，模拟侧（SerDes）还停在上一轮留下的 SGMII（0x3，1.25G），
两边速率对不上，link training 永远完不成。

后面的 `if (misc2)` 分支本来是写 MISC2 的，但 `misc2` 变量在 10GBASE-R 分支里是 0，所以整段被跳过。

**修复**：`patches-6.18/0405-net-pcs-ipq9574-program-misc2-for-10gbase-r.patch`
把 10GBASE-R 折进原来那句 USXGMII 的 MISC2 赋值：

```c
if (interface == PHY_INTERFACE_MODE_USXGMII ||
    interface == PHY_INTERFACE_MODE_10GBASER)
	misc2 = PCS_MISC2_MODE_USXGMII;   /* 0x7 */
```

USXGMII 用的 SerDes 速率同样是 10.3125G，所以直接复用它的 MISC2 值。

修复后：

```
PCS1  MISC2  0x30 → 0x70
XPCS  KR_STS 0x0000000c → 0x0000100d   (link=1)
sfp   UP  carrier 1  speed 10000
dmesg: sfp: Link is Up - 10Gbps/Full - flow control rx/tx
```

## 五、当前实测结果

| 场景 | 结果 |
| --- | --- |
| 2500BASE-X 猫棒 | 2.5Gbps/Full，正常 |
| 10GBASE-R AOC 直连 ER2 sfp | 10000/Full，`KR_STS link=1` |
| 光口 → 10G 交换机 → 终端 | 二层通（DHCP 能拿到租约、ARP 能解析），**三层单播不通** |
| 同一终端直连 lan3 电口 | 0% 丢包，RTT 0.7ms，正常 |

## 六、遗留问题

1. **光口经交换机后单播不通**。sfp 与交换机能建立 link，DHCP 广播能过、ARP 能应答，
   但 ICMP / TCP 单播双向都不通。已排除：NAS 侧 ping 错 IP、NAS 网卡 MAC 过滤、ER2 flow offloading 与硬件加速、
   双网口同网段回包走错口（策略路由已钉死）、两台不同交换机与换端口换光纤位置。
   剩余怀疑集中在 sfp 这条 USXGMII 链路的单播收发是否完整，需要用另一台确定正常的 10G 设备接 sfp 做对照。
2. 光口与 LAN 之间的流量走 SoC 软件桥接，不享受 QCA8386 硬件转发，跑满时 CPU 占用会上来。
3. 插拔模块后偶发需要重启网口才会重新协商。

## 七、2.5G / 10G 自动切换

USXGMII 本身是多速率 SerDes，同一个 SFP+ 口天然支持 10G / 5G / 2.5G / 1G 自适应。
要做到插什么模块跑什么速率，`pcs_config()` 需要按 link speed 选 `SEL` 与 `MISC2`，而不是像现在
只在 10GBASE-R 分支里补一个值：

| 接口 | MODE_CTRL (`SEL`) | MISC2 (SerDes) |
| --- | --- | --- |
| 10GBASE-R | `0x10` XPCS | `0x7` USXGMII |
| 2500BASE-X | `0x8` 2500BASEX | `0x5` SGMII+ |
| 1000BASE-X | `0x8` SGMII | `0x3` SGMII |

## 八、变更清单

| 文件 | 改动 |
| --- | --- |
| `dts/ipq5322-re-cs-08.dts` | SFP 口 `phy-mode` 由 `10gbase-r` 改为 `2500base-x`，插模块后由 phylink 重新选择 |
| `patches-6.18/0403-...` | phylink 带内不支持时降级为强制模式 |
| `patches-6.18/0404-...` | 模块无 A2h 软状态时停止轮询 |
| `patches-6.18/0405-...` | 10GBASE-R 补上 MISC2，PCS 两侧速率对齐，10G 链路可建立 |
| `qualcommbe/Makefile` + `ipq53xx/target.mk` | 去掉 WiFi，仅构建 `jdcloud_re-cs-08` |
| `package/er2-debuglog/` | 本地调试用，CI 默认不选 |
| `02_network` | SFP 归入 LAN，四个 2.5G 电口同网段 |

## 九、后续可选方向

1. 找一台确定正常的 10G 设备接 sfp，把单播不通这件事定位到 ER2 侧还是交换机侧
2. 按第七节实现 `pcs_config()` 的速率自适应，让 10G / 2.5G 模块免配置互换
3. 对照官方 dtb 重新梳理 QCA8386 → SoC 的 CPU 口配置，争取让光口回到交换芯片上，恢复硬件转发
