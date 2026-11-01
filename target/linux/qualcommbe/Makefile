include $(TOPDIR)/rules.mk

ARCH:=aarch64
BOARD:=qualcommbe
BOARDNAME:=Qualcomm Atheros 802.11be WiSoC-s
FEATURES:=squashfs ramdisk fpu nand rtc emmc
KERNELNAME:=Image
CPU_TYPE:=cortex-a53
SUBTARGETS:=ipq53xx ipq95xx

KERNEL_PATCHVER:=6.18

include $(INCLUDE_DIR)/target.mk

# WiFi 相关包（wpad-openssl、kmod-ath12k）已移除：本 fork 只做 ER2 的有线/SFP
# 调试，不编 802.11 驱动、固件和 hostapd，能省十几分钟编译时间和大量磁盘空间。
# 需要恢复 WiFi 时，把 wpad-openssl 和 kmod-ath12k 加回下面这两行即可。
DEFAULT_PACKAGES += \
	autocore automount cpufreq e2fsprogs f2fs-tools losetup luci uboot-envtools \
	kmod-qcom-ppe kmod-qrtr-mhi kmod-qrtr-smd \
	kmod-dsa kmod-dsa-qca8k kmod-phy-aquantia kmod-phy-qca83xx \
	kmod-fs-ext4 kmod-fs-f2fs kmod-gpio-button-hotplug kmod-leds-gpio \
	kmod-usb3 kmod-usb-dwc3 kmod-usb-dwc3-qcom kmod-usb-serial-qualcomm tc-tiny

$(eval $(call BuildTarget))
