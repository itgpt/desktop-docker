#!/bin/bash
# 容器启动后由 desktop-vnc.service 调用：拉起 Xvfb + GNOME + x11vnc + noVNC
set -u

VNC_PORT=${VNC_PORT:-5901}
NOVNC_PORT=${NOVNC_PORT:-6080}
VNC_RESOLUTION=${VNC_RESOLUTION:-1920x1080}
VNC_DEPTH=${VNC_DEPTH:-24}
VNC_PASSWORD=${VNC_PASSWORD:-password}

VNC_USER=vnc
VNC_UID=$(id -u "$VNC_USER")
VNC_HOME=$(getent passwd "$VNC_USER" | cut -d: -f6)
RUNTIME_DIR="/run/user/${VNC_UID}"
BUS="${RUNTIME_DIR}/bus"

log() { echo "[desktop] $*"; }

# ---------------------------------------------------------------- VNC 密码
mkdir -p "${VNC_HOME}/.vnc"
x11vnc -storepasswd "${VNC_PASSWORD}" "${VNC_HOME}/.vnc/passwd" >/dev/null 2>&1
chmod 600 "${VNC_HOME}/.vnc/passwd"
chown "${VNC_USER}:${VNC_USER}" "${VNC_HOME}/.vnc/passwd"
log "VNC 密码已设置"

# ---------------------------------------------------------------- Xvfb
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1
log "启动 Xvfb :1 (${VNC_RESOLUTION}x${VNC_DEPTH})"
Xvfb :1 -screen 0 "${VNC_RESOLUTION}x${VNC_DEPTH}" &
for _ in $(seq 1 40); do
    DISPLAY=:1 xdpyinfo >/dev/null 2>&1 && break
    sleep 0.5
done
if ! DISPLAY=:1 xdpyinfo >/dev/null 2>&1; then
    log "错误：Xvfb 启动失败"
    exit 1
fi
DISPLAY=:1 xset r rate 200 30 2>/dev/null

# ---------------------------------------------------------------- 运行时目录
mkdir -p "${RUNTIME_DIR}"
chmod 700 "${RUNTIME_DIR}"
chown "${VNC_USER}:${VNC_USER}" "${RUNTIME_DIR}"

# ================================================================ 踩坑记录
#  1. 不要自己起 dbus-daemon 占 ${RUNTIME_DIR}/bus。Ubuntu 24.04+ 的用户总线
#     由 systemd 的 dbus.socket / dbus-broker 提供，抢占会让客户端连到错误的
#     总线，org.freedesktop.systemd1 变成不可达，gnome-session 报
#     NameHasNoOwner 后退出。
#  2. 必须给 vnc 用户开启 linger（等价于 loginctl enable-linger）。否则最后一
#     个 logind 会话结束时 user@<uid>.service 会被销毁，systemd --user 一没，
#     GNOME 49 的会话立刻崩。
#  3. Ubuntu 26.04（GNOME 49 + systemd 259）必须有真实 logind 会话，否则报
#     "Could not get session id for session"。用 systemd-run + PAMName=login。
# ================================================================

# 让用户管理器常驻
mkdir -p /var/lib/systemd/linger
touch "/var/lib/systemd/linger/${VNC_USER}"
chmod 0644 "/var/lib/systemd/linger/${VNC_USER}"
systemctl start "user@${VNC_UID}.service" >/dev/null 2>&1 || true

SESSION_ENV=(
    -E "DISPLAY=:1"
    -E "XDG_SESSION_TYPE=x11"
    -E "XDG_SESSION_DESKTOP=ubuntu"
    -E "XDG_CURRENT_DESKTOP=ubuntu:GNOME"
    -E "GNOME_SHELL_SESSION_MODE=ubuntu"
    -E "XDG_RUNTIME_DIR=${RUNTIME_DIR}"
    -E "DBUS_SESSION_BUS_ADDRESS=unix:path=${BUS}"
    -E "LANG=zh_CN.UTF-8"
    -E "LANGUAGE=zh_CN:zh"
    -E "LC_ALL=zh_CN.UTF-8"
    -E "GTK_IM_MODULE=ibus"
    -E "QT_IM_MODULE=ibus"
    -E "XMODIFIERS=@im=ibus"
    -E "XDG_CONFIG_DIRS=/etc/xdg/xdg-ubuntu:/etc/xdg"
    -E "XDG_DATA_DIRS=/usr/share/ubuntu:/usr/share/gnome:/usr/local/share:/usr/share"
)

