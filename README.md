# Ubuntu GNOME Desktop in Docker

基于 [jockerdragon/docker-systemd](https://hub.docker.com/r/jockerdragon/docker-systemd) 的完整 Ubuntu GNOME 桌面容器。

- **Ubuntu 20.04 / 22.04**：X11 + Xvfb + x11vnc + **noVNC**，浏览器直接访问
- **Ubuntu 24.04 / 26.04**：Wayland 无头 + GNOME Remote Desktop + **RDP**，用 RDP 客户端连接

## 预览

![预览1](images/image.png)

![预览2](images/image_copy.png)

![预览3](images/image_copy_3.png)

## 版本支持

| 标签 | Ubuntu | GNOME | 桌面协议 | 访问方式 | 状态 |
|---|---|---|---|---|---|
| `2004` | 20.04 | 3.36 | X11 | noVNC :6080 / VNC :5901 | ✅ |
| `2204` | 22.04 | 42 | X11 | noVNC :6080 / VNC :5901 | ✅ |
| `2404` | 24.04 | 46 | **Wayland** | **RDP :3389** | ✅ |
| `2604` | 26.04 | 50 | **Wayland** | **RDP :3389** | ✅ |

### 为什么 24.04 / 26.04 走 RDP

这两个版本改用 GNOME 官方支持的无头路线，容器里不再有 Xvfb / x11vnc / noVNC：

```
无头 Wayland GNOME 会话（mutter 虚拟显示器）
  └─ gnome-remote-desktop-headless.service → RDP :3389
```

两个版本建立会话的方式不同，脚本会自动识别：

| 版本 | 无头会话怎么来 |
|---|---|
| 24.04 | 没有 `gnome-headless-session@` 单元，用 `systemd-run` + `PAMName=login` 直接跑 `gnome-shell --wayland --headless --virtual-monitor` |
| 26.04 | 有官方单元：GDM → `gdm-new-session --headless` → `gnome-headless-session@vnc.service` |

> 26.04 额外需要这套的原因：GNOME Shell 50 已经**移除 X11 会话**（`/usr/share/xsessions` 目录都不存在），
> 且 GNOME Remote Desktop 50 **移除了 VNC 后端**，只能走 RDP。
>
> 22.04 暂未切换：它的 GNOME Remote Desktop 是 42.9，RDP 凭据依赖 libsecret/keyring，
> 在无 keyring 服务的容器里 `set-credentials` 会静默失败（`Username: (empty)`），
> 导致客户端被拒（`Credentials are not set`）。20.04 的 GNOME 3.36 没有可用的无头 RDP 能力。

## 特性

- 完整 Ubuntu GNOME 桌面（ubuntu-desktop）
- systemd 作为 PID 1，保证 GNOME 会话正常运行
- 中文界面 + 拼音输入法（ibus-pinyin），时区 Asia/Shanghai
- 内置 Google Chrome（Ubuntu 22.04 起 firefox 仅为 snap 过渡包，已自动移除）
- 内置健康检查（HEALTHCHECK），按 `/etc/desktop-mode` 自动选择检查 noVNC 还是 RDP
- 跳过 GNOME「初始配置」向导，屏蔽升级提示
- 提供 docker compose 一键部署

## 前置要求

### 1. 宿主机必须启用 cgroup v2

**这是最容易踩的坑。** Ubuntu 24.04+ 的 systemd 要求 cgroup v2；如果宿主机还是
cgroup v1 混合模式，容器会**启动后立刻退出（退出码 255），且日志为空**。

容器内对应的报错是：

```
Detected cgroup v1 hierarchy at /sys/fs/cgroup/, which is no longer
supported by current version of systemd.
[!!!!!!] Detected unsupported legacy cgroup hierarchy, refusing execution.
```

**WSL2**：在 `%USERPROFILE%\.wslconfig` 中加上

```ini
[wsl2]
kernelCommandLine = cgroup_no_v1=all systemd.unified_cgroup_hierarchy=1
```

然后 `wsl --shutdown` 重启 WSL。验证：`stat -fc %T /sys/fs/cgroup` 应输出 `cgroup2fs`。

**普通 Linux**：内核启动参数加上 `systemd.unified_cgroup_hierarchy=1`。

### 2. 内存

单个桌面容器常驻约 **0.6~2.5 GB**（24.04 RDP 空载实测约 620 MB，26.04 约 820 MB，
X11 版本约 1.1 GB）。同时运行多个容器时请预留足够内存，否则宿主机 OOM 会直接杀掉
`dockerd`，表现为所有容器同时"莫名退出"。compose 里已用 `mem_limit: 4g` 做保护。

### 3. 特权模式

systemd 需要 `--privileged`，无法用普通权限运行。

## 快速开始

### 方式一：docker compose（推荐）

```bash
docker compose up -d gnome-2404   # 24.04（RDP）
docker compose up -d gnome-2604   # 26.04（RDP）
docker compose up -d gnome-2004   # 20.04（浏览器 noVNC）
```

### 方式二：docker run

**X11 版本（20.04 / 22.04）**

```bash
docker run -d \
  --privileged --name gnome-desktop --shm-size=2g --memory=4g \
  -p 6080:6080 -p 5901:5901 \
  -e VNC_PASSWORD=yourpassword \
  muaimingjunbot/ubuntu-gnome-vnc:2204
```

浏览器打开 `https://localhost:6080`，证书告警点「高级」→「继续访问」，输入密码。

**Wayland/RDP 版本（24.04 / 26.04）**

```bash
docker run -d \
  --privileged --name gnome-2404 --shm-size=2g --memory=4g \
  -p 3389:3389 \
  -e VNC_PASSWORD=yourpassword \
  muaimingjunbot/ubuntu-gnome-vnc:2404
```

用任意 RDP 客户端（Windows `mstsc` / Microsoft Remote Desktop / Remmina / FreeRDP）连接
`localhost:3389`，用户名 `vnc`，密码为你设置的 `VNC_PASSWORD`。

```bash
# 命令行验证
xfreerdp /v:localhost:3389 /u:vnc /p:yourpassword /cert:ignore
```

首次启动约 10 秒即可连（健康检查 `start-period` 设为 180 秒，留足余量）。

### 方式三：自己构建

```bash
docker build -t muaimingjunbot/ubuntu-gnome-vnc:2404 ./ubuntu-gnome
docker build --build-arg UBUNTU_VERSION=26.04 -t muaimingjunbot/ubuntu-gnome-vnc:2604 ./ubuntu-gnome
```

## 环境变量

| 变量 | 默认值 | 适用 | 说明 |
|------|--------|------|------|
| `VNC_PASSWORD` | `password` | 全部 | 桌面登录密码（RDP 模式下作为 RDP 密码） |
| `RDP_PORT` | `3389` | 24.04 / 26.04 | RDP 监听端口 |
| `RDP_USER` | `vnc` | 24.04 / 26.04 | 运行桌面的 Linux 用户（一般不用改） |
| `RDP_USERNAME` | 同 `RDP_USER` | 24.04 / 26.04 | **RDP 登录名**（可与 Linux 用户名不同） |
| `RDP_PASSWORD` | 同 `VNC_PASSWORD` | 24.04 / 26.04 | **RDP 登录密码** |
| `VNC_RESOLUTION` | `1920x1080` | 全部 | X11 版为桌面分辨率；RDP 版为无头合成器虚拟显示器尺寸 |
| `VNC_DEPTH` | `24` | X11 | 色深 |
| `VNC_PORT` | `5901` | X11 | VNC 端口 |
| `NOVNC_PORT` | `6080` | X11 | noVNC 端口 |

密码在容器**每次启动**时写入，改环境变量后 `docker restart` 即可生效，无需重建镜像。

### 修改 RDP 登录用户名 / 密码

RDP 的登录凭据由 GNOME Remote Desktop 自己管理，**与 Linux 用户名 `vnc` 无关**，
所以用户名可以随意指定（不必是系统里存在的账号）：

```bash
# 改成 用户名 boss、密码 MySecret88（立刻生效，无需重启容器）
docker exec -it gnome-2404 /usr/local/bin/set-rdp-creds.sh boss 'MySecret88'
```

也可以在建容器时通过环境变量指定：

```bash
-e RDP_USERNAME=boss -e RDP_PASSWORD=MySecret88
```

> 注意：`grdctl` 只写配置，运行中的守护进程不会自动加载新凭据 ——
> `set-rdp-creds.sh` 已经帮你重启了 `gnome-remote-desktop-headless`。
> 手动用 `grdctl` 改的话，记得执行
> `su - vnc -c 'systemctl --user restart gnome-remote-desktop-headless'`，否则旧密码仍然有效。

## GPU 支持

需要宿主机安装 [nvidia-container-toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)，然后在 `docker run` 加上 `--gpus` 参数：

```bash
--gpus all                # 启用所有 GPU
--gpus device=0           # 指定单个 GPU
--gpus '"device=0,1"'     # 指定多个 GPU
```

## 排错

### 容器启动后立刻退出，退出码 255，日志为空

几乎一定是 **cgroup v1** 问题，见上面「前置要求 1」。

### 浏览器能打开，但桌面是黑的（X11 版本）

noVNC 服务正常但 GNOME 没起来：

```bash
docker exec -it gnome-desktop journalctl -u desktop-vnc -n 50 --no-pager
docker exec -it gnome-desktop journalctl --user -n 50 --no-pager
```

### 容器"活着"但桌面永远起不来

`docker ps` 显示 running，但 gnome-shell 不出现，`docker exec` 还会卡住。这是
systemd 249（22.04）的死循环 bug：`acpid.socket` 反复触发被 Condition 跳过的
`acpid.service`，日志在同一时间戳上刷几十万条，CPU 烧满后 systemd 自身被堵死。

镜像里已屏蔽 `acpid.service / acpid.socket / acpid.path`。核对方法：

```bash
docker cp <容器>:/var/log/journal /tmp/j
journalctl -D /tmp/j/<machine-id> --no-pager | grep -c "ACPI event daemon being skipped"
```

该计数达到数万量级即为该问题。

### RDP 连不上（24.04 / 26.04）

按顺序排查：

```bash
# 1) RDP 是否在监听
docker exec <容器> ss -lnt | grep 3389

# 2) 无头会话是否建立
docker exec <容器> pgrep -a "gnome-shell"
docker exec <容器> loginctl list-sessions

# 3) 启动脚本日志
docker exec <容器> journalctl -u desktop-rdp -n 60 --no-pager

# 4) GRD 日志（注意是用户级 unit）
docker exec <容器> bash -c 'su - vnc -c "export XDG_RUNTIME_DIR=/run/user/$(id -u vnc); \
  export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u vnc)/bus; \
  journalctl --user -u gnome-remote-desktop-headless -n 30 --no-pager"'
```

常见原因：

- **客户端被拒，日志 `Credentials are not set, denying client`**：凭据没写入。检查
  `grdctl --headless status` 里 `Username` 是否为 `(hidden)`；若不是，重跑
  `set-rdp-creds.sh`。改了凭据后**必须重启守护进程**才生效。
- **CPU 100%+ 且日志疯狂刷 `polkit-agent-helper-1: needs to be setuid root`**：
  polkit helper 丢了 setuid 位，镜像已修复；自定义镜像遇到可执行
  `chmod u+s /usr/lib/polkit-1/polkit-agent-helper-1`。
- **云主机 / 代理环境下认证阶段被掐断**（Windows 事件日志 `原因=1800`，服务端日志
  `tpdu length N > tpkt header length 0`）：RDP 的 NLA 握手被透明代理（如 Clash TUN）
  干扰。把代理的 TUN 模式关掉，或给目标地址加 `DIRECT` 分流规则。
- **客户端报 `HYBRID_REQUIRED_BY_SERVER`**：服务端只接受 NLA，客户端不要强制
  `/sec:tls`，让它自动协商。

### 24.04 连上后只有壁纸，没有顶栏和 Dock

这是当前 24.04 方案已知的**限制**，不是配置错误。

现象：RDP 连上后能看到 Ubuntu 壁纸，但看不到顶栏、左侧 Dock、活动视图。

原因：会话里有**两个虚拟显示器**。查询 Mutter 的状态可以看到：

```
显示器数量: 2
  Meta-0  2520x1680   ← RDP 客户端协商的分辨率
  Meta-1  1920x1080   ← 另一个（无人显示）
```

GNOME 只会把顶栏/Dock 画在**主显示器**上，而 RDP 客户端连的是另一个，
于是看起来只有一张空壁纸。

为什么 26.04 没这个问题：26.04 用 GDM 的 `gdm-new-session --headless` 拉起了
完整的 **gnome-session**，会话只有一个显示器；24.04 没有对应的 systemd 单元，
只能直接跑 `gnome-shell --wayland --headless`，缺少会话层，因此出现多余的
虚拟显示器。

已尝试但无效：去掉 `--virtual-monitor` 启动参数后，GRD 自己仍会创建两个显示器。

后续可选方案：把 24.04 改成 **xrdp + Xorg**（单显示器、UI 完整、成熟方案）。
在此之前，需要完整桌面请使用 `2604`。

### 多个容器同时莫名退出

宿主机内存不足，`dockerd` 被 OOM 杀掉。`docker info` 会报 socket 不存在，
`systemctl start docker` 可恢复。请加 `--memory` 限制并减少并发容器数。

### Chrome 崩溃

`--shm-size` 太小，至少给到 `2g`。

## 目录结构

```
ubuntu-gnome/
  ├── Dockerfile                  # 镜像构建（按版本分流 X11 / RDP）
  ├── start-desktop.sh            # X11 路径：Xvfb + GNOME + x11vnc + noVNC
  ├── start-desktop-rdp.sh        # Wayland 路径：无头会话 + GRD RDP（自动识别 24.04/26.04）
  ├── set-rdp-creds.sh            # 运行时修改 RDP 登录用户名/密码
  ├── healthcheck.sh              # 健康检查（按 /etc/desktop-mode 分支）
  ├── desktop-vnc.service         # X11 版 systemd 单元
  ├── desktop-rdp.service         # RDP 版 systemd 单元
  └── 49-gnome-headless.rules     # 允许创建无头会话的 polkit 规则（26.04 用）
docker-compose.yml                # 一键部署
```

## 实现要点（踩坑记录）

**X11 路径（20.04 ~ 22.04）**

1. **不要自建 `dbus-daemon`** —— 用户总线由 systemd 的 `dbus.socket`/`dbus-broker`
   提供，抢占它会让 `org.freedesktop.systemd1` 不可达，`gnome-session` 报
   `NameHasNoOwner` 后退出。
2. **必须给桌面用户开 linger** —— 否则最后一个 logind 会话结束时
   `user@<uid>.service` 被销毁，`systemd --user` 一消失 GNOME 会话就崩。
3. 会话用 `systemd-run` + `PAMName=login` 创建真实 logind 会话，老版本失败时回退 `su`。
4. `websockify` 的 `--wrap-mode` 参数按可用性自适应（0.11+ 已移除）。

**Wayland/RDP 路径（24.04 / 26.04）**

1. **`gnome-shell` 不能同时用 `--display-server` 和 `--headless`** —— 24.04 上会直接报
   `Can't run in display server mode headlessly`，去掉 `--display-server` 即可。
2. **`set-credentials` 的参数个数两版不同** —— 24.04（GRD 46）要 `<用户名> <密码>` 两个
   参数；26.04（GRD 50）是一个参数 + stdin 两次输入。脚本先试两参数再回退 stdin。
3. **改完凭据必须重启守护进程** —— GRD 只在启动时读取凭据，否则旧密码仍然有效。
4. **polkit helper 必须 setuid** —— 否则 gnome-shell 的 polkit agent 无限重试，
   实测 CPU 149%、journal 每分钟 5000+ 条。
5. **屏蔽 colord 与 gnome-initial-setup 用户单元** —— 它们会申请 polkit 授权，
   无头会话里没人点确认，同样会触发上面的重试死循环。
6. **26.04 的 `gnome-headless-session@` 需要 polkit 放行** —— 该单元以
   `DynamicUser=true` 运行，默认无权调 `ManageUserDisplays`，需
   `49-gnome-headless.rules`。
7. GDM 找不到 DRM 设备会重试 3 次后放弃（26.04），属预期行为，不影响无头会话。

## License

见仓库 LICENSE（如有）。
