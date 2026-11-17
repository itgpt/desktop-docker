# Ubuntu GNOME Desktop in Docker via noVNC

基于 [jockerdragon/docker-systemd](https://hub.docker.com/r/jockerdragon/docker-systemd) 的完整 Ubuntu GNOME 桌面容器，通过浏览器（noVNC）或任意 VNC 客户端访问。

## 预览

![预览1](images/image.png)

![预览2](images/image_copy.png)

![预览3](images/image_copy_3.png)

## 特性

- 完整 Ubuntu GNOME 桌面（ubuntu-desktop）
- systemd 作为 PID 1，保证 GNOME 会话正常运行
- 浏览器访问（noVNC HTTPS，端口 6080），支持剪贴板双向同步
- VNC 直连（端口 5901）
- 中文界面 + 拼音输入法（ibus-pinyin）
- 时区 Asia/Shanghai
- 内置 Google Chrome（Ubuntu 22.04 起 firefox 仅为 snap 过渡包，容器内不可用，已自动移除）
- 内置健康检查（HEALTHCHECK）
- 跳过 GNOME「初始配置」向导，屏蔽升级提示，开箱即用
- 提供 docker compose 一键部署

## 版本支持

| 标签 | Ubuntu | GNOME | 状态 | 说明 |
|---|---|---|---|---|
| `2004` | 20.04 | 3.36 | ✅ 可用 | 已实测 |
| `2204` | 22.04 | 42 | ✅ 可用 | 已实测 |
| `2404` | 24.04 | 46 | ✅ 可用 | 已实测，推荐 |
| `2604` | 26.04 | 50 | ⚠️ 实验 | 见下方说明 |

> **关于 Ubuntu 26.04**
>
> Ubuntu 26.04 的 GNOME Shell 50 已**彻底移除 X11 会话**（`/usr/share/xsessions`
> 目录都不存在了），同时 GNOME Remote Desktop 50 也**移除了 VNC 后端**（`grdctl`
> 只剩 `rdp` 子命令）。
>
> 因此本项目原有的 `Xvfb + X11 + x11vnc` 架构在 26.04 上原理上无法工作，官方
> 无头方案只剩 RDP。`2604` 标签保留为实验状态，需要 Wayland 无头 + RDP 方案，
> 且对内核版本较敏感（systemd 259 要求较新的内核；在 WSL2 的 5.15 内核上实测
> 会不稳定）。**生产使用请选择 `2404`。**

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

然后 `wsl --shutdown` 重启 WSL。验证：`stat -fc %T /sys/fs/cgroup` 应输出
`cgroup2fs`。

**普通 Linux**：内核启动参数加上 `systemd.unified_cgroup_hierarchy=1`。

### 2. 内存

单个 GNOME 桌面容器常驻约 **1~2 GB**（24.04 空载实测约 1.1 GB，开浏览器后会明显上涨）。
同时运行多个容器时请预留足够内存，否则宿主机 OOM 会直接杀掉 `dockerd`，表现为所有容器
同时"莫名退出"（退出码 255）。compose 文件里已经用 `mem_limit: 4g` 做了保护。

### 3. 特权模式

systemd 需要 `--privileged`，无法用普通权限运行。

## 快速开始

### 方式一：docker compose（推荐）

```bash
# 只启动 24.04
docker compose up -d gnome-2404

# 同时启动 20.04 和 24.04
docker compose up -d gnome-2004 gnome-2404
```

### 方式二：docker run

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

浏览器打开 `https://localhost:6080`，提示证书不受信任时点「高级」→「继续访问」，
输入密码即可。首次进入 GNOME 需要约 10~15 秒。

### 方式三：自己构建

```bash
# 默认 Ubuntu 24.04
docker build -t muaimingjunbot/ubuntu-gnome-vnc:2404 ./ubuntu-gnome

# 指定版本
docker build --build-arg UBUNTU_VERSION=20.04 -t muaimingjunbot/ubuntu-gnome-vnc:2004 ./ubuntu-gnome
```

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `VNC_PASSWORD` | `password` | VNC/noVNC 登录密码 |
| `VNC_RESOLUTION` | `1920x1080` | 桌面分辨率 |
| `VNC_DEPTH` | `24` | 色深 |
| `VNC_PORT` | `5901` | VNC 端口 |
| `NOVNC_PORT` | `6080` | noVNC 端口 |

密码在容器**每次启动**时由 `/usr/local/bin/start-desktop.sh` 写入
`/home/vnc/.vnc/passwd`，所以改环境变量后 `docker restart` 即可生效，无需重建镜像。

## GPU 支持

需要宿主机安装 [nvidia-container-toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)，然后在 `docker run` 加上 `--gpus` 参数：

```bash
# 启用所有 GPU
--gpus all

# 指定单个 GPU
--gpus device=0

# 指定多个 GPU
--gpus '"device=0,1"'
```

## 排错

### 容器启动后立刻退出，退出码 255，日志为空

几乎一定是 **cgroup v1** 问题，见上面「前置要求 1」。

### 浏览器能打开，但桌面是黑的

说明 noVNC 服务正常但 GNOME 没起来。进容器查：

```bash
docker exec -it gnome-desktop journalctl -u desktop-vnc -n 50 --no-pager
docker exec -it gnome-desktop journalctl --user -n 50 --no-pager
docker exec -it gnome-desktop pgrep -a gnome-shell
```

### 多个容器同时莫名退出

宿主机内存不足，`dockerd` 被 OOM 杀掉。`docker info` 会报 socket 不存在，
`systemctl start docker` 可恢复。请加 `--memory` 限制并减少并发容器数。

### 容器"活着"但桌面永远起不来（22.04 曾出现）

`docker ps` 显示 running，但 gnome-shell 不出现、6080 不监听，`docker exec` 还会卡住。

这是 systemd 249（Ubuntu 22.04）的死循环 bug：`acpid.socket` 反复触发被 Condition
跳过的 `acpid.service`，systemd 在同一时间戳上刷几十万条
`Condition check resulted in ACPI event daemon being skipped`，CPU 烧满后自身被堵死。

镜像里已屏蔽 `acpid.service / acpid.socket / acpid.path`，正常不会遇到。若在自定义
镜像中见到此现象，确认这三项已 mask，并可用以下命令核对：

```bash
docker cp <容器>:/var/log/journal /tmp/j
journalctl -D /tmp/j/<machine-id> --no-pager | grep -c "ACPI event daemon being skipped"
```

该计数若达到数万量级，即为该问题。

### Chrome 崩溃

`--shm-size` 太小，至少给到 `2g`。

## 目录结构

```
ubuntu-gnome/
  ├── Dockerfile             # 镜像构建
  ├── start-desktop.sh       # 容器内启动 Xvfb + GNOME + x11vnc + noVNC
  ├── healthcheck.sh         # 健康检查
  └── desktop-vnc.service    # systemd 单元
docker-compose.yml           # 一键部署
```

## 实现要点

几个容易出错的地方，已在 `start-desktop.sh` 里处理：

1. **不要自建 `dbus-daemon`**。Ubuntu 24.04+ 的用户总线由 systemd 的
   `dbus.socket` / `dbus-broker` 提供，再往同一个 socket 路径绑一个 `dbus-daemon`
   会让客户端连到非 systemd 管理的那条总线，`org.freedesktop.systemd1` 变得不可达，
   `gnome-session` 报 `NameHasNoOwner` 后退出。

2. **必须给桌面用户开 linger**。否则最后一个 logind 会话结束时
   `user@<uid>.service` 会被销毁，`systemd --user` 一消失 GNOME 会话就崩。

3. **GNOME 会话用 `systemd-run` + `PAMName=login` 创建**，这样才有一个真正的
   logind 会话；老版本走不通时脚本会自动回退到 `su` 方式。

4. **`websockify` 的 `--wrap-mode` 参数按可用性自适应**（0.11+ 已移除该参数）。

## License

见仓库 LICENSE（如有）。