gnome_shell_running() { pgrep -x gnome-shell >/dev/null 2>&1; }

wait_for_shell() {
    local limit=$1
    for _ in $(seq 1 "$limit"); do
        gnome_shell_running && return 0
        sleep 1
    done
    return 1
}

wait_for_bus() {
    local limit=${1:-60}
    for _ in $(seq 1 "$limit"); do
        [ -S "${BUS}" ] && return 0
        sleep 0.5
    done
    return 1
}

start_gnome_via_logind() {
    log "创建 logind 会话并启动 GNOME"
    systemctl reset-failed gnome-desktop.service >/dev/null 2>&1
    systemd-run --unit=gnome-desktop \
        -p "User=${VNC_USER}" -p "PAMName=login" -p "Type=simple" \
        -p "StandardOutput=journal" -p "StandardError=journal" \
        "${SESSION_ENV[@]}" \
        /usr/bin/gnome-session --session=ubuntu
}

start_gnome_via_su() {
    log "以 su 方式启动 GNOME（回退路径）"
    su - "${VNC_USER}" -s /bin/bash -c "
        export DISPLAY=:1
        export XDG_SESSION_TYPE=x11
        export XDG_SESSION_DESKTOP=ubuntu
        export XDG_CURRENT_DESKTOP=ubuntu:GNOME
        export GNOME_SHELL_SESSION_MODE=ubuntu
        export XDG_RUNTIME_DIR=${RUNTIME_DIR}
        export DBUS_SESSION_BUS_ADDRESS=unix:path=${BUS}
        export LANG=zh_CN.UTF-8
        export LANGUAGE=zh_CN:zh
        export LC_ALL=zh_CN.UTF-8
        export GTK_IM_MODULE=ibus
        export QT_IM_MODULE=ibus
        export XMODIFIERS=@im=ibus
        export XDG_CONFIG_DIRS=/etc/xdg/xdg-ubuntu:/etc/xdg
        export XDG_DATA_DIRS=/usr/share/ubuntu:/usr/share/gnome:/usr/local/share:/usr/share
        gnome-session --session=ubuntu >> /tmp/gnome-session.log 2>&1 &
        disown
    " &
    return 0
}

wait_for_bus 60 || log "警告：未等到用户总线"

if command -v systemd-run >/dev/null 2>&1; then
    start_gnome_via_logind
    if wait_for_shell 45; then
        log "gnome-shell 已就绪（logind 会话）"
    else
        log "logind 方式未成功，回退 su"
        systemctl stop gnome-desktop.service >/dev/null 2>&1
        systemctl reset-failed gnome-desktop.service >/dev/null 2>&1
        start_gnome_via_su
        if wait_for_shell 60; then
            log "gnome-shell 已就绪（su 方式）"
        else
            log "警告：gnome-shell 未能启动，诊断如下"
            journalctl -u gnome-desktop --no-pager -n 25 2>/dev/null
            tail -20 /tmp/gnome-session.log 2>/dev/null
        fi
    fi
else
    start_gnome_via_su
    if wait_for_shell 60; then
        log "gnome-shell 已就绪（su 方式）"
    else
        log "警告：gnome-shell 未能启动"
    fi
fi

# ---------------------------------------------------------------- x11vnc
log "启动 x11vnc :${VNC_PORT}"
x11vnc -display :1 \
    -rfbport "${VNC_PORT}" \
    -rfbauth "${VNC_HOME}/.vnc/passwd" \
    -forever -shared -noxdamage -xkb -bg \
    -o /var/log/x11vnc.log

# ---------------------------------------------------------------- noVNC
# websockify 0.11+ 移除了 --wrap-mode，按可用性自适应
NOVNC_EXTRA=""
if websockify --help 2>&1 | grep -q -- '--wrap-mode'; then
    NOVNC_EXTRA="--wrap-mode=ignore"
fi

log "启动 noVNC :${NOVNC_PORT}"
exec websockify --web=/usr/share/novnc \
    ${NOVNC_EXTRA} \
    --cert=/etc/novnc-cert.pem \
    --key=/etc/novnc-key.pem \
    "${NOVNC_PORT}" \
    "localhost:${VNC_PORT}"
