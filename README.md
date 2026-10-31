# immortalwrt-sfp

太乙 Plus ER2（JDCloud RE-CS-08）专用 ImmortalWrt 源码分支，用于调试 SFP 光口。

- 硬件：IPQ5332（四核 A53，WiFi7）+ QCA8386 交换芯片
- 平台：`qualcommbe` / `ipq53xx`，内核 6.18
- 仅构建 `jdcloud_re-cs-08` 一个机型，`ipq95xx` 平台已关闭
- 光口调试全过程与结论：[docs/ER2-SFP-notes.md](docs/ER2-SFP-notes.md)

# 分支

仅 `owrt` 一个分支，基于 [VIKINGYFY/immortalwrt](https://github.com/VIKINGYFY/immortalwrt) 的 `owrt` 分支修改。

# SFP 光口现状

- 2.5G 模块（含 PON 猫棒）可用：跑 2500BASE-X 强制模式，2.5Gbps / Full
- 10G 模块不可用：本板 PCS 只实现了 SGMII / SGMII+（2500BASE-X）/ USXGMII，不支持 10GBASE-R；
  且 OpenWrt 的 qca8k DSA 驱动 mac_capabilities 只到 MAC_2500FD
- 相关补丁：`patches-6.18/0403-*`（PCS 不支持带内自协商时降级为强制模式）、
  `0404-*`（模块不提供 A2h 软状态时停止轮询，避免日志刷屏）

# 配套

- 云编译：[LYOI/OpenWRT-CI](https://github.com/LYOI/OpenWRT-CI)（工作流 `ER2-BUILD`）
- U-BOOT（高通版，沉心，推荐）：https://github.com/chenxin527/uboot-qsdk12.5-build.git

# 上游致谢

本分支源码取自以下项目：

- https://github.com/VIKINGYFY/immortalwrt
- https://github.com/JiaY-shi/openwrt.git
- https://github.com/JuliusBairaktaris/openwrt-ppe-nss.git
- https://github.com/pbs05/ponwrt.git
- https://github.com/perceival/openwrt-flint3.git
