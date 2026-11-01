SUBTARGET:=ipq53xx
BOARDNAME:=Qualcomm Atheros IPQ53xx

# WiFi 固件（ath12k-firmware-ipq5332 / qcn9274）已移除：本 fork 只做 ER2 的
# 有线/SFP 调试，不编 802.11。需要恢复时把这两个包名加回下面一行。
DEFAULT_PACKAGES +=

define Target/Description
	Build firmware images for Qualcomm Atheros IPQ53XX based boards.
endef
