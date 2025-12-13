# 创建自定义主机配置

本文档指导你如何基于本仓库的模块库，为你的 VPS 或物理机创建 NixOS 配置。

---

## 架构概述

本仓库采用 **模块库 + 独立主机配置** 的分离架构：

```
nixos-config/
├── flake.nix              # 模块库入口
├── core/               # 可复用模块
└── vps/                   # 主机配置目录
    ├── tohu/              # 示例主机 1
    │   ├── flake.nix      # 主机配置 (独立 flake)
    │   └── facter.json    # 硬件探测报告
    └── hyperv/            # 示例主机 2
        ├── flake.nix
        └── facter.json
```

每个主机都是一个**独立的 Flake**，通过 `lib-core.url = "path:../../"` 引用模块库。

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

### 第二步：确定网络配置方式

首先确认你的主机网络环境：

👉 **[如何检测主机是否支持 DHCP](./create_your_own_host/check_dhcp.md)**

根据结果选择合适的模板：

**DHCP 环境 (推荐):**
```bash
cp ../hyperv/flake.nix ./flake.nix
```

**静态 IP 环境:**
```bash
cp ../tohu/flake.nix ./flake.nix
```

### 第三步：编辑主机配置

打开 `flake.nix`，根据以下模板进行配置：

```nix
{
  description = "<新主机名> Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable-small";
    lib-core.url = "path:../../";
    lib-core.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, lib-core, ... }: 
  let
    # 通用配置 (用于实际部署和测试)
    commonConfig = { config, pkgs, ... }: {
      system.stateVersion = "25.11"; 
      core.base.enable = true;
      
      # ========== 硬件配置 ==========
      core.hardware.type = "vps";  # "vps" 或 "physical"
      core.hardware.disk = {
        enable = true;
        device = "/dev/sda";     # 磁盘设备
        swapSize = 2048;         # Swap 大小 (MB)，0 禁用
      };
      
      # ========== 性能配置 ==========
      core.performance.tuning.enable = true;
      core.memory.mode = "aggressive";  # "conservative" / "aggressive"
      
      # ========== 容器配置 ==========
      core.container.podman.enable = true;
      
      # ========== 自动更新配置 ==========
      core.base.update = {
        enable = true;
        allowReboot = true;       # 更新后自动重启
        # flakeUri 默认使用 github:ShaoG-R/nixos-config?dir=vps/${hostName}
        # 如需自定义，取消下行注释:
        # flakeUri = "github:<你的用户名>/nixos-config?dir=vps/<主机名>";
      };
    };
  in
  {
    nixosConfigurations.<新主机名> = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inputs = lib-core.inputs; };
      modules = [
        # 1. 引入模块库
        lib-core.nixosModules.default
        lib-core.nixosModules.kernel-xanmod  # 或 kernel-cachyos / kernel-cachyos-unstable
        
        # 2. 通用配置
        commonConfig
        
        # 3. 主机特有配置
        ({ config, pkgs, ... }: {
          networking.hostName = "<新主机名>";
          facter.reportPath = ./facter.json;
          
          # ========== 网络配置 ==========
          # DHCP 模式:
          core.hardware.network.single-interface = {
            enable = true;
            dhcp.enable = true;
          };
          
          # 静态 IP 模式 (取消注释并配置):
          # core.hardware.network.single-interface = {
          #   enable = true;
          #   ipv4 = {
          #     enable = true;
          #     address = "192.168.1.100";
          #     prefixLength = 24;
          #     gateway = "192.168.1.1";
          #   };
          # };
          
          # ========== 认证配置 ==========
          core.auth.root = {
            mode = "default";  # "default" (仅密钥) 或 "permit_passwd" (允许密码)
            initialHashedPassword = "$6$...";  # 密码 Hash (见下方生成方法)
            authorizedKeys = [ 
              "ssh-ed25519 AAAA..." 
            ];
          };
          
          # ========== 应用服务 (可选) ==========
          # core.app.web.alist = {
          #   enable = true;
          #   domain = "alist.example.com";
          #   backend = "podman";
          # };
        })
        
        # 4. 内联测试模块 (可选，见下方)
      ];
    };
  };
}
```

### 第四步：配置认证

#### 生成密码 Hash

```bash
nix run nixpkgs#mkpasswd -- -m sha-512
```

将生成的 Hash 填入 `core.auth.root.initialHashedPassword`。

#### 添加 SSH 公钥

将你的 SSH 公钥添加到 `core.auth.root.authorizedKeys` 列表。

查看本地公钥:
```bash
cat ~/.ssh/id_ed25519.pub
```

#### 认证模式说明

| 模式 | SSH 密码登录 | SSH 密钥登录 | 说明 |
|------|-------------|-------------|------|
| `default` | ❌ 禁止 | ✅ 允许 | 推荐，更安全 |
| `permit_passwd` | ✅ 允许 | ✅ 允许 | 密码登录，方便但不安全 |

### 第五步：生成硬件报告

在目标机器上运行 `nixos-facter` 生成硬件探测报告：

```bash
# 方法 1: 在目标机器上直接生成
nix run github:nix-community/nixos-facter -- -o facter.json

# 方法 2: 远程执行并保存到本地
ssh root@<TARGET_IP> "nix run --extra-experimental-features 'nix-command flakes' github:nix-community/nixos-facter" > facter.json
```

将 `facter.json` 保存到主机目录 (`vps/<新主机名>/facter.json`)。

### 第六步：选择内核

根据需求选择内核模块：

| 模块 | 适用场景 | 需要额外 overlay |
|------|---------|-----------------|
| `kernel-xanmod` | 通用兼容性好，无需额外配置 | ❌ |
| `kernel-cachyos` | CachyOS 稳定版，性能优化 | ✅ chaotic |
| `kernel-cachyos-unstable` | CachyOS 最新版，最激进优化 | ✅ chaotic 完整 |

---

## 添加内联测试 (可选)

为了验证配置正确性，可以添加内联 VM 测试：

```nix
# 在 modules 列表末尾添加
({ config, pkgs, ... }: 
let
  testPkgs = import lib-core.inputs.nixpkgs {
    system = "x86_64-linux";
    config.allowUnfree = true;
    # 如果使用 cachyos 内核，需要添加 overlay:
    # overlays = [ lib-core.inputs.chaotic.overlays.default ];
  };
in {
  system.build.vmTest = pkgs.testers.nixosTest {
    name = "<新主机名>-inline-test";
    
    nodes.machine = { config, lib, ... }: {
      imports = [ 
        lib-core.nixosModules.default 
        lib-core.nixosModules.kernel-xanmod
        commonConfig
      ];
      
      nixpkgs.pkgs = testPkgs;
      # testers.nixosTest 不支持 specialArgs，需要在这里注入 inputs
      _module.args.inputs = lib-core.inputs;
      networking.hostName = "<新主机名>-test";
    };
    
    testScript = ''
      start_all()
      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("podman.socket")
    '';
  };
})
```

运行测试:
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

- CI 会自动运行配置检查
- 检查通过后合并 PR
- 合并后可触发镜像构建

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
```

---

## 下一步

配置完成后，前往安装指南进行部署：

👉 **[安装指南](./install.md)**
