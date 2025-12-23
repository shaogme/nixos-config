# 创建自定义主机配置

本文档指导你如何基于本仓库的模块库，为你的 VPS 或物理机创建 NixOS 配置。

---

## 架构概述

本仓库采用 **Core + Extra + 独立主机配置** 的分层架构：

```
nixos-config/
├── flake.nix              # 聚合入口 (整合 core + extra，提供 VM 测试)
├── core/                  # 📦 核心模块库
│   ├── flake.nix          # Core 入口
│   ├── app/               # 应用服务
│   ├── base/              # 基础系统
│   ├── hardware/          # 硬件配置
│   └── kernel/            # XanMod 内核
├── extra/                 # 🧪 扩展模块
│   └── kernel/
│       ├── cachyos/           # CachyOS 稳定内核
│       └── cachyos-unstable/  # CachyOS 不稳定内核
└── vps/                   # 🖥️ 主机配置目录
    ├── cloudcone/              # 示例主机 1 (使用 CachyOS)
    │   ├── flake.nix
    │   └── facter.json
    └── hyperv/            # 示例主机 2 (使用 XanMod)
        ├── flake.nix
        └── facter.json
```

每个主机都是一个**独立的 Flake**，通过 GitHub URL 引用 `core` 和 `extra` 模块。

---

## 准备工作

### 1. Fork 仓库

如果你还没有配置自己的仓库，请先阅读：

👉 **[GitHub 仓库配置指南](./github_repo_config.md)**

### 2. Clone 到本地

```bash
git clone git@github.com:<你的用户名>/nixos-config.git
cd nixos-config
```

---

## 创建主机配置

### 第一步：创建主机目录

```bash
# 创建新主机目录
mkdir -p vps/<新主机名>
cd vps/<新主机名>
```

### 第二步：在远程主机获取必要配置

该步骤首先安装 nix (若不是 nixos)
然后运行
```bash
curl -O https://raw.githubusercontent.com/ShaoG-R/nixos-config/refs/heads/main/scripts/check-net.sh && chmod +x check-net.sh && ./check-net.sh 
```
将对应的静态配置复制进 hostConfig 内，对应修改 core.hardware.network.single-interface 部分

#### 生成硬件报告

在目标机器上运行 `nixos-facter` 生成硬件探测报告：

```bash
# 方法 1: 在目标机器上直接生成
nix run github:nix-community/nixos-facter -- -o facter.json

# 方法 2: 远程执行并保存到本地
ssh root@<TARGET_IP> "nix run --extra-experimental-features 'nix-command flakes' github:nix-community/nixos-facter" > facter.json
```

将 `facter.json` 保存到主机目录 (`vps/<新主机名>/facter.json`)。

### 第三步：选择内核

根据需求选择内核模块：

| 内核 | 引用方式 | 适用场景 | 需要额外 overlay |
|------|----------|---------|-----------------|
| XanMod | `lib-core.nixosModules.kernel-xanmod` | 通用兼容性好，无需额外配置 | ❌ |
| CachyOS | 单独引入 `extra/kernel/cachyos` | CachyOS 稳定版，性能优化 | ✅ chaotic |
| CachyOS Unstable | 单独引入 `extra/kernel/cachyos-unstable` | CachyOS 最新版，最激进优化 | ✅ chaotic 完整 |

### 第四步：编辑主机配置与认证

请阅读下列文档，根据你的需求（内核选择、网络环境）编写 `flake.nix`：

👉 **[主机配置详解](./create_your_own_host/host_configuration.md)**

该文档包含了：
1. **基础配置模板** (XanMod + DHCP)
2. **进阶配置模板** (CachyOS + 静态 IP + Web 服务)
3. **认证配置** (密码 Hash 与 SSH Key)
4. **内联测试** 的运行方法

### 第五步：运行测试

配置完成后，请按照上述文档中的说明运行内联测试，确保配置无误。

```bash
nix build .#nixosConfigurations.<新主机名>.config.system.build.vmTest
```


---

## 提交配置

### 1. 创建新分支

```bash
git checkout -b add-host-<新主机名>
```

### 2. 提交更改

本仓库的 CI/CD 系统已实现**自动化主机发现**。你**不需要**手动修改任何 GitHub Actions 配置文件。

只要 `vps/<新主机名>/` 目录下包含 `flake.nix` 文件，Workflow 会自动识别并将其加入测试和发布的矩阵中。

```bash
git add vps/<新主机名>/
git commit -m "Add new host: <新主机名>"
```

### 3. 推送并创建 PR

```bash
git push -u origin add-host-<新主机名>
```

在 GitHub 上创建 Pull Request 合并到 `main` 分支。

### 4. 等待 CI 检查

- `ci.yml` 会自动扫描 `vps/` 目录，并为新主机运行检测。
- 检查通过后合并 PR
- 你的新主机现在已经正式加入到 GitOps 流程中了！
- 未来 `update-flake.yml` 也会自动维护该主机的 `flake.lock`。

---

## 进阶配置

### 自定义磁盘布局

`core.hardware.disk` 模块提供的默认布局：

```
/dev/sda
├── sda1 (1MB)     - BIOS Boot
├── sda2 (32MB)    - ESP (/boot/efi)
├── sda3 (可选)    - Swap
└── sda4 (剩余)    - Btrfs Root
    ├── @          → /
    ├── @home      → /home
    ├── @nix       → /nix
    └── @log       → /var/log
```

如需自定义，可以禁用 `core.hardware.disk.enable` 并使用原生 Disko 配置。

### 自定义自动更新源

默认情况下，自动更新会从你的 GitHub 仓库拉取：

```nix
core.base.update.flakeUri = "github:<你的用户名>/nixos-config?dir=vps/<主机名>";
```

如果你的仓库名称或结构不同，请相应修改此选项。

### 添加应用服务

本仓库提供了一些预配置的应用服务模块：

```nix
# Alist 文件列表
core.app.web.alist = {
  enable = true;
  domain = "files.example.com";
  backend = "podman";
};

# X-UI-YG 代理面板
core.app.web.x-ui-yg = {
  enable = true;
  domain = "panel.example.com";
  backend = "podman";
};

# Hysteria 代理服务
core.app.hysteria = {
  enable = true;
  backend = "podman"; # docker or podman
  
  # 如果设置了 domain，将自动配置 Nginx 处理 ACME
  domain = "hy.example.com"; 
  
  portHopping = {
    enable = true;
    range = "20000-50000";
    interface = "eth0"; 
  };
  
  settings = {
    listen = ":20000";
    bandwidth = { up = "512 mbps"; down = "512 mbps"; };
    auth = { type = "password"; password = "your_password"; };
  };
};
```

---

## 下一步

配置完成后，前往安装指南进行部署：

👉 **[安装指南](./install.md)**
