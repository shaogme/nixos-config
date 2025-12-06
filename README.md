# NixOS 部署与安装指南

本指南提供了多种安装 NixOS 的方式。请根据你的具体环境（VPS、物理机、已有 Linux 系统等）选择合适的方法。

在该配置库中，我们将使用环境变量来代替非固定的参数（如主机名、IP地址等），以便于理解和替换。

## 准备工作：设置环境变量

在开始之前，请在终端中根据你的实际情况设置以下环境变量。这样后续命令中的变量（如 `$HOST`）就会自动替换为你设置的值。

```bash
# 设置你的目标主机名（对应 flake.nix 中的 nixosConfigurations 名称，例如 tohu）
export HOST=tohu

# 设置目标服务器的 IP 地址（用于远程安装）
export TARGET_IP=1.2.3.4

# 设置你的自定义镜像下载链接（仅用于方式一）
export IMAGE_URL="https://your-domain.com/image.tar.zst"
```

---

## 方式一：构建自定义镜像并一键 DD (VPS 推荐)

**适用场景**：VPS（不限内存大小），需要你自己有一个本地的 NixOS 环境（虚拟机或物理机）来构建镜像，还需要一个能够直链下载的文件服务器来托管构建好的镜像。
**优点**：可以完全定制系统，不受 VPS 提供商救援系统限制，内存占用低。

### 1. 下载配置库
首先下载并解压本配置库到本地 NixOS 环境。

```bash
# 下载 main 分支的 tar 包并解压，然后进入目录
curl -L https://github.com/ShaoG-R/nixos-config/archive/refs/heads/main.tar.gz -o config.tar.gz && \
tar -xzf config.tar.gz && \
rm config.tar.gz && \
cd nixos-config-main
```

### 2. 构建系统镜像
使用 Nix 构建你的主机配置对应的 Disko 镜像。
*注意：这里的 `$HOST` 对应你在准备工作中设置的主机名。*

```bash
# 构建 diskoImages 产物
nix build .#nixosConfigurations.$HOST.config.system.build.diskoImages
```

### 3. 处理镜像文件
构建完成后，将生成的 raw 镜像复制出来，并使用 zstd 进行高压缩，以便于传输。

```bash
# 将构建结果中的 raw 镜像复制到当前目录，并清理构建链接和垃圾以节省空间
cp result/main.raw . && rm result && nix-collect-garbage

# 使用 zstd 多线程压缩镜像为 .tar.zst 格式
# -T0 表示使用所有可用 CPU 核心
tar -I "zstd -T0" -cf image.tar.zst main.raw
```

### 4. 上传镜像
**手动步骤**：请将生成的 `image.tar.zst` 文件上传到你可以直链下载的服务器或对象存储（如 R2, S3, 或者简单的 HTTP 服务器）。获取该文件的下载链接。

### 5. 在目标 VPS 上执行 DD
登录到你的目标 VPS（救援模式或现有系统），下载重装脚本并执行 DD 操作。

```bash
# 下载通用的重装脚本 reinstall.sh
curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh || wget -O ${_##*/} $_

# 执行 DD 命令，将系统替换为你构建的 NixOS 镜像
# 请确保已设置 IMAGE_URL 环境变量，或直接将链接填入下方命令
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
  github:nix-community/nixos-facter -- -o server/vps/hosts/facter/$HOST.json
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

---

## 辅助：在其他 Linux 系统获取硬件配置 (facter.json)

如果你需要在非 NixOS 系统上预先获取硬件信息以便生成 `facter.json`：

```bash
# 1. 安装 Nix
sh <(curl -L https://nixos.org/nix/install) --daemon

# 2. 配置 Nix
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf

# 3. 运行 nixos-facter 生成配置
nix run \
  --option experimental-features "nix-command flakes" \
  --option extra-substituters https://numtide.cachix.org \
  --option extra-trusted-public-keys numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE= \
  github:nix-community/nixos-facter -- -o ./facter.json
```
