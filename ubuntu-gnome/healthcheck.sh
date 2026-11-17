#!/bin/bash
# 容器健康检查：
#   x11 模式 —— gnome-shell 运行 且 noVNC 可访问
#   rdp 模式 —— gnome-shell 运行 且 RDP 端口在监听（26.04+ 的 Wayland 无头方案）
set -u

MODE=$(cat /etc/desktop-mode 2>/dev/null || echo x11)
NOVNC_PORT=${NOVNC_PORT:-6080}
RDP_PORT=${RDP_PORT:-3389}

if ! pgrep -x gnome-shell > /dev/null 2>&1; then
    echo "unhealthy: gnome-shell 未运行"
    exit 1
fi

if [ "$MODE" = "rdp" ]; then
    if ! ss -lnt 2>/dev/null | grep -q ":${RDP_PORT} "; then
        echo "unhealthy: RDP 端口 ${RDP_PORT} 未监听"
        exit 1
    fi
    echo "healthy (rdp ${RDP_PORT})"
    exit 0
fi

if ! curl -sk --max-time 5 "https://localhost:${NOVNC_PORT}/vnc.html" > /dev/null 2>&1; then
    echo "unhealthy: noVNC ${NOVNC_PORT} 无响应"
    exit 1
fi

echo "healthy (novnc ${NOVNC_PORT})"
exit 0
