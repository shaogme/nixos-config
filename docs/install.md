# NixOS 安装指南

本指南提供了多种安装 NixOS 的方式。请根据你的具体环境（VPS、物理机、已有 Linux 系统等）选择合适的方法。

---

## 前置准备

### 设置环境变量

在开始之前，请根据你的实际情况设置以下环境变量：

```bash
# 目标主机名（对应 vps/<hostname>/flake.nix）
export HOST=tohu

# 目标服务器 IP 地址（用于远程安装）
export TARGET_IP=1.2.3.4

# 你的 GitHub 用户名
export GITHUB_USER=ShaoG-R
```

### 确认主机配置

在安装前，请确保你已经创建了主机配置。如果还没有，请先阅读：

👉 **[创建主机配置指南](./create_your_own_host.md)**

---

## 方式一：云端构建 + 一键 DD (推荐)

**适用场景**: VPS，无本地 NixOS 环境，无需自备下载服务器。

**原理**: GitHub Actions 自动构建镜像并发布到 Releases，VPS 直接 DD 镜像即可。

### 1. 获取镜像直链

本仓库的 `.github/workflows/release.yml` 会自动构建镜像并发布到 Releases。

**默认镜像地址:**
```
https://github.com/<用户名>/nixos-config/releases/latest/download/<主机名>.tar.zst
```

**示例:**
```bash
export IMAGE_URL="https://github.com/$GITHUB_USER/nixos-config/releases/latest/download/$HOST.tar.zst"
```

**手动触发构建:**
1. 进入 GitHub 仓库的 **Actions** 页面
2. 选择 **Release System Images** 工作流
3. 点击 **Run workflow** 手动触发
4. 等待构建完成，在 **Releases** 页面获取下载链接

### 2. 在目标 VPS 执行 DD

登录 VPS 后执行以下命令：

```bash
# 下载重装脚本
curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh || wget -O ${_##*/} $_

# 设置镜像直链
export IMAGE_URL="https://github.com/$GITHUB_USER/nixos-config/releases/latest/download/$HOST.tar.zst"

# 执行一键 DD
bash reinstall.sh dd --img "$IMAGE_URL"

# 脚本会自动重启，等待安装完成后 SSH 登录
```

**注意事项:**
- DD 过程会**完全覆盖**目标磁盘，请确保数据已备份
- 安装完成后使用配置中定义的认证方式登录

---

## 方式二：救援模式安装 (Standard Install)

**适用场景**: 处于救援模式或 LiveCD 环境下的机器，内存 > 4GB。

### 1. 进入救援模式

通过 VPS 控制台进入救援系统 (Rescue System)，通常是基于 Debian 或 Alpine 的 Linux。

### 2. 安装 Nix 包管理器

```bash
# 安装 Nix (使用 Determinate Systems 安装器)
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm

# 加载 Nix 环境
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh

# 验证安装
nix --version
```

### 3. 下载配置库

```bash
# 下载并解压配置库
curl -L "https://github.com/$GITHUB_USER/nixos-config/archive/refs/heads/main.tar.gz" -o config.tar.gz
tar -xzf config.tar.gz
rm config.tar.gz
cd nixos-config-main
```

### 4. 生成硬件配置

使用 `nixos-facter` 自动探测硬件：

```bash
# 运行 nixos-facter 生成硬件报告
sudo nix run \
  --extra-experimental-features "nix-command flakes" \
  --option extra-substituters https://numtide.cachix.org \
  --option extra-trusted-public-keys "numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE=" \
  github:nix-community/nixos-facter -- -o ./vps/$HOST/facter.json
```

### 5. 磁盘分区

使用 Disko 进行自动分区：

```bash
# 执行分区（会格式化磁盘！）
# 注意：使用 path:$(pwd) 确保将当前根目录作为上下文，解决子 flake 引用父目录的问题
sudo nix run \
  --extra-experimental-features "nix-command flakes" \
  github:nix-community/disko -- --mode disko --flake "path:$(pwd)?dir=vps/$HOST#$HOST"

# 验证挂载
mount | grep /mnt
```

**分区布局 (由 `core.hardware.disk` 模块定义):**
- `/boot/efi` - ESP 分区 (32MB, FAT32)
- `/` - Btrfs 根分区 (子卷: `@`)
- `/home` - Btrfs 子卷 (`@home`)
- `/nix` - Btrfs 子卷 (`@nix`)
- `/var/log` - Btrfs 子卷 (`@log`)
- `swap` - 可选 Swap 分区

### 6. 安装系统

```bash
# 安装 NixOS
sudo nixos-install --flake "path:$(pwd)?dir=vps/$HOST#$HOST" --no-root-passwd --show-trace

# 安装完成后重启
reboot
```

---

