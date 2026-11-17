#!/bin/bash
# =============================================================================
# 修改 RDP 登录用户名与密码（26.04 Wayland 版本专用）
#
# 用法：
#   docker exec -it <容器名> /usr/local/bin/set-rdp-creds.sh <新用户名> <新密码>
#
# 说明：
#   RDP 的登录凭据由 GNOME Remote Desktop 自己管理，与 Linux 用户名 vnc 无关，
#   所以用户名可以随意指定（不必是系统里存在的账号）。
#   grdctl 只写配置，运行中的守护进程不会立刻加载，脚本会自动重启它。
# =============================================================================
set -u

if [ $# -ne 2 ]; then
    echo "用法: $0 <用户名> <密码>"
    exit 1
fi

USER_NAME="$1"
PASSWORD="$2"

# 找到桌面用户（默认 vnc）及其运行目录
DESKTOP_USER="${RDP_USER:-vnc}"
UID_NUM=$(id -u "$DESKTOP_USER" 2>/dev/null || echo 1001)
RUNTIME_DIR="/run/user/${UID_NUM}"
BUS="${RUNTIME_DIR}/bus"

RUN() {
    su - "$DESKTOP_USER" -s /bin/bash -c \
        "export XDG_RUNTIME_DIR=${RUNTIME_DIR}; export DBUS_SESSION_BUS_ADDRESS=unix:path=${BUS}; $1"
}

# 凭据通过临时文件传入，避免密码出现在进程列表里；文件必须让桌面用户可读
F=$(mktemp /tmp/rdpw.XXXXXX)
printf '%s\n%s\n' "$PASSWORD" "$PASSWORD" > "$F"
chown "${DESKTOP_USER}:${DESKTOP_USER}" "$F"
chmod 600 "$F"

RUN "grdctl --headless rdp set-credentials ${USER_NAME} < ${F}" >/dev/null 2>&1
RC=$?
rm -f "$F"

if [ "$RC" -ne 0 ]; then
    echo "错误：写入凭据失败（grdctl 返回 $RC）"
    exit 1
fi
echo "凭据已写入"

# 关键步骤：重启守护进程才会加载新凭据
RUN "systemctl --user restart gnome-remote-desktop-headless" >/dev/null 2>&1
sleep 1

OK=0
for _ in $(seq 1 30); do
    if ss -lnt 2>/dev/null | grep -q ':3389 '; then OK=1; break; fi
    sleep 0.5
done

if [ "$OK" = 1 ]; then
    echo "已生效：RDP 用户名 = ${USER_NAME}，端口 3389 正常监听"
else
    echo "警告：守护进程已重启，但 3389 未在监听，请检查 journalctl --user -u gnome-remote-desktop-headless"
    exit 1
fi
