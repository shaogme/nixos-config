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
    ├── tohu/              # 示例主机 1 (使用 CachyOS)
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

### 第三步：选择内核

根据需求选择内核模块：

| 内核 | 引用方式 | 适用场景 | 需要额外 overlay |
|------|----------|---------|-----------------|
| XanMod | `lib-core.nixosModules.kernel-xanmod` | 通用兼容性好，无需额外配置 | ❌ |
| CachyOS | 单独引入 `extra/kernel/cachyos` | CachyOS 稳定版，性能优化 | ✅ chaotic |
| CachyOS Unstable | 单独引入 `extra/kernel/cachyos-unstable` | CachyOS 最新版，最激进优化 | ✅ chaotic 完整 |

### 第四步：编辑主机配置

根据所选内核，参考以下模板进行配置：

#### 使用 XanMod 内核 (推荐新手)

```nix
{
  description = "<新主机名> Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable-small";
    lib-core.url = "github:ShaoG-R/nixos-config?dir=core";
    lib-core.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, lib-core, ... }: 
  let
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
        allowReboot = true;
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
        lib-core.nixosModules.kernel-xanmod
        
        # 2. 通用配置
        commonConfig
        
        # 3. 主机特有配置
        ({ config, pkgs, ... }: {
          networking.hostName = "<新主机名>";
          facter.reportPath = ./facter.json;
          
          # 网络配置 (DHCP)
          core.hardware.network.single-interface = {
            enable = true;
            dhcp.enable = true;
          };
          
          # 认证配置
          core.auth.root = {
            mode = "default";
            authorizedKeys = [ "ssh-ed25519 AAAA..." ];
          };
        })
        
        # 4. 内联测试模块 (见下方)
      ];
    };
  };
}
```

#### 使用 CachyOS 内核

```nix
{
  description = "<新主机名> Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable-small";
    lib-core.url = "github:ShaoG-R/nixos-config?dir=core";
    lib-core.inputs.nixpkgs.follows = "nixpkgs";
    
    # CachyOS 内核 (选择稳定版或不稳定版)
    cachyos.url = "github:ShaoG-R/nixos-config?dir=extra/kernel/cachyos-unstable";
    cachyos.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, lib-core, cachyos, ... }: 
  let
    system = "x86_64-linux";
    
    # 使用 cachyos flake 提供的 testPkgs 构建函数
    testPkgs = cachyos.lib.makeTestPkgs system;
    
    commonConfig = { config, pkgs, ... }: {
      system.stateVersion = "25.11"; 
      core.base.enable = true;
      
      core.hardware.type = "vps";
      core.hardware.disk = {
        enable = true;
        swapSize = 2048;
      };
      
      core.performance.tuning.enable = true;
      core.memory.mode = "aggressive";
      core.container.podman.enable = true;
      
      core.base.update = {
        enable = true;
        allowReboot = true;
      };
    };
  in
  {
    nixosConfigurations.<新主机名> = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inputs = lib-core.inputs; };
      modules = [
        # 1. 引入模块库
        lib-core.nixosModules.default
        cachyos.nixosModules.default  # CachyOS 内核
        
        # 2. 通用配置
        commonConfig
        
        # 3. 主机特有配置
        ({ config, pkgs, ... }: {
          networking.hostName = "<新主机名>";
          facter.reportPath = ./facter.json;
          
          # 网络配置 (静态 IP 示例)
          core.hardware.network.single-interface = {
            enable = true;
            ipv4 = {
              enable = true;
              address = "192.168.1.100";
              prefixLength = 24;
              gateway = "192.168.1.1";
            };
          };
          
          # 认证配置
          core.auth.root = {
            mode = "default";
            authorizedKeys = [ "ssh-ed25519 AAAA..." ];
          };
        })
        
        # 4. 内联测试模块 (使用 cachyos testPkgs)
        ({ config, pkgs, ... }: {
          system.build.vmTest = pkgs.testers.nixosTest {
            name = "<新主机名>-inline-test";
            
            nodes.machine = { config, lib, ... }: {
              imports = [ 
                lib-core.nixosModules.default 
                cachyos.nixosModules.default
                commonConfig
              ];
              
              nixpkgs.pkgs = testPkgs;
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
      ];
    };
  };
}
```

### 第五步：配置认证

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

### 第六步：生成硬件报告

在目标机器上运行 `nixos-facter` 生成硬件探测报告：

```bash
# 方法 1: 在目标机器上直接生成
nix run github:nix-community/nixos-facter -- -o facter.json

# 方法 2: 远程执行并保存到本地
ssh root@<TARGET_IP> "nix run --extra-experimental-features 'nix-command flakes' github:nix-community/nixos-facter" > facter.json
```

将 `facter.json` 保存到主机目录 (`vps/<新主机名>/facter.json`)。

---

## 添加内联测试

为了验证配置正确性，建议添加内联 VM 测试。

### XanMod 内核测试模块

```nix
({ config, pkgs, ... }: 
let
  testPkgs = import lib-core.inputs.nixpkgs {
    system = "x86_64-linux";
    config.allowUnfree = true;
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

### CachyOS 内核测试模块

CachyOS 需要使用带有 chaotic overlay 的 testPkgs:

```nix
({ config, pkgs, ... }: {
  system.build.vmTest = pkgs.testers.nixosTest {
    name = "<新主机名>-inline-test";
    
    nodes.machine = { config, lib, ... }: {
      imports = [ 
        lib-core.nixosModules.default 
        cachyos.nixosModules.default
        commonConfig
      ];
      
      # 使用 cachyos flake 提供的 testPkgs
      nixpkgs.pkgs = testPkgs;
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

### 运行测试

```bash
nix build .#nixosConfigurations.<新主机名>.config.system.build.vmTest
```

---

## 提交配置

### 1. 创建新分支

```bash
git checkout -b add-host-<新主机名>
```

### 2. 更新 CI 配置

在 `.github/workflows/vps-hosts-ci.yml` 中的 matrix 添加新主机:

```yaml
matrix:
  host: [hyperv, tohu, <新主机名>]
```

### 3. 提交更改

```bash
git add vps/<新主机名>/
git add .github/workflows/vps-hosts-ci.yml
git commit -m "Add new host: <新主机名>"
```

### 4. 推送并创建 PR

```bash
git push -u origin add-host-<新主机名>
```

在 GitHub 上创建 Pull Request 合并到 `main` 分支。

### 5. 等待 CI 检查

- `ci.yml` 会自动运行 flake 检查和三种内核的 VM 测试
- 检查通过后合并 PR
- 合并后 `vps-hosts-ci.yml` 会自动运行新主机的测试
- 测试成功后会自动触发 `update-flake.yml` 更新依赖

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
