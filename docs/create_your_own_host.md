# 如何创建自己的 NixOS 主机配置

本文档将指导你如何基于本仓库的配置模板，为您自己的 VPS 或物理机创建 NixOS 配置。

## 简单流程

### 第一步：安装 Nix (非 NixOS 系统)

在目标机器上（目前运行着 Ubuntu/Debian/CentOS 等系统），首先安装 Nix 包管理器。

**1. 安装 Nix**
```bash
sh <(curl -L https://nixos.org/nix/install) --daemon
```

**2. 配置 Nix 以启用 Flakes**
```bash
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

### 第二步：准备主机配置文件

首先确认你的主机网络环境是否支持 DHCP。我们为您准备了详细的探测教程：
👉 **[如何检测主机是否支持 DHCP](./create_your_own_host/check_dhcp.md)**

如果在上述检测中：

**若支持 DHCP:**
可以直接复制 `server/vps/hosts/hyperv.nix` 作为模板：
```bash
cp server/vps/hosts/hyperv.nix server/vps/hosts/<新主机名>.nix
```
*记得修改 `<新主机名>.nix` 中 `facter.reportPath` 的 `hyperv` 为你的 `<新主机名>`。*

**若不支持 DHCP (需静态 IP):**
请复制 `server/vps/hosts/tohu.nix` 作为模板：
```bash
cp server/vps/hosts/tohu.nix server/vps/hosts/<新主机名>.nix
```
*需修改 `<新主机名>.nix` 中 `facter.reportPath` 的 `tohu` 为你的 `<新主机名>`，并根据你主机的实际网络情况修改 `networking` 部分的 IP、网关等配置。*

**关于 SSH 登录配置**
如果你希望允许使用密码登录 SSH（不推荐，但有时便于调试）：
1. 在 `<新主机名>.nix` 中，将 `import ../auth/default.nix` 改为 `import ../auth/permit_passwd.nix` (仅适用于复制自 `tohu.nix` 的情况，`hyperv.nix` 默认已使用 `permit_passwd.nix`)。
2. 生成密码 hash:
   ```bash
   nix run nixpkgs#mkpasswd -- -m sha-512
   ```
3. 用生成的字符串替换 `initialHashedPassword` 的值。

**设置 SSH Key**
使用你自己的 SSH Public Key 替换 `authorizedKeys` 列表。如果你使用的是 `permit_passwd.nix` 且暂不配置 Key，可以将其设为空列表 `authorizedKeys = []`。

### 第三步：生成硬件报告 (facter.json)

我们需要使用 `nixos-facter` 来自动探测硬件配置（如驱动、内核模块等）。请在目标机器上运行：

```bash
nix run \
  --option experimental-features "nix-command flakes" \
  --option extra-substituters https://numtide.cachix.org \
  --option extra-trusted-public-keys numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE= \
  github:nix-community/nixos-facter -- -o ./facter.json
```
生成后，将其重命名为 `<新主机名>.json`。

### 第四步：保存配置到仓库

你可以选择 Fork 仓库到自己的 GitHub，或者仅在本地保存修改。

**选项一：配置自己的 Git Repo (推荐)**
1. Fork 本仓库: [https://github.com/ShaoG-R/nixos-config](https://github.com/ShaoG-R/nixos-config)
2. 在本地配置好 Git 环境并 clone 你的 Fork。
3. 将文件放置到正确位置：
   - `<新主机名>.nix` -> `server/vps/hosts/`
   - `<新主机名>.json` -> `server/vps/hosts/facter/`
4. 提交更改：
   ```bash
   git add .
   git commit -m "Add new host: <新主机名>"
   ```

**选项二：仅本地保存配置库**
1. 下载并解压配置库：
   ```bash
   curl -L https://github.com/ShaoG-R/nixos-config/archive/refs/heads/main.tar.gz -o config.tar.gz && \
   tar -xzf config.tar.gz && \
   rm config.tar.gz && \
   cd nixos-config-main
   ```
2. 将文件放置到正确位置：
   - `<新主机名>.nix` -> `server/vps/hosts/`
   - `<新主机名>.json` -> `server/vps/hosts/facter/`
3. 初始化 Git 仓库（Nix Flakes 依赖 Git 追踪文件）：
   ```bash
   rm .git -r
   git init
   git add .
   cd ..
   mv nixos-config-main nixos-config
   ```

### 第五步：注册新主机到 Flake

编辑 `flake.nix`，在 `outputs` 的 `nixosConfigurations` 中添加你的新主机配置。参考 `hyperv` 的配置块，在下方增加：

```nix
      # ... 现有配置 ...
      
      <新主机名> = mkSystem {
          system = "x86_64-linux"; # 根据实际架构修改，如 aarch64-linux
          diskDevice = "/dev/sda"; # 根据实际硬盘设备路径修改，如 /dev/vda, /dev/nvme0n1
          extraModules = [
            ./server/vps/hosts/<新主机名>.nix
            ./disk/vps/Swap-4G.nix # 根据内存大小选择合适的 Swap 配置
            {
              networking.hostName = "<新主机名>";
            }
          ];
        };
```
最后，暂存所有修改（如果配置了 Git Repo 可以提交）：
```bash
git add flake.nix
```

现在，你已经准备好使用 `nixos-anywhere` 或构建 Raw 镜像来部署这台新机器了。

---

## 进阶：自定义体验

除了基础的主机配置，你还可以深入定制系统行为。

### 自定义磁盘和文件系统 (`disk/vps/common.nix`)

该文件定义了通过 disko 进行的分区布局。
- **文件位置**: `disk/vps/common.nix`
- **默认布局**: BIOS+GPT 兼容引导，ESP 分区，Swap 分区，以及一个 Btrfs Root 分区。
- **Btrfs 子卷**: 默认创建了 `@`, `@home`, `@nix`, `@log` 四个子卷，并启用 zstd 压缩。

**如何自定义：**
如果你需要修改分区大小、增加加密 (LUKS) 或改变文件系统（如 ext4, xfs），可以创建 `disk/vps/common.nix` 的副本（例如 `disk/vps/custom.nix`），并在 `flake.nix` 中引用它，或者使用 Overlay 的方式覆盖参数。
*注意：`common.nix` 接受 `swapSize` 和 `imageSize` 参数，这使得它可以被复用。*

### 自定义平台通用设置 (`server/vps/platform/generic.nix`)

该文件汇集了所有 VPS 通用的基础配置。
- **文件位置**: `server/vps/platform/generic.nix`
- **包含内容**:
  - **内核**: 默认使用 XanMod 稳定版内核。
  - **网络**: 禁用 Predictable Interface Names (默认使用 eth0)，启用 Podman DNS。
  - **维护**: 自动升级 (每天 04:00)，自动垃圾回收 (每周)，Nix Store 自动去重。
  - **本地化**: 时区设为 Asia/Shanghai，默认语言 zh_CN.UTF-8。

**如何自定义：**
1. **覆盖设置**: 在你的 `<新主机名>.nix` 中，你可以使用 `lib.mkForce` 强制覆盖这里的默认设置。
   例如，要更改时区：
   ```nix
   time.timeZone = lib.mkForce "America/New_York";
   ```
2. **模块化替换**: 如果你不想要这些通用设置，可以在 `<新主机名>.nix` 的 `imports` 中移除 `../platform/generic.nix`，并建立自己的 platform 模块。
