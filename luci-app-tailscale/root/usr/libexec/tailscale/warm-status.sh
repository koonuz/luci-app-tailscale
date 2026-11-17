#!/bin/sh
# 开机预热：tailscaled 就绪后自动刷一次状态快照，
# 让重启后首次打开 LuCI 即有完整 peers 数据，不用等后台回填。
# 一次性脚本：完成后退出，不留常驻进程。
# 内存门槛可调：uci set tailscale.warm.min_kb=15000 （默认 25000）
SOCK=/var/run/tailscale/tailscaled.sock
MIN_KB="$(uci -q get tailscale.warm.min_kb 2>/dev/null)"
case "$MIN_KB" in ''|*[!0-9]*) MIN_KB=25000 ;; esac

# 幂等保护：快照 30 分钟内已存在则直接退出（防重复触发）
[ -n "$(find /tmp/tailscale/status-v1.json -mmin -30 2>/dev/null)" ] && exit 0

# 1) 等 daemon socket（最长 90s；tailscale 未启用则静默放弃）
i=0
while [ "$i" -lt 45 ]; do
	[ -S "$SOCK" ] && break
	sleep 2
	i=$((i+1))
done
[ -S "$SOCK" ] || exit 0

# 2) 稳定窗口：再让开机服务安静 20s
sleep 20

# 3) 内存门槛（默认 25MB，防 OOM 底线；不够就等，最多再等 5 分钟）
i=0
while [ "$i" -lt 30 ]; do
	avail="$(awk '/^MemAvailable/{print $2; exit}' /proc/meminfo)"
	[ -n "$avail" ] && [ "$avail" -ge "$MIN_KB" ] && break
	sleep 10
	i=$((i+1))
done

# 4) 刷新快照：开机内存低谷可能被 rpcd 守卫（50MB）拒绝，
#    重试直到成功，最长约 6 分钟；一旦成功立即退出
i=0
while [ "$i" -lt 24 ]; do
	out="$(/usr/libexec/rpcd/tailscale refresh 2>/dev/null)"
	case "$out" in
		*'"ok": true'*) exit 0 ;;
	esac
	[ -s /tmp/tailscale/status-v1.json ] && exit 0
	sleep 15
	i=$((i+1))
done
exit 0
