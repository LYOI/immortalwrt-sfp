# ER2 sfp 跨界丢包根因分析（2026-11-02）

## 现象

- sfp 光口（10G USXGMII）接交换机时，交换机下的设备（ARM 飞牛 eth1，.123）：
  - ping / ICMP 通
  - SSH / TCP 不通（SYN 发出后无 SYN-ACK 回来）
- 同一飞牛的 eth0（.247）接 ER2 电口（lan3）时，SSH 正常
- 电口 ↔ 电口（lan2 ↔ lan3）转发正常；sfp ↔ 电口 跨界转发异常
- ER2 自己连 .123 的 TCP 通（conntrack 里 TIME_WAIT + ASSURED）

## 已排除项（全部验证过，非根因）

1. 光模块 / 光纤 / 交换机物理层 —— 正常，KR_STS link=1, speed=10000
2. 10G PCS 配置 —— 0405 补丁正确，MISC2 0x30→0x70
3. flow offloading（软/硬）—— 关了没用
4. 调试打印时序干扰 —— 干净固件也没用
5. MTU / 帧长 —— 各口 mtu=1500，PPE reason_counters 里 "L2 MTU checking fail drop" 全 0
6. 防火墙 forward 链 —— 桥接流量走 table bridge (policy accept)，不被拦
7. syn_flood 限速 —— 25/s 阈值，手动连接不会触发
8. PPE RX NAPI budget —— IPQ5332 默认 128（正确），edma_rx_napi_budget=0 表示用默认
9. PPE 硬件丢包 —— reason_counters 里所有 drop 原因全 0；l2_forward RX_DROP=0
10. 内核 softnet —— dropped=0, time_squeeze=0
11. 软件桥 br-lan —— rx_dropped=0, tx_dropped=0

## 定位到的丢包点

抓包对比（本机 .186 SSH → .123）：

```
lan2 tx +1   ← SYN 从 lan2 进入 ER2
sfp  tx +1   ← SYN 被 ER2 从 sfp 转发出去了
sfp  rx +1   ← SYN-ACK 从交换机经 sfp 回来了
lan2 rx +0   ← 但 SYN-ACK 没回到 lan2！ ← 丢包点在这里
```

即：回程帧在「sfp 收到 → 转发到 lan2」之间被丢。单向（lan2→sfp）正常，反向（sfp→lan2）丢。

## 根因（最终锁定）

DTS 拓扑：

```
&qca8386 {                 ← QCA8386 交换芯片（DSA）
    port@1 = wan   (switch_port=1)
    port@2 = lan1  (switch_port=2)
    port@3 = lan2  (switch_port=3)
    port@4 = lan3  (switch_port=4)
}
&qcom_ppe {               ← PPE 引擎
    port@2 = sfp            ← sfp 直接挂 PPE，不经 QCA8386
}
```

sfp 在 PPE 域，lan 在 QCA8386 域，跨界转发（sfp↔lan）依赖上游 qcom_ppe 驱动的
athtag VP 映射 + direct_switch + flow offload 机制。但这套机制对「PPE 直连口」
的支持是未完成的 gap。

## 决定性外部佐证（2026-11-02 查得）

上游 PPE 驱动作者 Luo Jie 的邮件列表里，GL.iNet GL-BE9300（同为 IPQ5332）
的移植者 perceival（Kamil Bienkiewicz）在 2026-06-21 明确提出：

> "qcom_ppe: direct (non-DSA) MAC port - host-bound RX dropped at EDMA (src_port_inval_type)"

原文核心：
- 他的 port@2 是「直连（non-DSA）MAC 口」，RX broken
- 症状：`rxdesc:src_port_inval_type = 1`，帧的 src_info type 不是 PORTID，
  `edma_rx_get_src_dev()` 返回 NULL，帧被丢
- DSA conduit 口（port@1）能正确拿到 `SRCINFO_TYPE_PORTID`，直连口拿不到
- 他的原问："is 'deliver a direct MAC port's own ingress to the host CPU'
  an intended/supported configuration today, or does the EDMA RX path assume
  all host-bound traffic arrives via the DSA conduit or an offloaded bridge VSI?"

**结论：上游 PPE 驱动对「PPE 直连口（non-DSA MAC port）」的 host-bound RX
交付，是一个未完成的 gap，不是我们这台机器特有的问题。**

参考：https://marc.info/?m=178204067670122

## 修复尝试记录（均未解决，已放弃）

1. **0669 patch（athtag type 修复）**：让 `ppe_vp_athtag_add()` 写 switch_reg 时也写 type+enable。
   结果：PRX[2/3/4] type 0x0000→0xaaaa、en 0→1，但跨界 TCP 仍不通，SYN 反而不再从 sfp 转发出去。
   （该 patch 未提交，已删除）

2. **direct_switch 机制**：`qcom_ppe_ds_register()` 要求 `cfg->wlan_dev` 非空，
   是给 WLAN 固件（nss-wifi-drv）共享 EDMA/PPE 用的，跟 sfp 无关，unregistered 是正常现象。

## 关键区分：sfp 挂 PPE vs 挂 QCA8386

我们（ImmortalWrt 6.18）的 DTS：sfp 挂 `qcom_ppe` 的 `port@2`（reg=<2>），
phy-mode=10gbase-r，pcs-handle=<&pcs1_ch0>，走 phylink + SFP cage。

QSDK（39wrt/QWRT，5.4 内核；jiang，6.6 内核）的 dtb：sfp 挂 QCA8386（ess-switch1）
的一个端口，由 SSDK 硬件转发，media-type=sfp，phy_address=0x1e。

**两条路线：**
- 路线 A（对齐 QSDK）：把 sfp 移到 QCA8386 上，需 qca8k 驱动支持 QCA8386 的 SFP 口
- 路线 B（补全上游）：补完 PPE 直连口的 host-bound RX 交付（即 perceival 邮件问的 gap）

本仓库不做深挖，正确方向见 `docs/FINAL-SUMMARY.md` 和 `docs/qsdk-core-links.md`。