## 方式二 (进阶)：救援模式 + 远程 Flake (GitOps)

**适用场景**: 救援模式，且主机配置 (`flake.nix` 和 `facter.json`) 已推送到 GitHub 仓库。

这个方式无需手动下载配置库，直接读取远程 Flake 进行分区和安装。

### 1. 准备环境

设置环境变量并安装 Nix (同上)：

```bash
# 设置你的配置信息
export HOST=hyperv
export GITHUB_USER=ShaoG-R
export BRANCH=pre-release  # 通常使用 main 或 pre-release

# 安装 Nix
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
```

### 2. 远程分区

直接使用 Disko 读取远程配置进行分区：

```bash
sudo nix run \
  --extra-experimental-features "nix-command flakes" \
  github:nix-community/disko -- --mode disko --flake "github:$GITHUB_USER/nixos-config/$BRANCH?dir=vps/$HOST"#$HOST
```

### 3. 远程安装

直接使用 nixos-install 读取远程配置安装：

```bash
sudo nixos-install --flake "github:$GITHUB_USER/nixos-config/$BRANCH?dir=vps/$HOST"#$HOST --no-root-passwd --show-trace
```

### 4. 重启

```bash
reboot
```

---

## 方式三：nixos-anywhere 远程安装

**适用场景**: 本地有 Nix 环境，可通过 SSH root 登录目标 VPS。

### 1. 准备本地环境

确保本地已安装 Nix 并启用 Flakes：

```bash
# 检查 Nix 版本
nix --version

# 如果需要，启用实验性功能
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

### 2. 配置 SSH 免密登录

```bash
# 生成 SSH 密钥 (如果还没有)
ssh-keygen -t ed25519 -C "deploy@$HOST"

# 将公钥复制到目标机器
ssh-copy-id root@$TARGET_IP

# 测试连接
ssh root@$TARGET_IP "echo 'SSH OK'"
```

### 3. 下载配置库

```bash
# 下载并解压
curl -L "https://github.com/$GITHUB_USER/nixos-config/archive/refs/heads/main.tar.gz" -o config.tar.gz
tar -xzf config.tar.gz
rm config.tar.gz
cd nixos-config-main
```

### 4. 远程生成硬件报告

```bash
# 在远程机器上生成 facter.json
ssh root@$TARGET_IP "nix run --extra-experimental-features 'nix-command flakes' github:nix-community/nixos-facter" > ./vps/$HOST/facter.json
```

### 5. 执行远程安装

```bash
# 使用 nixos-anywhere 部署
nix run github:nix-community/nixos-anywhere -- \
  --flake "path:$(pwd)?dir=vps/$HOST#$HOST" \
  --target-host root@$TARGET_IP \
  --build-on local

# 安装完成后 SSH 登录验证
ssh root@$TARGET_IP
```

**选项说明:**
- `--build-on local`: 在本地构建系统闭包，然后上传到服务器 (推荐)
- `--build-on remote`: 在远程服务器上构建 (需要足够内存)

---

## 方式四：通用一键脚本 (Minimal)

**适用场景**: 快速重装为标准 NixOS 基础系统，不使用自定义配置。

```bash
# 下载重装脚本
curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh || wget -O ${_##*/} $_

# 运行脚本安装 NixOS
bash reinstall.sh nixos --password "YourSecurePassword"

# 重启开始安装
reboot
```

安装完成后，你可以手动应用本仓库的配置：

```bash
nixos-rebuild switch --flake "github:$GITHUB_USER/nixos-config?dir=vps/$HOST"
```

---

## 安装后

### 验证系统状态

```bash
# 检查系统版本
nixos-version

# 检查服务状态
systemctl status

# 检查自动更新服务
systemctl status nixos-upgrade.timer
```

### 手动触发更新

```bash
# 立即应用最新配置
nixos-rebuild switch --flake "github:$GITHUB_USER/nixos-config?dir=vps/$HOST"
```

### 回滚到上一版本

```bash
# 查看可用的系统代
nixos-rebuild --list-generations

# 回滚到上一代
nixos-rebuild --rollback
```

---

## 故障排除

### 构建失败: 内存不足

如果在救援模式下构建失败，可能是内存不足。解决方案：
1. 使用 **方式一 (云端构建 + DD)** 避免本地构建
2. 使用 **方式三 (nixos-anywhere)** 在本地构建后上传

### SSH 无法连接

1. 检查 `core.auth.root.authorizedKeys` 是否配置正确
2. 检查 `core.auth.root.mode` 是否允许密码登录
3. 确认防火墙是否开放 22 端口

### 网络配置错误

1. 确认 `core.hardware.network.single-interface` 配置正确
2. 检查 IP/网关/DNS 设置
3. DHCP 环境确保启用 `dhcp.enable = true`
