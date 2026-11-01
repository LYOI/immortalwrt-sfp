# 嵌入式固件 / 网络设备调试方法论

> 沉淀自「太乙 Plus ER2（IPQ5332）SFP 光口 10G 调试」全过程，提炼为可复用的通用逻辑。
> 目标是：换一台设备、换一个固件、换一个问题，也能套用这套思路。

---

## 一、核心心法：分层定位，逐层排除

遇到「某个口/某个功能不通」，不要急着下结论，先问一句：

> **「通」和「不通」的边界到底在哪一层？**

网络问题按自下而上分 7 层，每层都有独立的观测手段，一层一层确认：

| 层 | 观测手段 | 判断标准 |
|---|---|---|
| 物理层（光/电/线） | 交换机指示灯、`/sys/class/net/X/carrier`、`ethtool` | carrier=1 且有速率 |
| PCS/SerDes 层 | `dmesg` 的 link 事件、PCS 寄存器 | `Link is Up - XGbps` |
| 数据链路层（L2） | ARP 能否解析、`ip neigh`、DHCP 能否拿租约 | 邻居表 REACHABLE |
| 网络层（L3） | `ping`、`/proc/net/arp` | ping 通 |
| 传输层（L4/TCP） | `nc`、SSH、`curl`、conntrack | TCP 三次握手成功 |
| 应用层 | 网页、SSH 登录 | 能正常使用 |

**关键教训**：每一层「通」都不代表上一层「通」。本次踩过的坑——
- `carrier=1` 不代表数据面通（物理层 ≠ 数据面）
- `ping` 通不代表 TCP 通（ICMP 无连接、不建流，可能绕过 offload/防火墙）
- 设备「自己 curl 自己」通不代表「跨口转发」通（本地回环不经过转发路径）

---

## 二、最有效的定位手段：抓包对账

「哪个方向丢、丢在哪一段」是网络问题的核心。方法：

### 1. 用计数器对账（最快，无需抓包工具）

在转发路径的每个口记录 `rx_packets`/`tx_packets`，制造一次流量，对比增量：

```sh
# 制造流量前记录基线
cat /sys/class/net/sfp/statistics/rx_packets
cat /sys/class/net/lan2/statistics/tx_packets
# 发起一次 SSH / ping
# 再读一次，看哪个口 +1、哪个口 +0
```

本次决定性发现就是靠这个：
```
lan2 tx +1   ← 发出去了
sfp  tx +1   ← 转发出去了
sfp  rx +1   ← 回包收到了
lan2 rx +0   ← 但没回到 lan2 → 丢包点在这里！
```

### 2. 用「错误计数器」判断丢包性质

- `rx_errors` / `rx_crc_errors` / `rx_length_errors` 有值 → 物理层坏帧
- `rx_dropped` 有值、但 errors 全 0 → 软件/驱动主动丢，不是物理问题
- 所有计数器都是 0、但包就是不见 → 丢在「计数器覆盖不到」的环节（如硬件 offload 内部）

### 3. 用「ping 包大小」区分 MTU 问题

```sh
for s in 64 200 600 1000 1400 1472; do ping -l $s 目标; done
```
- 小包通、大包断 → MTU/帧长问题（阈值很规整）
- 大小包都随机丢 → 不是 MTU，是随机丢包（流控/缓冲区/offload）

---

## 三、关键工具清单

### 运行态观测（刷完固件后，不依赖编译环境）

```sh
# 链路/速率/载波
cat /sys/class/net/eth0/{carrier,speed,duplex,operstate}
# 完整统计（含各种错误）
ls /sys/class/net/eth0/statistics/
# 邻居表（L2 可达性）
ip neigh show            # REACHABLE / STALE / FAILED / INCOMPLETE
# ARP 表
cat /proc/net/arp
# 内核软中断丢包（NAPI backlog 溢出）
cat /proc/net/softnet_stat   # 第2列 dropped，第3列 time_squeeze
# conntrack（TCP 连接状态，判断握手到哪一步）
grep 目标IP /proc/net/nf_conntrack   # SYN_SENT/SYN_RECV/ESTABLISHED/TIME_WAIT
```

### 防火墙/转发层

```sh
nft list ruleset          # fw4 规则（forward/input 链、policy drop）
iptables -L -n -v         # 老版防火墙
# 注意：桥接流量走 table bridge，路由流量走 table inet，两者规则不同！
```

### 硬件引擎专用 debugfs（Qualcomm PPE 类）

```sh
ls /sys/kernel/debug/ppe/
cat /sys/kernel/debug/ppe/reason_counters   # 丢帧的「具体原因」分类计数
cat /sys/kernel/debug/ppe/l2_forward        # 硬件 FDB 转发统计
cat /sys/kernel/debug/ppe/flows             # flow offload 的 reject 原因
cat /sys/kernel/debug/ppe/qca8386_athtag    # 跨界 tag 映射
```

> **reason_counters 是宝藏**：它把丢帧按「drop code」分类，能直接告诉你丢包是
> 「L2 MTU 失败」「无路由」「流控 pause frame」还是「flow 丢弃」，比盲猜强一万倍。

---

## 四、固件逆向分析方法

### 1. 识别固件格式

```sh
xxd 固件.bin | head        # 看 magic
# d00dfeed = OpenWrt FIT 镜像
# 27051956 = uImage
# 找 "ARM64 OpenWrt FIT" 等描述串
```

### 2. 提取 FIT 内的 dtb / kernel / rootfs

FIT 是容器格式，内部有多个 blob，用 Python 遍历 magic 定位：

