#!/bin/bash
# =============================================================================
# Ubuntu 26.04+ 桌面启动脚本（Wayland 无头 + RDP）
#
# 背景：Ubuntu 26.04 的 GNOME Shell 50 只支持 Wayland（/usr/share/xsessions 已
# 不存在），原 Xvfb + x11vnc + noVNC 架构失效；GNOME Remote Desktop 50 也移除了
# VNC 后端，只剩 RDP。
#
# 架构：GDM 提供 org.gnome.DisplayManager → gnome-headless-session@<user> 创建
#       无头 Wayland 会话（mutter 虚拟显示器）→ GRD headless 通过 PipeWire 抓屏
#       并以 RDP 协议对外服务。
# =============================================================================
set -u

RDP_PORT=${RDP_PORT:-3389}
RDP_USER=${RDP_USER:-vnc}
# RDP 登录名可以与 Linux 用户不同（GRD 自己管理凭据），默认沿用 Linux 用户
RDP_USERNAME=${RDP_USERNAME:-$RDP_USER}
RDP_PASSWORD=${RDP_PASSWORD:-${VNC_PASSWORD:-password}}

UID_NUM=$(id -u "$RDP_USER" 2>/dev/null || echo 1000)
RUNTIME_DIR="/run/user/${UID_NUM}"
BUS="${RUNTIME_DIR}/bus"

log() { echo "[rdp-desktop] $*"; }

# 以桌面用户身份执行（带上正确的用户总线）
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
# 2. polkit helper 必须 setuid，否则 gnome-shell 的 polkit agent 会无限重试
#    （实测 CPU 飙到 149%，journal 每分钟 5000+ 条报错）
# -----------------------------------------------------------------------------
HELPER=/usr/lib/polkit-1/polkit-agent-helper-1
if [ -f "$HELPER" ]; then
    chmod u+s "$HELPER" 2>/dev/null || true
fi

# -----------------------------------------------------------------------------
# 3. 启动 GDM —— gnome-headless-session@.service 需要 org.gnome.DisplayManager
#    GDM 找不到 DRM 设备会重试几次然后放弃（日志里的 "maximum number of display
#    failures reached"），这是预期行为，不影响无头会话。
# -----------------------------------------------------------------------------
log "启动 GDM（提供 DisplayManager D-Bus）"
systemctl start gdm >/dev/null 2>&1 || true
for _ in $(seq 1 60); do
    busctl --system status org.gnome.DisplayManager >/dev/null 2>&1 && break
    sleep 1
done
if busctl --system status org.gnome.DisplayManager >/dev/null 2>&1; then
    log "DisplayManager 就绪"
else
    log "警告：DisplayManager 未就绪，无头会话可能失败"
fi

# -----------------------------------------------------------------------------
# 4. 创建无头 Wayland 会话
# -----------------------------------------------------------------------------
log "创建无头会话 gnome-headless-session@${RDP_USER}"
systemctl reset-failed "gnome-headless-session@${RDP_USER}.service" >/dev/null 2>&1 || true
systemctl start "gnome-headless-session@${RDP_USER}.service" >/dev/null 2>&1 || true

log "等待 gnome-shell 与用户总线"
SHELL_OK=0
for _ in $(seq 1 120); do
    if [ -S "$BUS" ] && pgrep -x gnome-shell >/dev/null 2>&1; then
        SHELL_OK=1
        break
    fi
    sleep 1
done
if [ "$SHELL_OK" = 1 ]; then
    log "gnome-shell 已运行（Wayland 无头会话）"
else
    log "警告：gnome-shell 未启动，诊断如下"
    journalctl -u "gnome-headless-session@${RDP_USER}" --no-pager -n 20 2>/dev/null
fi

# -----------------------------------------------------------------------------
# 5. TLS 证书
# -----------------------------------------------------------------------------
log "生成 RDP TLS 证书"
as_user "mkdir -p \$HOME/.config/gnome-remote-desktop && \
    openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
        -keyout \$HOME/rdp-key.pem -out \$HOME/rdp-cert.pem \
        -subj /CN=gnome-remote-desktop" >/dev/null 2>&1

# -----------------------------------------------------------------------------
# 6. 配置 GRD headless RDP
# -----------------------------------------------------------------------------
log "配置 RDP（端口 ${RDP_PORT}）"
as_user "grdctl --headless rdp set-tls-cert \$HOME/rdp-cert.pem"  >/dev/null 2>&1
as_user "grdctl --headless rdp set-tls-key  \$HOME/rdp-key.pem"   >/dev/null 2>&1
as_user "grdctl --headless rdp set-port ${RDP_PORT}"              >/dev/null 2>&1
as_user "grdctl --headless rdp disable-view-only"                 >/dev/null 2>&1
as_user "grdctl --headless rdp disable-port-negotiation"          >/dev/null 2>&1

# 凭据通过临时文件喂给 grdctl（避免密码出现在进程列表）
# 注意：文件由 root 创建后必须 chown 给桌面用户，否则 su 过去读不到，
# grdctl 会静默失败，表现为 "Credentials are not set, denying client"。
PWFILE=$(mktemp)
printf '%s\n%s\n' "$RDP_PASSWORD" "$RDP_PASSWORD" > "$PWFILE"
chown "${RDP_USER}:${RDP_USER}" "$PWFILE"
chmod 600 "$PWFILE"
as_user "grdctl --headless rdp set-credentials ${RDP_USERNAME} < ${PWFILE}" >/dev/null 2>&1
CREDS_OK=$(as_user "grdctl --headless status" 2>/dev/null | grep -c "Username: (hidden)")
rm -f "$PWFILE"
if [ "$CREDS_OK" -ge 1 ]; then
    log "RDP 凭据已写入（登录名 ${RDP_USERNAME}）"
else
    log "警告：RDP 凭据写入失败（客户端会被拒绝：Credentials are not set）"
fi

log "启用 RDP"
as_user "grdctl --headless rdp enable" >/dev/null 2>&1

# -----------------------------------------------------------------------------
# 7. 等待端口就绪
# -----------------------------------------------------------------------------
for _ in $(seq 1 60); do
    ss -lnt 2>/dev/null | grep -q ":${RDP_PORT} " && break
    sleep 1
done
if ss -lnt 2>/dev/null | grep -q ":${RDP_PORT} "; then
    log "RDP 已就绪：端口 ${RDP_PORT}，用户 ${RDP_USER}"
else
    log "警告：RDP 端口 ${RDP_PORT} 未监听"
    as_user "journalctl --user -u gnome-remote-desktop-headless -n 20 --no-pager" 2>/dev/null
fi

# -----------------------------------------------------------------------------
# 8. 守护：会话或端口异常时退出，由 systemd（Restart=on-failure）重新拉起
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
