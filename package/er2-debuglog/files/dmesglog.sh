#!/bin/sh
# 把新增的内核日志持续追加到 eMMC，掉电/卡死都不会丢。
# 由 /etc/init.d/dmesglog（procd 托管）在开机时拉起。

LOG=/etc/bootlog/dmesg.log
MAXLINES=30000
INTERVAL=5

mkdir -p /etc/bootlog

last=0

while true; do
	total=$(dmesg 2>/dev/null | wc -l)

	if [ "$total" -lt "$last" ] 2>/dev/null; then
		# dmesg 环回滚或重启过，重新从头记
		echo "=== dmesg 行数回退 $last -> $total，重置 ===" >> "$LOG"
		last=0
	fi

	if [ "$total" -gt "$last" ] 2>/dev/null; then
		dmesg 2>/dev/null | tail -n +$((last + 1)) >> "$LOG"
		last=$total

		lines=$(wc -l < "$LOG" 2>/dev/null || echo 0)
		if [ "$lines" -gt "$MAXLINES" ] 2>/dev/null; then
			tail -n "$MAXLINES" "$LOG" > "$LOG.tmp" 2>/dev/null && mv -f "$LOG.tmp" "$LOG"
		fi
	fi

	sleep $INTERVAL
done
