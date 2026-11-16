#!/bin/bash
# 容器健康检查：桌面进程存在 且 noVNC 可访问
set -u

NOVNC_PORT=${NOVNC_PORT:-6080}

# GNOME 会话是否真的起来了
if ! pgrep -x gnome-shell > /dev/null 2>&1; then
    echo "unhealthy: gnome-shell 未运行"
    exit 1
fi

# noVNC 是否响应
if ! curl -sk --max-time 5 "https://localhost:${NOVNC_PORT}/vnc.html" > /dev/null 2>&1; then
    echo "unhealthy: noVNC ${NOVNC_PORT} 无响应"
    exit 1
fi

echo "healthy"
exit 0
