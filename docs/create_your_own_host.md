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

### 第二步：获取配置仓库

我们需要先将配置仓库下载到本地，以便后续基于模板创建您的专属配置。

**选项一：配置自己的 Git Repo (推荐)**
1. Fork 本仓库: [https://github.com/ShaoG-R/nixos-config](https://github.com/ShaoG-R/nixos-config)
2. 在本地配置好 Git 环境并 clone 你的 Fork：
   ```bash
   git clone git@github.com:<你的用户名>/nixos-config.git
   cd nixos-config
   ```

**选项二：仅本地保存配置库**
1. 下载并解压配置库：
   ```bash
   curl -L https://github.com/ShaoG-R/nixos-config/archive/refs/heads/main.tar.gz -o config.tar.gz && \
   tar -xzf config.tar.gz && \
   rm config.tar.gz && \
   mv nixos-config-main nixos-config && \
   cd nixos-config
   ```
2. 初始化 Git 仓库（Nix Flakes 必须在 Git 仓库中工作）：
   ```bash
   # 如果你需要彻底脱离原有的 git 历史，可以先删除 .git (通常这一步在下载 tarball 时是不需要的，因为 tarball 不含 .git)
   git init
   git add .
   ```

### 第三步：准备主机配置文件

首先确认你的主机网络环境是否支持 DHCP。我们为您准备了详细的探测教程：
👉 **[如何检测主机是否支持 DHCP](./create_your_own_host/check_dhcp.md)**

如果在上述检测中：

**若支持 DHCP:**
可以直接复制 `server/vps/hyperv.nix` 作为模板：
```bash
cp server/vps/hyperv.nix server/vps/<新主机名>.nix
```
*记得修改 `<新主机名>.nix` 中 `facter.reportPath` 的 `./facter/hyperv.json` 为 `./facter/<新主机名>.json`。*

**若不支持 DHCP (需静态 IP):**
请复制 `server/vps/tohu.nix` 作为模板：
```bash
cp server/vps/tohu.nix server/vps/<新主机名>.nix
```
*需修改 `<新主机名>.nix` 中 `facter.reportPath` 的 `./facter/tohu.json` 为 `./facter/<新主机名>.json`，并根据你主机的实际网络情况修改 `network` 相关配置。*

**关于 SSH 登录配置**

打开生成的 `<新主机名>.nix`，找到 `extraModules` 列表和 `auth` 导入部分。

**1. 修改登录方式 (可选)**
如果你希望允许密码登录（默认为仅 Key 登录），请将 `auth/default.nix` 修改为 `auth/permit_passwd.nix`：

```nix
  extraModules = [
    ./platform/generic.nix
    # ...
    # 修改这里：default.nix (仅Key) -> permit_passwd.nix (允许密码)
    (import ./auth/permit_passwd.nix {
       # ...
    })
    # ...
  ];
```

**2. 设置密码和 SSH Key**
生成你的密码 Hash：
```bash
nix run nixpkgs#mkpasswd -- -m sha-512
```

然后替换配置文件中的 `initialHashedPassword` 和 `authorizedKeys`：

```nix
    (import ./auth/permit_passwd.nix {
      # 用生成的 Hash 替换下面的字符串
      initialHashedPassword = "$6$DhwUDApjyhVCtu4H$mr8WIUeuNrxtoLeGjrMqTtp6jQeQIBuWvq/.qv9yKm3T/g5794hV.GhG78W2rctGDaibDAgS9X9I9FuPndGC01";
      
      # 替换为你的 SSH 公钥
      authorizedKeys = [ "ssh-ed25519 AAAA..." ];
    })
```

### 第四步：生成硬件报告 (facter.json)

我们需要使用 `nixos-facter` 来自动探测硬件配置（如驱动、内核模块等）。请在目标机器上运行：

```bash
nix run \
  --option experimental-features "nix-command flakes" \
  --option extra-substituters https://numtide.cachix.org \
  --option extra-trusted-public-keys numtide.cachix.org-1:2ps1kLBUWjxIneOy1Ik6cQjb41X0iXVXeHigGmycPPE= \
  github:nix-community/nixos-facter -- -o server/vps/facter/<新主机名>.json
```
注意：我们将输出路径直接指定为了仓库中的 `server/vps/facter/<新主机名>.json` （假设你当前在仓库根目录下），如果不在，请移动该文件到对应位置。

### 第五步：注册新主机到 Flake

编辑 `server/vps.nix`，在返回的 Set 中添加你的新主机配置。参考 `tohu` 或 `hyperv` 的配置块，在下方增加：

```nix
  # ... 现有配置 ...
  
  <新主机名> = import ./vps/<新主机名>.nix {
    inherit mkSystem;
    pkgSrc = inputs.nixpkgs-25-11; # 或者使用 inputs.nixpkgs
  };
```

注意：
1. 你的主机文件 `<新主机名>.nix` 应位于 `server/vps/` 目录下。
2. 确保在 `<新主机名>.nix` 中正确配置了 `diskDevice` 和导入了必要的模块（如 `facter.reportPath`）。

最后，提交所有修改到 Git（这对于 Flakes 很重要，未暂存的文件对 Flake 不可见）：
```bash
git add .
git commit -m "Add new host: <新主机名>"
```

现在，你已经准备好使用 `nixos-anywhere` 或构建 Raw 镜像来部署这台新机器了。

---

## 进阶：自定义体验

除了基础的主机配置，你还可以深入定制系统行为。

### 自定义磁盘和文件系统 (`server/vps/disk/specific/common.nix`)

该文件定义了通过 disko 进行的分区布局。
- **文件位置**: `server/vps/disk/specific/common.nix`
- **默认布局**: BIOS+GPT 兼容引导，ESP 分区，Swap 分区，以及一个 Btrfs Root 分区。
- **Btrfs 子卷**: 默认创建了 `@`, `@home`, `@nix`, `@log` 四个子卷，并启用 zstd 压缩。

**如何自定义：**
如果你需要修改分区大小、增加加密 (LUKS) 或改变文件系统（如 ext4, xfs），可以创建 `server/vps/disk/specific/common.nix` 的副本（例如 `custom.nix`），并创建对应的 Swap 封装文件（如 `Swap-Custom.nix`）来引用它。
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
2. **模块化替换**: 如果你不想要这些通用设置，可以在 `<新主机名>.nix` 的 `extraModules` 中移除 `./platform/generic.nix`，并建立自己的 platform 模块。
