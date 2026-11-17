ARG UBUNTU_VERSION=24.04
FROM jockerdragon/docker-systemd:ubuntu-${UBUNTU_VERSION}

ARG UBUNTU_VERSION
ENV DEBIAN_FRONTEND=noninteractive \
    VNC_PORT=5901 \
    NOVNC_PORT=6080 \
    RDP_PORT=3389 \
    VNC_RESOLUTION=1920x1080 \
    VNC_DEPTH=24 \
    VNC_PASSWORD=password \
    LANG=zh_CN.UTF-8 \
    LANGUAGE=zh_CN:zh \
    LC_ALL=zh_CN.UTF-8 \
    TZ=Asia/Shanghai

# ---------------------------------------------------------------------------
# 1) 桌面基础组件 + 中文环境
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y \
        ubuntu-desktop \
        language-pack-zh-hans \
        language-pack-gnome-zh-hans \
        fonts-noto-cjk \
        ibus \
        ibus-pinyin \
        tzdata \
        openssl \
        ca-certificates \
        sudo \
        curl \
        wget \
        git \
        vim \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# 1b) X11 / noVNC 栈
#     Ubuntu 26.04 起 GNOME Shell 只有 Wayland，这套用不上了，改走 RDP，
#     因此只给 26.04 以前的版本安装。
# ---------------------------------------------------------------------------
RUN set -eu; \
    if dpkg --compare-versions "${UBUNTU_VERSION}" lt 26.04; then \
        echo ">>> ${UBUNTU_VERSION}：安装 X11 + noVNC 组件"; \
        apt-get update; \
        apt-get install -y xvfb x11vnc novnc websockify xdotool xclip; \
        apt-get clean; \
        rm -rf /var/lib/apt/lists/*; \
    else \
        echo ">>> ${UBUNTU_VERSION}：跳过 X11/noVNC（使用 Wayland 无头 + RDP）"; \
    fi

# ---------------------------------------------------------------------------
# 2) 剔除不需要的软件包
#    直接 `apt-get remove 一堆包名`，只要有一个包在当前版本不存在就会失败。
#    这里先用 dpkg-query 按模式解析出"实际已安装"的包，再统一卸载。
# ---------------------------------------------------------------------------
RUN set -eu; \
    to_purge=""; \
    for pat in \
        'libreoffice*' thunderbird rhythmbox totem shotwell transmission-gtk remmina \
        gnome-games aisleriot gnome-mahjongg gnome-mines gnome-sudoku cheese gnome-photos \
        simple-scan gnome-calendar gnome-clocks gnome-weather gnome-maps gnome-contacts \
        gnome-music deja-dup brltty orca hplip 'printer-driver-*' 'foomatic-db*' \
        openprinting-ppds cups-browsed sane-utils usb-creator-gtk usb-modeswitch; do \
        for p in $(dpkg-query -W -f='${Package}\n' "$pat" 2>/dev/null || true); do \
            to_purge="$to_purge $p"; \
        done; \
    done; \
    if dpkg --compare-versions "${UBUNTU_VERSION}" ge 22.04; then \
        for p in $(dpkg-query -W -f='${Package}\n' 'firefox*' 2>/dev/null || true); do \
            to_purge="$to_purge $p"; \
        done; \
    fi; \
    if [ -n "$to_purge" ]; then \
        echo ">>> 卸载：$to_purge"; \
        apt-get purge -y $to_purge; \
    else \
        echo ">>> 没有需要卸载的包"; \
    fi; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# 3) 浏览器
#    Ubuntu 22.04 起仓库里的 firefox 已是 snap 过渡包，且 ubuntu-desktop 会把它
#    作为推荐包带进来，所以 22.04+ 必须显式卸载（见上一节）；只有 20.04 装真货。
# ---------------------------------------------------------------------------
RUN set -eu; \
    if dpkg --compare-versions "${UBUNTU_VERSION}" lt 22.04; then \
        echo ">>> ${UBUNTU_VERSION}：安装 deb 版 Firefox"; \
        apt-get update; \
        apt-get install -y firefox; \
        rm -rf /var/lib/apt/lists/*; \
    else \
        echo ">>> ${UBUNTU_VERSION}：firefox 为 snap 过渡包，已移除，使用 Chrome"; \
        rm -f /usr/share/applications/firefox.desktop; \
    fi

RUN set -eu; \
    wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -O /tmp/chrome.deb; \
    apt-get update; \
    apt-get install -y /tmp/chrome.deb; \
    rm -f /tmp/chrome.deb; \
    rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# 4) 时区与语言
# ---------------------------------------------------------------------------
RUN ln -snf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    echo "Asia/Shanghai" > /etc/timezone && \
    dpkg-reconfigure -f noninteractive tzdata && \
    locale-gen zh_CN.UTF-8 && \
    update-locale LANG=zh_CN.UTF-8

# ---------------------------------------------------------------------------
# 5) 桌面用户
#    linger 必须开启：否则最后一个 logind 会话结束时 user@<uid>.service 销毁，
#    systemd --user 一消失 GNOME 会话就崩。
# ---------------------------------------------------------------------------
RUN useradd -m -s /bin/bash vnc && \
    echo "vnc:vnc" | chpasswd && \
    usermod -aG sudo vnc && \
    printf 'vnc ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/vnc && \
    chmod 440 /etc/sudoers.d/vnc && \
    mkdir -p /var/lib/systemd/linger && \
    touch /var/lib/systemd/linger/vnc && \
    chmod 0644 /var/lib/systemd/linger/vnc

# ---------------------------------------------------------------------------
# 5b) 跳过 GNOME「初始配置」向导，屏蔽升级提示
# ---------------------------------------------------------------------------
RUN mkdir -p /home/vnc/.config && \
    touch /home/vnc/.config/gnome-initial-setup-done && \
    chown -R vnc:vnc /home/vnc/.config && \
    (systemctl mask update-notifier-release.service \
        update-notifier-release.path \
        update-notifier-crash.service \
        update-notifier-crash.path 2>/dev/null || true)

# ---------------------------------------------------------------------------
# 5c) 屏蔽 acpid 相关单元
#     容器里没有 ACPI 事件。更要命的是 systemd 249（Ubuntu 22.04）有个死循环
#     bug：acpid.socket 反复触发被 Condition 跳过的 acpid.service，日志每秒刷
#     上千条、CPU 烧满、systemd 自身被堵死，表现为容器"活着但桌面起不来"。
# ---------------------------------------------------------------------------
RUN ln -sf /dev/null /etc/systemd/system/acpid.service && \
    ln -sf /dev/null /etc/systemd/system/acpid.socket && \
    ln -sf /dev/null /etc/systemd/system/acpid.path

# ---------------------------------------------------------------------------
# 6) noVNC 首页 + 自签证书（仅 X11 模式需要）
# ---------------------------------------------------------------------------
RUN if [ -d /usr/share/novnc ]; then \
        ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html && \
        openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
            -keyout /etc/novnc-key.pem \
            -out /etc/novnc-cert.pem \
            -subj "/CN=novnc"; \
    else \
        echo "跳过 noVNC 证书（RDP 模式）"; \
    fi

# ---------------------------------------------------------------------------
# 7) GNOME 系统级默认配置：关屏保/锁屏/休眠，预置中文输入法
# ---------------------------------------------------------------------------
RUN mkdir -p /etc/dconf/db/local.d /etc/dconf/profile && \
    printf '[org/gnome/desktop/screensaver]\nlock-enabled=false\nidle-activation-enabled=false\n\n[org/gnome/desktop/session]\nidle-delay=uint32 0\n\n[org/gnome/settings-daemon/plugins/power]\nsleep-inactive-ac-type='"'"'nothing'"'"'\nsleep-inactive-battery-type='"'"'nothing'"'"'\nidle-dim=false\npower-button-action='"'"'nothing'"'"'\n\n[org/gnome/desktop/input-sources]\nsources=[('"'"'ibus'"'"', '"'"'pinyin'"'"'), ('"'"'xkb'"'"', '"'"'us'"'"')]\n' \
        > /etc/dconf/db/local.d/00-nodim && \
    printf 'user-db:user\nsystem-db:local\n' > /etc/dconf/profile/user && \
    dconf update 2>/dev/null || true

# ---------------------------------------------------------------------------
# 8) 版本分流：26.04+ 走 Wayland 无头 + RDP
#    - 允许 gnome-headless-session@ 通过 polkit 创建无头会话
#    - 恢复 polkit-agent-helper 的 setuid 位（否则 gnome-shell 的 polkit agent
#      会无限重试，实测 CPU 149%、journal 每分钟 5000+ 条报错）
#    - 屏蔽 colord（容器无色彩设备，否则会弹授权框）
#    - 屏蔽 gnome-initial-setup 的登录/升级向导
# ---------------------------------------------------------------------------
COPY 49-gnome-headless.rules /tmp/49-gnome-headless.rules

RUN set -eu; \
    if dpkg --compare-versions "${UBUNTU_VERSION}" ge 26.04; then \
        echo ">>> ${UBUNTU_VERSION}：配置 Wayland 无头 + RDP"; \
        apt-get update; \
        apt-get install -y gnome-remote-desktop gdm3; \
        rm -rf /var/lib/apt/lists/*; \
        mkdir -p /etc/polkit-1/rules.d; \
        cp /tmp/49-gnome-headless.rules /etc/polkit-1/rules.d/49-gnome-headless.rules; \
        chmod 644 /etc/polkit-1/rules.d/49-gnome-headless.rules; \
        chmod u+s /usr/lib/polkit-1/polkit-agent-helper-1 2>/dev/null || true; \
        systemctl mask colord.service 2>/dev/null || true; \
        mkdir -p /home/vnc/.config/systemd/user; \
        ln -sf /dev/null /home/vnc/.config/systemd/user/gnome-initial-setup-first-login.service; \
        ln -sf /dev/null /home/vnc/.config/systemd/user/gnome-initial-setup-upgrade-login.service; \
        chown -R vnc:vnc /home/vnc/.config; \
        echo rdp > /etc/desktop-mode; \
    else \
        echo ">>> ${UBUNTU_VERSION}：使用 X11 + noVNC"; \
        echo x11 > /etc/desktop-mode; \
    fi; \
    rm -f /tmp/49-gnome-headless.rules

# ---------------------------------------------------------------------------
# 9) 启动脚本与 systemd 单元（按版本二选一）
# ---------------------------------------------------------------------------
COPY start-desktop.sh /usr/local/bin/start-desktop.sh
COPY start-desktop-rdp.sh /usr/local/bin/start-desktop-rdp.sh
COPY healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod +x /usr/local/bin/start-desktop.sh /usr/local/bin/start-desktop-rdp.sh /usr/local/bin/healthcheck.sh

COPY desktop-vnc.service /etc/systemd/system/desktop-vnc.service
COPY desktop-rdp.service /etc/systemd/system/desktop-rdp.service

RUN set -eu; \
    if [ "$(cat /etc/desktop-mode)" = "rdp" ]; then \
        systemctl enable desktop-rdp.service 2>/dev/null || true; \
        echo ">>> 已启用 desktop-rdp.service"; \
    else \
        systemctl enable desktop-vnc.service 2>/dev/null || true; \
        echo ">>> 已启用 desktop-vnc.service"; \
    fi

EXPOSE 5901 6080 3389

HEALTHCHECK --interval=30s --timeout=10s --start-period=180s --retries=3 \
    CMD ["/usr/local/bin/healthcheck.sh"]

CMD ["/sbin/init"]
