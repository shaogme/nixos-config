# NixOS 部署与安装指南

> **Note**: 当前库是个人配置文件库。若希望寻找模板库方便配置 NixOS，请前往 [https://github.com/ShaoG-R/nixos-config-template](https://github.com/ShaoG-R/nixos-config-template)。

本指南提供了多种安装 NixOS 的方式。请根据你的具体环境（VPS、物理机、已有 Linux 系统等）选择合适的方法。

在该配置库中，我们将使用环境变量来代替非固定的参数（如主机名、IP地址等），以便于理解和替换。

## 准备工作：设置环境变量

在开始之前，请在终端中根据你的实际情况设置以下环境变量。这样后续命令中的变量（如 `$HOST`）就会自动替换为你设置的值。

```bash
# 设置你的目标主机名（对应 flake.nix 中的 nixosConfigurations 名称，例如 tohu）
export HOST=tohu

# 设置目标服务器的 IP 地址（用于远程安装）
export TARGET_IP=1.2.3.4
```

---

## 创建你自己的主机配置

默认配置使用 `tohu` 作为演示。如果你需要部署自己的服务器，请先参考文档：
👉 **[如何创建自己的 NixOS 主机配置](docs/create_your_own_host.md)**

---


## 方式一：构建自定义镜像并一键 DD (推荐)

**适用场景**：VPS，无本地 NixOS 环境，无自备下载服务器。
**原理**：我们通过使用 GitHub Action 构建和发布，解决了本地 NixOS 环境和自备直链下载服务器的问题。

### 1. 获取镜像直链

本仓库的 `.github/workflows/release.yml` 会自动构建镜像并发布到 Releases。

- **直链地址 (tohu)**：
  `https://github.com/ShaoG-R/nixos-config/releases/latest/download/tohu.tar.zst`

- **自定义构建**：
  如果你 Fork 了本仓库，请在 Actions 页面手动触发 `Release System Images` 工作流，构建完成后在 Releases 页面获取你的下载直链。

### 2. 在目标 VPS 上执行 DD

登录 VPS 后执行以下命令：

```bash
# 下载重装脚本
curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh || wget -O ${_##*/} $_

# 设置镜像直链 (请根据实际情况替换 URL)
export IMAGE_URL="https://github.com/ShaoG-R/nixos-config/releases/latest/download/tohu.tar.zst"

# 执行一键 DD
bash reinstall.sh dd --img "$IMAGE_URL"
```

---

## 方式二：正规恢复环境下安装 (Standard Install)

**适用场景**：由于需要运行 Nix 编译，建议内存 > 4G (不包含 Swap)。适用于处于救援模式或 LiveCD 环境下的机器。

### 1. 准备 Nix 环境
在救援系统中安装 Nix 包管理器并启用必要的特性。

```bash
# 创建配置目录
mkdir -p ~/.config/nix

# 启用 flakes 和 nix-command 实验性功能
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

### 2. 下载配置库

```bash
# 下载配置库并解压
curl -L https://github.com/ShaoG-R/nixos-config/archive/refs/heads/main.tar.gz -o config.tar.gz && \
tar -xzf config.tar.gz && \
rm config.tar.gz && \
cd nixos-config-main
```

### 3. 生成硬件配置
使用 `nixos-facter` 自动检测硬件并生成配置文件。

```bash
# 运行 nixos-facter 并将结果保存到指定主机的 facter 目录中
sudo nix run \
  --option experimental-features "nix-command flakes" \
  --option extra-substituters https://numtide.cachix.org \
  --option extra-trusted-public-keys numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE= \
  github:nix-community/nixos-facter -- -o server/vps/facter/$HOST.json
```

### 4. 磁盘分区与安装
使用 Disko 进行分区并安装系统。

```bash
# 使用 Disko 根据配置对磁盘进行分区和格式化
# --mode disko: 执行实际的磁盘操作
nix run github:nix-community/disko -- --mode disko --flake .#$HOST

# 安装 NixOS 系统到挂载点
# --no-root-passwd: 不设置 root 密码（假设配置中已通过 SSH Key 等方式验证）
# --show-trace: 出错时显示详细堆栈
nixos-install --flake .#$HOST --no-root-passwd --show-trace
```

---

## 方式三：nixos-anywhere 远程安装

**适用场景**：你有一台本地机器（安装了 Nix），并且可以通过 SSH root 登录到目标 VPS。适合批量部署或不想进入救援模式操作的情况。

### 1. 准备本地环境

```bash
# 确保本地已配置好 nix 和 flakes
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

### 2. 配置 SSH 免密登录
如果还没有 SSH Key，请先生成。
```bash
# ssh-keygen -t ed25519 -C "root@$HOST"
```

将公钥复制到目标机器：
```bash
# 将本地 SSH 公钥复制到目标机器的 root 用户
ssh-copy-id root@$TARGET_IP
```

### 3. 下载配置并远程安装
在本地机器上执行安装命令。

```bash
# 下载并解压配置库
curl -L https://github.com/ShaoG-R/nixos-config/archive/refs/heads/main.tar.gz -o config.tar.gz && \
tar -xzf config.tar.gz && \
rm config.tar.gz && \
cd nixos-config-main

# 使用 nixos-anywhere 远程部署
# --build-on local: 在本地构建系统闭包，然后上传到服务器（减少服务器负载）
nix run github:nix-community/nixos-anywhere -- \
  --flake .#$HOST \
  --target-host root@$TARGET_IP \
  --build-on local
```

---

## 方式四：通用一键脚本 (Minimal)

**适用场景**：想快速重装为标准的 NixOS 基础系统，不使用自定义配置。

```bash
# 下载重装脚本
curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh || wget -O ${_##*/} $_

# 运行脚本安装 NixOS
# --password: 设置 root 密码
bash reinstall.sh nixos --password "ChangeMe123"

# 重启开始重装
reboot
```