# Ubuntu GNOME Desktop in Docker

基于 [jockerdragon/docker-systemd](https://hub.docker.com/r/jockerdragon/docker-systemd) 的完整 Ubuntu GNOME 桌面容器。

- **Ubuntu 20.04 / 22.04 / 24.04**：X11 + Xvfb + x11vnc + **noVNC**，浏览器直接访问
- **Ubuntu 26.04**：Wayland 无头 + GNOME Remote Desktop + **RDP**，用 RDP 客户端连接

## 预览

![预览1](images/image.png)

![预览2](images/image_copy.png)

![预览3](images/image_copy_3.png)

## 特性

- 完整 Ubuntu GNOME 桌面（ubuntu-desktop）
- systemd 作为 PID 1，保证 GNOME 会话正常运行
- 中文界面 + 拼音输入法（ibus-pinyin），时区 Asia/Shanghai
- 内置 Google Chrome（Ubuntu 22.04 起 firefox 仅为 snap 过渡包，已自动移除）
- 内置健康检查（HEALTHCHECK）
- 跳过 GNOME「初始配置」向导，屏蔽升级提示
- 提供 docker compose 一键部署

## 版本支持

| 标签 | Ubuntu | GNOME | 桌面协议 | 访问方式 | 状态 |
|---|---|---|---|---|---|
| `2004` | 20.04 | 3.36 | X11 | noVNC :6080 / VNC :5901 | ✅ |
| `2204` | 22.04 | 42 | X11 | noVNC :6080 / VNC :5901 | ✅ |
| `2404` | 24.04 | 46 | X11 | noVNC :6080 / VNC :5901 | ✅ 推荐 |
| `2604` | 26.04 | 50 | Wayland | **RDP :3389** | ✅ |

### 为什么 26.04 换了协议

Ubuntu 26.04 有两个上游变更，导致原来的 X11 方案彻底失效：

1. **GNOME Shell 50 移除了 X11 会话** —— `/usr/share/xsessions` 目录都不存在了，
   `org.gnome.Shell@.service` 里写死了 `AssertEnvironment=XDG_SESSION_TYPE=wayland`。
   所以 `Xvfb + x11vnc` 采集不到任何桌面（能连上，但永远黑屏）。
2. **GNOME Remote Desktop 50 移除了 VNC 后端** —— `grdctl` 只剩 `rdp` 子命令，
   noVNC 无法代理。

因此 26.04 改用官方支持的无头路线：

```
GDM（提供 org.gnome.DisplayManager 的 D-Bus）
  └─ gnome-headless-session@vnc.service  → gdm-new-session vnc --headless
       └─ 无头 Wayland GNOME 会话（mutter 虚拟显示器）
            └─ gnome-remote-desktop-headless.service → RDP :3389
```

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

单个桌面容器常驻约 **1~2.5 GB**（24.04 空载约 1.1 GB，26.04 无头会话约 0.9 GB）。
同时运行多个容器时请预留足够内存，否则宿主机 OOM 会直接杀掉 `dockerd`，表现为所有
容器同时"莫名退出"。compose 里已用 `mem_limit: 4g` 做了保护。

### 3. 特权模式

systemd 需要 `--privileged`，无法用普通权限运行。

## 快速开始

### 方式一：docker compose（推荐）

```bash
# 24.04（浏览器访问）
docker compose up -d gnome-2404

# 26.04（RDP 访问）
docker compose up -d gnome-2604
```

### 方式二：docker run

**X11 版本（20.04 / 22.04 / 24.04）**

```bash
docker run -d \
  --privileged \
  --name gnome-desktop \
  --shm-size=2g \
  --memory=4g \
  -p 6080:6080 \
  -p 5901:5901 \
  -e VNC_PASSWORD=yourpassword \
  muaimingjunbot/ubuntu-gnome-vnc:2404
```

浏览器打开 `https://localhost:6080`，证书告警点「高级」→「继续访问」，输入密码。

**Wayland/RDP 版本（26.04）**

```bash
docker run -d \
  --privileged \
  --name gnome-2604 \
  --shm-size=2g \
  --memory=4g \
  -p 3389:3389 \
  -e VNC_PASSWORD=yourpassword \
  muaimingjunbot/ubuntu-gnome-vnc:2604
```

用任意 RDP 客户端（Windows 远程桌面 / `mstsc` / Microsoft Remote Desktop / Remmina /
FreeRDP）连接 `localhost:3389`，用户名 `vnc`，密码为 `VNC_PASSWORD`。

```bash
# 命令行验证（Linux）
xfreerdp /v:localhost:3389 /u:vnc /p:yourpassword /cert:ignore
```

首次启动需要 30~60 秒（GDM 起、无头会话建、RDP 监听）；容器 HEALTHCHECK 的
`start-period` 已设为 180 秒。

### 方式三：自己构建

```bash
docker build -t muaimingjunbot/ubuntu-gnome-vnc:2404 ./ubuntu-gnome
docker build --build-arg UBUNTU_VERSION=26.04 -t muaimingjunbot/ubuntu-gnome-vnc:2604 ./ubuntu-gnome
```

## 环境变量

| 变量 | 默认值 | 适用 | 说明 |
|------|--------|------|------|
| `VNC_PASSWORD` | `password` | 全部 | 桌面登录密码（RDP 模式下作为 RDP 密码） |
| `RDP_PORT` | `3389` | 26.04 | RDP 监听端口 |
| `RDP_USER` | `vnc` | 26.04 | RDP 登录用户名 |
| `VNC_RESOLUTION` | `1920x1080` | X11 | 桌面分辨率 |
| `VNC_DEPTH` | `24` | X11 | 色深 |
| `VNC_PORT` | `5901` | X11 | VNC 端口 |
| `NOVNC_PORT` | `6080` | X11 | noVNC 端口 |

密码在容器**每次启动**时写入，所以改环境变量后 `docker restart` 即可生效，无需重建镜像。
RDP 模式下分辨率由客户端协商（RDP 动态分辨率）。

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

### 浏览器能打开，但桌面是黑的（仅 X11 版本）

noVNC 服务正常但 GNOME 没起来：

```bash
docker exec -it gnome-desktop journalctl -u desktop-vnc -n 50 --no-pager
docker exec -it gnome-desktop journalctl --user -n 50 --no-pager
docker exec -it gnome-desktop pgrep -a gnome-shell
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

### RDP 连不上（26.04）

按顺序排查：

```bash
# 1) RDP 是否在监听
docker exec gnome-2604 ss -lnt | grep 3389

# 2) 无头会话是否创建成功
docker exec gnome-2604 loginctl list-sessions
docker exec gnome-2604 pgrep -a "gnome-shell --mode"

# 3) 启动脚本与 GRD 日志
docker exec gnome-2604 journalctl -u desktop-rdp -n 60 --no-pager
docker exec gnome-2604 bash -c 'su - vnc -c "export XDG_RUNTIME_DIR=/run/user/1001; \
  export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1001/bus; \
  journalctl --user -u gnome-remote-desktop-headless -n 30 --no-pager"'
```

常见原因：

- **GDM 起不来** → 无头会话创建失败，日志里会出现
  `Not authorized for action org.gnome.displaymanager.displayfactory.manage-user-displays`
  （镜像内已有 polkit 规则放行）。
- **CPU 100%+ 且日志疯狂刷 `polkit-agent-helper-1: needs to be setuid root`** →
  polkit helper 丢了 setuid 位，镜像已修复；若自定义镜像遇到，执行
  `chmod u+s /usr/lib/polkit-1/polkit-agent-helper-1`。
- **客户端报 `HYBRID_REQUIRED_BY_SERVER`** → 服务端只接受 NLA，客户端不要强制
  `/sec:tls`，让它自动协商（或换用支持 NLA 的客户端）。

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
  ├── start-desktop-rdp.sh        # Wayland 路径：GDM + 无头会话 + GRD RDP
  ├── healthcheck.sh              # 健康检查（按 /etc/desktop-mode 分支）
  ├── desktop-vnc.service         # X11 版 systemd 单元
  ├── desktop-rdp.service         # RDP 版 systemd 单元
  └── 49-gnome-headless.rules     # 允许创建无头会话的 polkit 规则
docker-compose.yml                # 一键部署
```

## 实现要点（踩坑记录）

**X11 路径（20.04 ~ 24.04）**

1. **不要自建 `dbus-daemon`** —— 用户总线由 systemd 的 `dbus.socket`/`dbus-broker`
   提供，抢占它会让 `org.freedesktop.systemd1` 不可达，`gnome-session` 报
   `NameHasNoOwner` 后退出。
2. **必须给桌面用户开 linger** —— 否则最后一个 logind 会话结束时
   `user@<uid>.service` 被销毁，`systemd --user` 一消失 GNOME 会话就崩。
3. 会话用 `systemd-run` + `PAMName=login` 创建真实 logind 会话，老版本失败时回退 `su`。
4. `websockify` 的 `--wrap-mode` 参数按可用性自适应（0.11+ 已移除）。

**Wayland/RDP 路径（26.04）**

1. **`gnome-headless-session@.service` 需要 polkit 放行** —— 它以 `DynamicUser=true`
   运行，默认没有权限调 `ManageUserDisplays`，会报
   `Not authorized for action`。镜像内附带 `49-gnome-headless.rules`。
2. **polkit-agent-helper 必须 setuid** —— 该 socket 激活方式依赖 pidfd，在较老内核的
   容器里不可用，会回退到 setuid helper；若 helper 没有 setuid 位，gnome-shell 的
   polkit agent 会无限重试（实测 CPU 149%、每分钟 5000+ 条日志）。
3. **屏蔽 colord** —— 容器没有色彩管理设备，否则 GNOME 会弹授权对话框。
4. **屏蔽 gnome-initial-setup 的用户单元** —— 否则首登向导要申请
   `whoopsiepreferences.change` 授权，同样会触发上面的重试死循环。
5. GDM 找不到 DRM 设备会重试 3 次后打印
   `maximum number of display failures reached. Giving up.`，这是预期行为，
   不影响无头会话，也不需要处理。

## License

见仓库 LICENSE（如有）。
