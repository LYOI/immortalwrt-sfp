# immortalwrt-sfp

> **归档状态：项目已归档（2026-11-02）。SFP 光口速率自适应已打通，但光口↔电口数据面转发无解。**

太乙 Plus ER2（JDCloud RE-CS-08）专用 ImmortalWrt 源码分支，用于调试 SFP 光口。

- 硬件：IPQ5332（四核 A53，WiFi7）+ QCA8386 交换芯片
- 平台：`qualcommbe` / `ipq53xx`，内核 6.18
- 仅构建 `jdcloud_re-cs-08` 一个机型，`ipq95xx` 平台已关闭
- 完整调试过程与最终结论：[docs/ER2-SFP-notes.md](docs/ER2-SFP-notes.md)

# 分支

仅 `owrt` 一个分支，基于 [VIKINGYFY/immortalwrt](https://github.com/VIKINGYFY/immortalwrt) 的 `owrt` 分支修改。

# SFP 光口现状（最终）

## 成果：速率自适应（link 层）已打通

- 2.5G 模块（含 PON 猫棒）→ 2500BASE-X，2.5Gbps/Full
- 10G 模块 → 10GBASE-R，10Gbps/Full，XPCS `KR_STS link=1`
- 插模块后由 phylink 自动选择 1000BASE-X / 2500BASE-X / 10GBASE-R

相关补丁（本仓库已提交）：
- `patches-6.18/0403-*`：PCS 不支持带内自协商时降级为强制模式
- `patches-6.18/0404-*`：模块无 A2h 软状态时停止轮询
- `patches-6.18/0405-*`：10GBASE-R 补上 PCS `MISC2` 的 SerDes 模式位（10G 关键）

## 无解：光口↔电口数据面转发（跨界）不通

sfp 挂在 SoC PPE 直连口（`qcom_ppe` port@2），lan/wan 是 QCA8386 DSA 口，
两者不同硬件域。上游 `qcom_ppe` 驱动对「PPE 直连口（non-DSA MAC port）的
host-bound RX 交付」存在未完成的 gap，导致：

- 广播/ARP/DHCP 能过（二层泛洪正常）
- 单播 TCP 不通（SYN 发出后无 SYN-ACK 回程）
- ping（ICMP）通但 SSH/HTTP 全断

这是上游驱动的架构级 gap（已由 GL.iNet GL-BE9300 移植者 perceival 在
linux-netdev 邮件列表确认，见 docs/ER2-SFP-notes.md），不是单个 bug。

**结论：sfp 光口本身能 link 到正确速率，但无法作为「和电口通信」的普通端口使用。**

## 正确的方向（供后续参考）

QSDK 架构把 sfp 挂在 QCA8386（ess-switch）上由 SSDK 硬件转发，是能跑通
数据面的正确方案。核心源码在 CodeLinaro 公开，现成 ER2 构建方案见：
https://github.com/zt406600/wlan-ap（er2 分支）。

# 配套

- 云编译：[LYOI/OpenWRT-CI](https://github.com/LYOI/OpenWRT-CI)（工作流 `ER2-BUILD`，同样归档）
- U-BOOT（高通版，沉心，推荐）：https://github.com/chenxin527/uboot-qsdk12.5-build.git

# 上游致谢

本分支源码取自以下项目：

- https://github.com/VIKINGYFY/immortalwrt
- https://github.com/JiaY-shi/openwrt.git
- https://github.com/JuliusBairaktaris/openwrt-ppe-nss.git
- https://github.com/pbs05/ponwrt.git
- https://github.com/perceival/openwrt-flint3.git
