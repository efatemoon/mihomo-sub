#!/bin/sh
# Mihomo + Subconverter 容器启动脚本

SUB_SCRIPT="/usr/local/bin/sub.sh"
LOG_FILE="/root/.config/mihomo/log.txt"
CONFIG_FILE="/root/.config/mihomo/config.yaml"
SUBCONV_PORT="${subconv_port:-25500}"
MIHOMO_MIXED_PORT="${mihomo_mixed_port:-7890}"

echo "=========================================="
echo "  Mihomo + Subconverter 容器正在启动..."
echo "=========================================="

# 写入基础配置，确保 Mihomo 启动时使用的端口与环境变量一致
#（后续 sub.sh 会在此基础上覆盖完整的订阅配置）
echo "[$(date +"%Y-%m-%d %H:%M:%S %z")] [0/4] 写入 Mihomo 基础配置 (mixed-port: ${MIHOMO_MIXED_PORT})..."
mkdir -p "$(dirname "$CONFIG_FILE")"
cat > "$CONFIG_FILE" <<EOF
mixed-port: ${MIHOMO_MIXED_PORT}
external-ui: /root/.config/mihomo/ui
allow-lan: true
external-controller: :9090
EOF

# 后台启动 subconverter（在其 own 目录下运行，确保读取 /subconverter/pref.toml）
echo "[$(date +"%Y-%m-%d %H:%M:%S %z")] [1/4] 启动 Subconverter 服务 (端口: ${SUBCONV_PORT})..."
(cd /subconverter && ./subconverter) &
echo "[$(date +"%Y-%m-%d %H:%M:%S %z")]       Subconverter 已后台运行"

# 配置 crontab：按 cron 定时执行订阅脚本（cron 为空则不创建定时任务）
echo "[$(date +"%Y-%m-%d %H:%M:%S %z")] [2/4] 配置定时任务 (cron: ${cron:-未设置})..."
if [ -n "$cron" ]; then
	echo "${cron} $SUB_SCRIPT >> $LOG_FILE 2>&1" > /etc/crontabs/root
	crond -d 8 &
	echo "[$(date +"%Y-%m-%d %H:%M:%S %z")]       crond 已后台运行，将按计划更新订阅"
else
	echo "[$(date +"%Y-%m-%d %H:%M:%S %z")]       cron 未设置，跳过定时任务"
fi

# 等待 Subconverter 就绪后执行首次订阅转换（轮询替代固定 sleep，避免启动慢时失败）
echo "[$(date +"%Y-%m-%d %H:%M:%S %z")] [3/4] 等待 Subconverter 就绪并执行首次订阅转换..."
ready=false
for i in $(seq 1 30); do
	if curl -s --max-time 1 "http://127.0.0.1:${SUBCONV_PORT}/" >/dev/null 2>&1; then
		echo "[$(date +"%Y-%m-%d %H:%M:%S %z")]       Subconverter 已就绪 (${i}s)"
		ready=true
		break
	fi
	sleep 1
done
if [ "$ready" = false ]; then
	echo "[$(date +"%Y-%m-%d %H:%M:%S %z")]       Warning: Subconverter 在 30s 内未就绪，继续执行订阅转换..."
fi
"$SUB_SCRIPT" && echo "[$(date +"%Y-%m-%d %H:%M:%S %z")]       首次订阅转换完成" || echo "[$(date +"%Y-%m-%d %H:%M:%S %z")]       订阅转换执行完毕（请检查日志: $LOG_FILE）"

# 前台运行 mihomo（容器主进程）
echo "[$(date +"%Y-%m-%d %H:%M:%S %z")] [4/4] 启动 Mihomo（前台运行，日志见下方）..."
echo "=========================================="
echo "  提示: 按 Ctrl+C 可停止容器"
echo "=========================================="
exec /mihomo
