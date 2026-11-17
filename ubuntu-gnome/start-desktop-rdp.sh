#!/bin/bash
# =============================================================================
# Wayland 无头 + RDP 桌面启动脚本（Ubuntu 24.04 / 26.04）
#
# 两条路径，按系统里有没有 GDM 的无头会话单元自动选择：
#
#   A. 26.04（有 gnome-headless-session@.service）
#        GDM → gdm-new-session --headless → 无头会话 → GRD headless
#
#   B. 24.04（没有该单元）
#        自己用 systemd-run + PAMName=login 建会话，直接跑
#        gnome-shell --wayland --headless --virtual-monitor → GRD headless
#
# 背景：这两个版本的 GNOME 都只支持 Wayland，原 Xvfb + x11vnc 方案失效；
#       同时 GNOME Remote Desktop 移除了 VNC 后端，只能走 RDP。
# =============================================================================
set -u

RDP_PORT=${RDP_PORT:-3389}
RDP_USER=${RDP_USER:-vnc}
RDP_USERNAME=${RDP_USERNAME:-$RDP_USER}
RDP_PASSWORD=${RDP_PASSWORD:-${VNC_PASSWORD:-password}}
RESOLUTION=${VNC_RESOLUTION:-1920x1080}

UID_NUM=$(id -u "$RDP_USER" 2>/dev/null || echo 1000)
RUNTIME_DIR="/run/user/${UID_NUM}"
BUS="${RUNTIME_DIR}/bus"

log() { echo "[rdp-desktop] $*"; }

as_user() {
    su - "$RDP_USER" -s /bin/bash -c \
        "export XDG_RUNTIME_DIR=${RUNTIME_DIR}; export DBUS_SESSION_BUS_ADDRESS=unix:path=${BUS}; $1"
}

# -----------------------------------------------------------------------------
# 1. linger：否则最后一个 logind 会话结束时 user@<uid>.service 被销毁
# -----------------------------------------------------------------------------
mkdir -p /var/lib/systemd/linger
touch "/var/lib/systemd/linger/${RDP_USER}"
chmod 0644 "/var/lib/systemd/linger/${RDP_USER}"
systemctl start "user@${UID_NUM}.service" >/dev/null 2>&1 || true

# -----------------------------------------------------------------------------
# 2. polkit helper 必须 setuid，否则 gnome-shell 的 polkit agent 无限重试
#    （实测 CPU 149%、journal 每分钟 5000+ 条报错）
# -----------------------------------------------------------------------------
HELPER=/usr/lib/polkit-1/polkit-agent-helper-1
[ -f "$HELPER" ] && chmod u+s "$HELPER" 2>/dev/null || true

# -----------------------------------------------------------------------------
# 3. 创建无头 Wayland 会话
# -----------------------------------------------------------------------------
HAS_GDM_HEADLESS=0
[ -f /usr/lib/systemd/system/gnome-headless-session@.service ] && HAS_GDM_HEADLESS=1

if [ "$HAS_GDM_HEADLESS" = 1 ]; then
    # --- A. 26.04：走 GDM 的无头会话 ---
    log "使用 GDM 无头会话路径"
    systemctl start gdm >/dev/null 2>&1 || true
    for _ in $(seq 1 60); do
        busctl --system status org.gnome.DisplayManager >/dev/null 2>&1 && break
        sleep 1
    done

    systemctl reset-failed "gnome-headless-session@${RDP_USER}.service" >/dev/null 2>&1 || true
    systemctl start "gnome-headless-session@${RDP_USER}.service" >/dev/null 2>&1 || true

    for _ in $(seq 1 120); do
        if [ -S "$BUS" ] && pgrep -x gnome-shell >/dev/null 2>&1; then break; fi
        sleep 1
    done
else
    # --- B. 24.04：手工拉起无头合成器 ---
    log "使用手工无头合成器路径"
    systemctl reset-failed gnome-headless-shell.service >/dev/null 2>&1 || true
    systemctl stop gnome-headless-shell.service >/dev/null 2>&1 || true
    systemd-run --unit=gnome-headless-shell \
        -p "User=${RDP_USER}" -p "PAMName=login" -p Type=simple \
        -p StandardOutput=journal -p StandardError=journal \
        -E "XDG_RUNTIME_DIR=${RUNTIME_DIR}" \
        -E "XDG_SESSION_TYPE=wayland" \
        -E "XDG_SESSION_DESKTOP=ubuntu" \
        -E "XDG_CURRENT_DESKTOP=ubuntu:GNOME" \
        -E "GNOME_SHELL_SESSION_MODE=ubuntu" \
        -E "LANG=zh_CN.UTF-8" -E "LANGUAGE=zh_CN:zh" \
        /usr/bin/gnome-shell --wayland --headless --virtual-monitor "${RESOLUTION}" \
        >/dev/null 2>&1

    for _ in $(seq 1 60); do
        [ "$(systemctl is-active gnome-headless-shell 2>/dev/null)" = "active" ] && break
        sleep 1
    done