```python
import struct, re
data = open('fw.bin','rb').read()
# 找 FDT magic (d00dfeed)，读后 4 字节大端 totalsize 判断是否独立 dtb blob
for m in re.finditer(bytes.fromhex('d00dfeed'), data):
    total = struct.unpack('>I', data[m.start()+4:m.start()+8])[0]
    if 1000 < total < 200000:
        print('FDT blob at', m.start(), 'size', total)
        # 提取 data[m.start():m.start()+total] 即为 dtb
```

### 3. 从 dtb 提取字符串，快速看拓扑（无需完整反编译）

```python
# 搜索关键节点名/属性名，看打印上下文
for kw in [b'ess-switch', b'sfp', b'media-type', b'qca8386', b'port@']:
    for m in re.finditer(kw, data):
        # 打印 m.start() 前后的可打印字符串
```

**技巧**：即使没有 `dtc` 反编译工具，直接搜 dtb 里的字符串也能定位「这个口挂在哪、用什么驱动、什么属性」，比完整反编译快得多。

### 4. 判断内核架构（决定驱动方向）

看 dtb 里的 `compatible` 串：
- `qcom,ess-switch-qca8386` → QSDK 闭源 ess-switch 架构（老内核 5.4）
- 上游 `phy-mode` + `pcs-handle` → 主线 phylink + PPE 架构（新内核 6.x）

**这两个架构的驱动完全不同，混用必踩坑。**

---

## 五、改固件 / 重编译的正确姿势

### 教训：改 build_dir 里的解包源码是无效的！

OpenWrt 的构建系统在 `make` 时，会用 `dl/linux-*.tar.xz` 的原始源码**重新解压覆盖**
`build_dir/` 里的源码，所以直接改 build_dir 里的 `.c` 文件，重新 make 会被冲掉。

**正确做法**：改 `target/linux/<平台>/patches-<内核>/` 下的 patch，或新增 patch。

```sh
# 1. 找到该文件的来源 patch
grep -rln "关键函数名\|关键变量" target/linux/*/patches-6.18/

# 2. 新建一个编号递增的 patch（标准 unified diff 格式）
#    Subject + 说明 + --- a/xxx.c +++ b/xxx.c + @@ ... @@

# 3. 删掉内核源码目录，触发干净重建（强制重新解压+重新应用所有 patch）
rm -rf build_dir/*/linux-*/linux-6.18.*
make -j$(nproc)
```

### 验证 patch 是否真的生效

```sh
# 编译后检查源码里改动是否在（md5 会变才是真的重编了）
grep -A3 "你的改动" build_dir/*/linux-*/.../xxx.c
# 固件 md5 应该和上一版不同
md5sum bin/.../sysupgrade.bin
```

---

## 六、刷机与验证

### 系统内升级（sysupgrade）

```sh
scp sysupgrade.bin root@192.168.1.1:/tmp/fw.bin
ssh root@192.168.1.1 'sysupgrade -n /tmp/fw.bin'
# 注意：EXIT=246 + "Connection failed" 是正常的（重启前关闭所有会话）
```

### 判断设备在哪一层

```sh
curl -s http://192.168.1.1/version   # 返回 U-Boot 版本 = 在 uboot
ssh root@192.168.1.1 'uptime'        # 通 = 系统正常
```

### 教训：HTTP 200 ≠ 接口存在

uboot web 是单页应用，任何未知路径都 fallback 返回 200。**看返回的 JSON 内容，不看状态码。**

---

## 七、通用排查思路总结（自查清单）

遇到「某口不通」时，按顺序问自己：

1. **边界在哪？** 是「物理不通」「二层不通」「TCP 不通」还是「应用不通」？（先分清楚）
2. **方向对了吗？** 单向通还是双向通？哪个方向丢？
3. **对照实验做了吗？** 同一个设备、同一个口，只换一个变量（如电口 vs 光口），结果是否不同？
4. **被「假阳性」骗了吗？** ping 通≠TCP 通；自己 curl 自己≠跨口通；carrier=1≠数据面通。
5. **计数器覆盖到这个环节了吗？** 所有计数器都是 0 但包不见，说明丢在计数器盲区（硬件 offload 内部）。
6. **架构对了吗？** 这个口到底挂在哪（PPE？交换芯片？）、走什么驱动？跟参考实现（官方/QSDK）差在哪？

---

## 八、本次最值得记住的一句话

> **「link up」和「数据面通」是两回事。**
> 物理层、PCS 层、二层、ICMP 全通，不代表 TCP 能通——
> 因为 ICMP 无连接、不建流，会绕过 flow offload 和防火墙的状态跟踪，
> 而 TCP 必须经过完整的状态机。任何「只有 sfp 这个口才这样」的怪现象，
> 先怀疑「这个口走的硬件 offload 路径是否完整」，而不是物理层。

---

## 附：本次用到的所有命令速查

```sh
# 链路
cat /sys/class/net/X/{carrier,speed,duplex,mtu}
# 统计
cat /sys/class/net/X/statistics/{rx_packets,tx_packets,rx_errors,rx_dropped,rx_crc_errors}
# 邻居/ARP
ip neigh show; cat /proc/net/arp
# 软中断
cat /proc/net/softnet_stat
# conntrack
grep IP /proc/net/nf_conntrack
# 防火墙
nft list ruleset
# PPE debugfs（Qualcomm）
cat /sys/kernel/debug/ppe/{reason_counters,l2_forward,flows,qca8386_athtag,direct_switch}
# ping 大小扫描
for s in 64 600 1400 1472; do ping -l $s IP; done
# 抓包对账
#   记录各口 rx/tx 基线 → 制造流量 → 看增量
```
