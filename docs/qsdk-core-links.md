# QSDK 核心组件源码链接清单（ER2 / IPQ5332）

> 来源：`zt406600/wlan-ap` 的 `er2` 分支（京东云 ER2 完整 QSDK + OpenWrt 25.12 构建方案）
> 提取时间：2026-11-02

## 一、构建方案本体

| 项目 | 值 |
|---|---|
| 仓库 | `https://github.com/zt406600/wlan-ap`（分支 `er2`） |
| 上游 OpenWrt | `https://github.com/openwrt/openwrt.git`（分支 `openwrt-25.12`） |
| 基线 revision | `f0a60eee2fe051741c643ea6118718aae1ef17fb`（v25.12.5） |
| 内核 | 6.6（ipq53xx target 由 qca feed 提供） |
| 包管理 | apk |
| ER2 完整 config | `defconfig/jdc-er2.config`（351 包，含 LuCI） |
| 最小 config | `profiles/jdcloud_er2.yml`（约 80 包） |
| ER2 设备树 | `feeds/qca-wifi-7/ipq53xx/dts/ipq5332-jdcloud-er2.dts` |

## 二、QSDK 核心组件源码（全部在 CodeLinaro，公开）

| 组件 | 源码仓库 | 锁定 commit |
|---|---|---|
| **qca-ssdk**（交换驱动，SSDK 3.1.0） | `https://git.codelinaro.org/clo/qsdk/oss/lklm/qca-ssdk` | `4a51edc04910792fde91098b6c1a1655e63800b6` |
| **qca-nss-dp**（数据面） | `https://git.codelinaro.org/clo/qsdk/oss/lklm/nss-dp` | `23928147cfb6f55638cc0a27f700831623ed679c` |
| **qca-nss-phy** | `https://git.codelinaro.org/clo/qsdk/oss/lklm/qca-nss-phy` | `ad5f76af81697d6d2f0864b8c72a6f38da5079a9` |
| **nss-ppe**（PPE 引擎） | `https://git.codelinaro.org/clo/qsdk/oss/lklm/nss-ppe` | `d53eff24bf257a8bb1b2f68beb3aa06332bfd567` |
| **qca-nss-ecm**（连接管理） | `https://git.codelinaro.org/clo/qsdk/oss/lklm/qca-nss-ecm` | `7b7ea2753e0918c6c82318b80b87e8d45a3495a3` |
| **shortcut-fe**（SFE） | `https://git.codelinaro.org/clo/qsdk/oss/lklm/shortcut-fe` | `5818706ab48c7a8bf45ffeee8bc3a5f5bcbc38b0` |

> 注：nss-ppe 被多个包复用（ppe-ds、ppe-vp 等都是同一个 commit，只是不同分支/构建选项）。

## 三、ER2 的 SFP 拓扑（QSDK 架构，决定性）

`feeds/qca-wifi-7/ipq53xx/dts/ipq5332-jdcloud-er2.dts`：

```
port@1 {
    port_id = <2>;
    phy_address = <30>;        /* 0x1e，官方/第三方统一值 */
    media-type = "sfp";        /* fiber mode */
};
```

- sfp 是 QCA8386（ess-switch1）的 port@1，`port_id=2`，`phy_address=0x1e`
- 由 SSDK 硬件转发，**不是**挂在 SoC PPE 直连口上
- 这跟我们 ImmortalWrt 的「sfp 挂 qcom_ppe port@2」**架构完全不同**

## 四、其他关键组件

- `qca-ssdk-shell` —— SSDK 的用户态 shell 工具
- `kmod-qca8084`、`kmod-qca8k-cc` —— QCA8084 PHY / QCA8386 交换芯片驱动
- `kmod-phy-aquantia` —— Aquantia PHY（SFP cage 用的）
- `kmod-phylink` —— phylink 框架

## 五、QSDK 架构 vs 我们 ImmortalWrt 架构（核心区别）

| | QSDK（zt406600/wlan-ap） | 我们 ImmortalWrt 6.18 |
|---|---|---|
| 内核 | 6.6（OpenWrt 25.12） | 6.18 |
| 交换驱动 | SSDK 3.1.0 + NSS/PPE/ECM | 上游 qca_ppe + DSA + qca8k |
| sfp 归属 | QCA8386 的 port@1（media-type=sfp） | qcom_ppe 的 port@2（直连口） |
| sfp 数据面 | SSDK 硬件转发（架构正确） | PPE 直连口（数据面未打通，上游 gap） |
| 加速 | NSS + ECM（硬件 offload） | PPE flowtable（上游） |

## 六、结论

「学 QSDK 核心做 ImmortalWrt」的正确答案就是这套：**OpenWrt 25.12 + QSDK SSDK/NSS/PPE 全家桶**，
其中 sfp 挂 QCA8386（ess-switch）由 SSDK 硬件转发。所有核心组件源码都在 CodeLinaro 公开，
zt406600/wlan-ap 的 er2 分支已经把「拉源码 + 打补丁 + 生成 ER2 配置 + 编译」全流程做成了脚本。