fi

# gnome-shell 起来还需要一点时间，单独等一下再判断
for _ in $(seq 1 60); do
    pgrep -x gnome-shell >/dev/null 2>&1 && break
    sleep 1
done

if pgrep -x gnome-shell >/dev/null 2>&1; then
    log "gnome-shell 已运行（Wayland 无头会话）"
else
    log "警告：gnome-shell 未启动"
    journalctl -u gnome-headless-shell -u "gnome-headless-session@${RDP_USER}" --no-pager -n 20 2>/dev/null
fi

# -----------------------------------------------------------------------------
# 4. TLS 证书
# -----------------------------------------------------------------------------
log "生成 RDP TLS 证书"
as_user "openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
    -keyout \$HOME/rdp-key.pem -out \$HOME/rdp-cert.pem \
    -subj /CN=gnome-remote-desktop" >/dev/null 2>&1

# -----------------------------------------------------------------------------
# 5. 配置 GRD RDP
#    - 24.04 / 26.04 都支持 --headless 模式
#    - set-credentials 的参数个数两版不同：24.04 要两个参数，26.04 一个参数+stdin
# -----------------------------------------------------------------------------
GRD_MODE=""
if as_user "grdctl --help" 2>/dev/null | grep -q -- "--headless"; then
    GRD_MODE="--headless"
    log "使用 GRD headless 模式"
fi

log "配置 RDP（端口 ${RDP_PORT}）"
as_user "grdctl ${GRD_MODE} rdp set-tls-cert \$HOME/rdp-cert.pem" >/dev/null 2>&1 || true
as_user "grdctl ${GRD_MODE} rdp set-tls-key  \$HOME/rdp-key.pem"  >/dev/null 2>&1 || true
as_user "grdctl ${GRD_MODE} rdp set-port ${RDP_PORT}"             >/dev/null 2>&1 || true
as_user "grdctl ${GRD_MODE} rdp disable-view-only"                >/dev/null 2>&1 || true

# 先试两参数写法（24.04）
CREDS_OK=0
if as_user "grdctl ${GRD_MODE} rdp set-credentials ${RDP_USERNAME} '${RDP_PASSWORD}'" >/dev/null 2>&1; then
    as_user "grdctl ${GRD_MODE} status" 2>/dev/null | grep -q "Username: (hidden)" && CREDS_OK=1
fi
# 失败则回退到 stdin 写法（26.04）
if [ "$CREDS_OK" != 1 ]; then
    PWFILE=$(mktemp)
    printf '%s\n%s\n' "$RDP_PASSWORD" "$RDP_PASSWORD" > "$PWFILE"
    chown "${RDP_USER}:${RDP_USER}" "$PWFILE" 2>/dev/null || true
    chmod 600 "$PWFILE"
    as_user "grdctl ${GRD_MODE} rdp set-credentials ${RDP_USERNAME} < ${PWFILE}" >/dev/null 2>&1
    rm -f "$PWFILE"
    as_user "grdctl ${GRD_MODE} status" 2>/dev/null | grep -q "Username: (hidden)" && CREDS_OK=1
fi

if [ "$CREDS_OK" = 1 ]; then
    log "RDP 凭据已写入（登录名 ${RDP_USERNAME}）"
else
    log "警告：RDP 凭据写入失败，客户端会被拒绝（Credentials are not set）"
fi

# -----------------------------------------------------------------------------
# 6. 启用并重启 GRD —— 守护进程只在启动时读取凭据，改完必须重启
# -----------------------------------------------------------------------------
log "启用 RDP 服务"
as_user "grdctl ${GRD_MODE} rdp enable" >/dev/null 2>&1 || true

SVC="gnome-remote-desktop-headless"
as_user "systemctl --user start ${SVC}" >/dev/null 2>&1 || true
as_user "systemctl --user restart ${SVC}" >/dev/null 2>&1 || true

for _ in $(seq 1 60); do
    ss -lnt 2>/dev/null | grep -q ":${RDP_PORT} " && break
    sleep 1
done

if ss -lnt 2>/dev/null | grep -q ":${RDP_PORT} "; then
    log "RDP 已就绪：端口 ${RDP_PORT}，用户 ${RDP_USERNAME}"
else
    log "警告：RDP 端口 ${RDP_PORT} 未监听"
    as_user "journalctl --user -u ${SVC} -n 20 --no-pager" 2>/dev/null
fi

# -----------------------------------------------------------------------------
# 7. 守护：异常退出以触发 systemd 重启
# -----------------------------------------------------------------------------
log "进入守护模式"
while true; do
    bad=0
    pgrep -x gnome-shell >/dev/null 2>&1 || bad=1
    ss -lnt 2>/dev/null | grep -q ":${RDP_PORT} " || bad=1
    if [ "$bad" = 1 ]; then
        log "检测到 gnome-shell 或 RDP 端口异常，退出以触发重启"
        exit 1
    fi
    sleep 30
done
