ARG UBUNTU_VERSION=24.04
FROM jockerdragon/docker-systemd:ubuntu-${UBUNTU_VERSION}

ARG UBUNTU_VERSION
ENV DEBIAN_FRONTEND=noninteractive \
    VNC_PORT=5901 \
    NOVNC_PORT=6080 \
    VNC_RESOLUTION=1920x1080 \
    VNC_DEPTH=24 \
    VNC_PASSWORD=password \
    LANG=zh_CN.UTF-8 \
    LANGUAGE=zh_CN:zh \
    LC_ALL=zh_CN.UTF-8 \
    TZ=Asia/Shanghai

# ---------------------------------------------------------------------------
# 1) 桌面基础组件 + 中文环境 + VNC/noVNC 栈
# ---------------------------------------------------------------------------
# 注意：ubuntu-desktop 的很多桌面组件挂在 Recommends 里，这里不能加
# --no-install-recommends，否则会装出一个缺胳膊少腿的桌面。
RUN apt-get update && apt-get install -y \
        ubuntu-desktop \
        language-pack-zh-hans \
        language-pack-gnome-zh-hans \
        fonts-noto-cjk \
        ibus \
        ibus-pinyin \
        tzdata \
        xvfb \
        x11vnc \
        novnc \
        websockify \
        openssl \
        ca-certificates \
        sudo \
        curl \
        wget \
        git \
        vim \
        xdotool \
        xclip \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# 2) 剔除不需要的软件包
#    旧写法直接 `apt-get remove 一堆包名`，只要有一个包在当前 Ubuntu 版本里
#    不存在（例如 26.04 已移除 cheese / gnome-photos），整条命令就会失败，
#    构建随即中断。这里先用 dpkg-query 按模式解析出"实际已安装"的包，再统一
#    卸载，缺失的包自动跳过。
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
#    Ubuntu 24.04 起，仓库里的 firefox 只是 snap 过渡包，容器内没有 snapd，
#    装上也用不了。因此 >= 24.04 直接跳过，统一使用 Google Chrome。
# ---------------------------------------------------------------------------
RUN set -eu; \
    if dpkg --compare-versions "${UBUNTU_VERSION}" lt 24.04; then \
        echo ">>> Ubuntu ${UBUNTU_VERSION}：安装 deb 版 Firefox"; \
        apt-get update; \
        apt-get install -y firefox; \
        rm -rf /var/lib/apt/lists/*; \
    else \
        echo ">>> Ubuntu ${UBUNTU_VERSION}：firefox 为 snap 过渡包，跳过（使用 Chrome）"; \
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
#    linger 必须开启：否则最后一个 logind 会话结束时 user@<uid>.service 会被
#    销毁，systemd --user 一消失，GNOME 会话就崩。
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
# 5b) 容器桌面不需要这些交互打扰：
#     - 跳过 GNOME 首次登录的「初始配置」向导
#     - 屏蔽"有新版本 Ubuntu 可用"的升级提示
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
#     容器里没有 ACPI 事件，acpid 永远用不上。更要命的是 systemd 249
#     （Ubuntu 22.04）有个死循环 bug：acpid.socket 反复触发被 Condition 跳过
#     的 acpid.service，systemd 在同一个时间戳上刷几十万条日志、CPU 烧满、
#     自身被堵死，表现为容器"活着但桌面永远起不来"、docker exec 卡住。
# ---------------------------------------------------------------------------
RUN ln -sf /dev/null /etc/systemd/system/acpid.service && \
    ln -sf /dev/null /etc/systemd/system/acpid.socket && \
    ln -sf /dev/null /etc/systemd/system/acpid.path

# ---------------------------------------------------------------------------
# 6) noVNC 首页 + 自签证书（剪贴板 API 需要 HTTPS）
# ---------------------------------------------------------------------------
RUN ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html && \
    openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
        -keyout /etc/novnc-key.pem \
        -out /etc/novnc-cert.pem \
        -subj "/CN=novnc"

# ---------------------------------------------------------------------------
# 7) GNOME 系统级默认配置：关屏保/锁屏/休眠，预置中文输入法
# ---------------------------------------------------------------------------
RUN mkdir -p /etc/dconf/db/local.d /etc/dconf/profile && \
    printf '[org/gnome/desktop/screensaver]\nlock-enabled=false\nidle-activation-enabled=false\n\n[org/gnome/desktop/session]\nidle-delay=uint32 0\n\n[org/gnome/settings-daemon/plugins/power]\nsleep-inactive-ac-type='"'"'nothing'"'"'\nsleep-inactive-battery-type='"'"'nothing'"'"'\nidle-dim=false\npower-button-action='"'"'nothing'"'"'\n\n[org/gnome/desktop/input-sources]\nsources=[('"'"'ibus'"'"', '"'"'pinyin'"'"'), ('"'"'xkb'"'"', '"'"'us'"'"')]\n' \
        > /etc/dconf/db/local.d/00-nodim && \
    printf 'user-db:user\nsystem-db:local\n' > /etc/dconf/profile/user && \
    dconf update 2>/dev/null || true

# ---------------------------------------------------------------------------
# 8) 启动脚本与 systemd 单元
# ---------------------------------------------------------------------------
COPY start-desktop.sh /usr/local/bin/start-desktop.sh
COPY healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod +x /usr/local/bin/start-desktop.sh /usr/local/bin/healthcheck.sh

COPY desktop-vnc.service /etc/systemd/system/desktop-vnc.service
RUN systemctl enable desktop-vnc.service 2>/dev/null || true

EXPOSE 5901 6080

HEALTHCHECK --interval=30s --timeout=10s --start-period=150s --retries=3 \
    CMD ["/usr/local/bin/healthcheck.sh"]

CMD ["/sbin/init"]
