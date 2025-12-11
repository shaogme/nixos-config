# 如何创建自己的 NixOS 主机配置

本文档将指导你如何基于本仓库的配置模板，为您自己的 VPS 或物理机创建 NixOS 配置。

由于本配置库采用 Cloud-Native 设计，**请务必先完成 GitHub 仓库的配置**。

## 准备工作

1. **Fork & Configure**: 如果你还没有配置自己的仓库，请先阅读：
   👉 **[GitHub 仓库配置指南](./github_repo_config.md)**

2. **Clone 仓库**: 将你的 Fork 克隆到本地进行编辑。
   ```bash
   git clone git@github.com:<你的用户名>/nixos-config.git
   cd nixos-config
   ```

## 创建流程

### 第一步：准备主机配置

首先确认你的主机网络环境是否支持 DHCP。我们为您准备了详细的探测教程：
👉 **[如何检测主机是否支持 DHCP](./create_your_own_host/check_dhcp.md)**

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

### 第二步：配置自动升级源

为了让 VPS 能够自动从你的仓库拉取更新，你需要修改 `server/vps/profiles/update/auto-upgrade.nix`。

1. 打开该文件。
2. 找到 `flake = "github:ShaoG-R/nixos-config";`。
3. 将 `ShaoG-R` 替换为你的 GitHub 用户名。

### 第三步：SSH 与 认证配置

打开生成的 `<新主机名>.nix`，查看 `auth` 导入部分。

**1. 修改登录方式 (可选)**
如果你希望允许密码登录（默认为仅 Key 登录），请将 `auth/default.nix` 修改为 `auth/permit_passwd.nix`：

```nix
  extraModules = [
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

然后替换配置文件中的 `initialHashedPassword` 和 `authorizedKeys`。

### 第四步：生成硬件报告 (facter.json)

我们需要使用 `nixos-facter` 来自动探测硬件配置。请在目标机器（或其他 Linux 环境）上运行生成，并将结果保存到 `server/vps/facter/<新主机名>.json`。

```bash
# 示例：直接在目标机器上生成并打印（你需要复制内容到本地文件）
nix run github:nix-community/nixos-facter
```

或者如果你按照 README 方式二进入了 Nix 环境，可以直接生成到挂载的仓库目录中。

### 第五步：注册新主机到 Flake

编辑 `server/vps.nix`，在返回的 Set 中添加你的新主机配置。

```nix
  # ... 现有配置 ...
  
  <新主机名> = import ./vps/<新主机名>.nix {
    inherit mkSystem;
    pkgSrc = inputs.nixpkgs-25-11; # 选择使用的 nixpkgs 版本
  };
```

### 第六步：提交、推送与 PR

由于我们对 `main` 分支开启了保护（Best Practice），你不能直接推送到主分支。你需要通过 Pull Request 来合并更改。

1. **创建并切换到新分支**：
   ```bash
   git checkout -b add-host-<新主机名>
   ```

2. **提交更改**：
   ```bash
   git add .
   git commit -m "Add new host: <新主机名>"
   ```

3. **推送到远程**：
   ```bash
   git push -u origin add-host-<新主机名>
   ```

4. **创建 Pull Request**：
   在终端输出中通常会包含一个创建 PR 的链接（或者直接访问你的 GitHub 仓库页面）。
   - 创建 PR 归并入 `main`。
   - 等待 CI (`check-configuration`) 检查通过。
   - 检查通过后，合并 PR。

一旦合并进入 `main`，GitHub Actions 就会开始构建，你的 GitOps 流程正式启动。

**接下来？**
回到主页 [README](../README.md)，选择一种方式（如 GitHub Release + DD）进行安装。

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
