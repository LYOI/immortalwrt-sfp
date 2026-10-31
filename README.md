# immortalwrt-sfp

太乙 Plus ER2（JDCloud RE-CS-08）专用 ImmortalWrt 源码分支，用于调试 SFP 光口。

- 硬件：IPQ5332（四核 A53，WiFi7），平台 `qualcommbe` / `ipq53xx`
- 仅构建 `jdcloud_re-cs-08` 一个机型，`ipq95xx` 平台设备已关闭
- 内核 6.18（qualcommbe）

# 分支

仅 `owrt` 一个分支，基于 [VIKINGYFY/immortalwrt](https://github.com/VIKINGYFY/immortalwrt) 的 `owrt` 分支修改。

# SFP 光口说明

光口 `port@2` 在 `target/linux/qualcommbe/dts/qcom/ipq5322-re-cs-08.dts`：

- 默认 `phy-mode = "10gbase-r"`，`managed = "in-band-status"`
- 10GBASE-R PCS 不支持带内自协商，接 2500BASE-X 模块（如诺基亚猫棒）会报
  `sfp: autoneg setting not compatible with PCS` 并停在 `Module state: error`
- 调试方向：去掉 `managed = "in-band-status"` 保持 10G；或改 `phy-mode = "2500base-x"` 适配 2.5G 模块

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
