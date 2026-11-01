# ER2（京东云太乙 Plus / IPQ5332）SFP 光口最终总结

> 归档时间：2026-11-02
> 结论：**SFP 光口速率自适应（2.5G/10G）已打通；但光口↔电口的数据面转发无解，项目归档。**

## 一、成果（已验证，保留）

### 1. SFP 光口速率自适应（link 层）

sfp 光口能够自动识别模块速率并 link 到对应档位：

| 模块 | 协商结果 |
|---|---|
| 诺基亚 3FE46541AA（2.5G PON 猫棒） | 2500BASE-X，2.5Gbps/Full |
| FINISAR FCBG110SD2C07-1R（10G AOC） | 10GBASE-R，10Gbps/Full，XPCS KR_STS link=1 |

实现依赖三个内核补丁（都在 `target/linux/qualcommbe/patches-6.18/`）：

- **`0403-net-phylink-use-forced-mode-when-pcs-lacks-inband-autoneg.patch`**
  PCS 不支持带内自协商时，phylink 降级为强制模式，不再把模块判 error。
  （2.5G 猫棒能不能 link 的关键）

- **`0404-net-sfp-stop-polling-soft-status-if-module-cannot-provide-it.patch`**
  模块读不到 A2h 软状态字节时停止轮询，避免日志刷屏。

- **`0405-net-pcs-ipq9574-program-misc2-for-10gbase-r.patch`**
  10GBASE-R 补上 PCS `MISC2` 的 SerDes 模式位（0x30 → 0x70），
  让数字侧 XPCS（10.3125G）与模拟侧 SerDes 速率对齐。
  （10G 模块能不能 link 的关键，本次排查的核心成果）

### 2. DTS 关键配置

`target/linux/qualcommbe/dts/ipq5322-re-cs-08.dts`：

```
&qcom_ppe {
    ethernet-ports {
        ppe_sfp: port@2 {
            reg = <2>;
            label = "sfp";
            phy-mode = "10gbase-r";      /* 插模块后由 phylink 重新选择 */
            managed = "in-band-status";
            sfp = <&sfp0>;
            pcs-handle = <&pcs1_ch0>;
            ...
        };
    };
};
```

`phy-mode` 只是「未插模块时的默认值」，插模块后 phylink 会根据模块 EEPROM
自动在 1000BASE-X / 2500BASE-X / 10GBASE-R 里重新选择——这就是「自动识别」的机制。

## 二、无解问题（已确认，归档原因）

### 光口 ↔ 电口的数据面转发（跨界）不通

**现象**：sfp 光口 link up 到 10G，但光口和电口之间无法正常通信：
- 广播/ARP/DHCP 能过（二层泛洪正常）
- 单播 TCP 不通（SYN 发出后无 SYN-ACK 回程）
- ping（ICMP）能通，但 TCP/SSH/HTTP 全断

**根因（已定位到代码级）**：

sfp 挂载在 SoC 的 PPE 直连口（`qcom_ppe` 的 port@2），而 lan/wan 是
QCA8386 交换芯片的 DSA 口，两者是不同硬件域。跨域转发依赖上游
`qcom_ppe` 驱动，但这套驱动对「PPE 直连口（non-DSA MAC port）的 host-bound
RX 交付」存在未完成的 gap。

**决定性证据**：上游 PPE 驱动作者 Luo Jie 的邮件列表里，GL.iNet GL-BE9300
（同为 IPQ5332）移植者 perceival 在 2026-06-21 明确提出相同问题：

> "qcom_ppe: direct (non-DSA) MAC port - host-bound RX dropped at EDMA (src_port_inval_type)"
> "is 'deliver a direct MAC port's own ingress to the host CPU' an intended/supported configuration today?"

即「PPE 直连口的数据面交付」在上游驱动里根本未实现，DSA conduit 口能正确
交付（所以电口正常），直连口不能（所以 sfp 数据面不通）。

**结论**：这不是单个 bug，而是「sfp 挂 PPE 直连口」这个架构在上游驱动里
就是未完成状态。要解决必须走 QSDK 架构（sfp 挂 QCA8386，SSDK 硬件转发），
等于换一套交换驱动，超出本仓库范围。

## 三、正确的架构方向（供后续参考）

QSDK 架构把 sfp 挂在 QCA8386（ess-switch）上，由 SSDK 硬件转发：

```
port@1 {
    port_id = <2>;
    phy_address = <30>;    /* 0x1e */
    media-type = "sfp";
};
```

完整 QSDK 核心源码（CodeLinaro 公开）+ 现成 ER2 构建方案：
- 构建方案：`https://github.com/zt406600/wlan-ap`（er2 分支）
- 核心组件源码清单见 `docs/qsdk-core-links.md`

## 四、归档状态

- 本仓库（immortalwrt-sfp）：保留 0403/0404/0405 三个有效补丁 + DTS 配置，
  作为「sfp 速率自适应」的成果存档。sfp 数据面跨界问题标记为无解。
- OpenWRT-CI：保留 ER2 编译流程，标注 sfp 局限。
