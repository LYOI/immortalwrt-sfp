include $(TOPDIR)/rules.mk

PKG_NAME:=er2-debuglog
PKG_VERSION:=1.0
PKG_RELEASE:=1

PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/er2-debuglog
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=ER2 debug logging (netconsole + pstore archive)
  DEPENDS:=+kmod-netconsole
endef

define Package/er2-debuglog/description
  调试专用组件，正式镜像不选它。
  - netconsole：把内核 printk 直接通过 UDP 发到远端，不依赖用户态，
    用户态卡死时仍能拿到日志；
  - pstore-archive：开机把上一次崩溃留在 ramoops 里的记录拷到
    /etc/bootlog 并清空 pstore。
endef

define Package/er2-debuglog/conffiles
/etc/config/netconsole
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Compile
endef

define Package/er2-debuglog/install
	$(INSTALL_DIR) $(1)/etc/config $(1)/etc/init.d $(1)/etc/uci-defaults
	$(INSTALL_CONF) ./files/netconsole.config $(1)/etc/config/netconsole
	$(INSTALL_BIN) ./files/netconsole.init $(1)/etc/init.d/netconsole
	$(INSTALL_BIN) ./files/pstore-archive.init $(1)/etc/init.d/pstore-archive
	$(INSTALL_BIN) ./files/99-bootlog $(1)/etc/uci-defaults/99-bootlog
endef

$(eval $(call BuildPackage,er2-debuglog))
