# 主机配置详解

本节详细介绍如何配置主机的 `flake.nix` 文件。本仓库推荐使用 **集中式配置 (hostConfig)** 模式，将主机特有的变量提取到文件顶部，方便管理。

## 场景一：基础配置 (XanMod 内核 + DHCP)

适用于大多数 VPS 或虚拟机（如 Hyper-V），网络使用 DHCP 自动获取，并使用 XanMod 内核提供更好的性能。

参考模板 (`vps/hyperv/flake.nix`)：

```nix
{
  description = "My New Host Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable-small";
    lib-core.url = "path:../../core";
    lib-core.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, lib-core, ... }: 
  let
    system = "x86_64-linux";

    # ==========================================
    # Host Configuration (集中配置区域)
    # ==========================================
    hostConfig = {
      name = "<新主机名>"; # 主机名

      auth = {
        # 密码 Hash (生成方式见下文)
        rootHash = "$6$xxxxxxxx";
        # SSH Keys
        sshKeys = [ "ssh-ed25519 AAAA..." ];
      };
    };
    # ==========================================

    testPkgs = import lib-core.inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };

    commonConfig = { config, pkgs, ... }: {
        system.stateVersion = "25.11"; 
        core.base.enable = true;
        
        # 硬件配置
        core.hardware.type = "vps";
        core.hardware.disk = {
            enable = true;
            swapSize = 2048;
        };
        
        # 性能优化
        core.performance.tuning.enable = true;
        core.memory.mode = "aggressive"; 
        
        # 容器支持
        core.container.podman.enable = true;
        
        # 自动更新
        core.base.update = {
            enable = true;
            allowReboot = true;
        };
    };
  in
  {
    nixosConfigurations.${hostConfig.name} = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inputs = lib-core.inputs; };
      modules = [
        lib-core.nixosModules.default
        lib-core.nixosModules.kernel-xanmod # 引入 XanMod 内核模块

        commonConfig
        
        # 主机特有配置
        ({ config, pkgs, modulesPath, ... }: {
            networking.hostName = hostConfig.name;
            facter.reportPath = ./facter.json;
            
            # 网络配置 (DHCP)
            core.hardware.network.single-interface = {
                enable = true;
                dhcp.enable = true;
            };
            
            # 认证配置
            core.auth.root = {
                mode = "default";
                initialHashedPassword = hostConfig.auth.rootHash;
                authorizedKeys = hostConfig.auth.sshKeys;
            };
        })
        
        # 内联 VM 测试
        ({ config, pkgs, ... }: {
          system.build.vmTest = pkgs.testers.nixosTest {
            name = "${hostConfig.name}-inline-test";
            nodes.machine = { config, lib, ... }: {
                imports = [ 
                    lib-core.nixosModules.default 
                    lib-core.nixosModules.kernel-xanmod
                    commonConfig
                ];
                nixpkgs.pkgs = testPkgs;
                _module.args.inputs = lib-core.inputs;
                networking.hostName = "${hostConfig.name}-test";
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

## 场景二：进阶配置 (CachyOS 内核 + 静态 IP + Web 服务)

适用于高性能需求场景，使用 CachyOS 内核，手动配置静态 IP，并暴露 Web 服务。

参考模板 (`vps/cloudcone/flake.nix`)：

```nix
{
  description = "High Performance Host Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable-small";
    lib-core.url = "path:../../core";
    lib-core.inputs.nixpkgs.follows = "nixpkgs";
    
    # 引入 CachyOS 内核源 (稳定版或 unstable)
    cachyos.url = "path:../../extra/kernel/cachyos-unstable";
    cachyos.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, lib-core, cachyos, ... }: 
  let
    system = "x86_64-linux";
    
    # ==========================================
    # Host Configuration
    # ==========================================
    hostConfig = {
      name = "<新主机名>";
      domainRoot = "example.com"; # 根域名

      auth = {
        rootHash = "$6$xxxxxxxx";
        sshKeys = [ "ssh-ed25519 AAAA..." ];
      };

      # 静态 IP 配置
      ipv4 = {
        address = "192.168.1.100";
        gateway = "192.168.1.1";
        prefixLength = 24;
      };
    };
    
    # 使用 CachyOS 提供的 makeTestPkgs 以包含必要的 chaotic overlay
    testPkgs = cachyos.lib.makeTestPkgs system;
    
    commonConfig = { config, pkgs, ... }: {
        system.stateVersion = "25.11"; 
        core.base.enable = true;
        core.hardware.type = "vps";
        core.hardware.disk = { enable = true; swapSize = 2048; };
        
        core.performance.tuning.enable = true;
        core.memory.mode = "aggressive";
        core.container.podman.enable = true;
        
        core.base.update = { enable = true; allowReboot = true; };
    };
  in
  {
    nixosConfigurations.${hostConfig.name} = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inputs = lib-core.inputs; };
      modules = [
        lib-core.nixosModules.default
        cachyos.nixosModules.default # 使用 CachyOS 模块
        
        commonConfig
        
        
        ({ config, pkgs, lib, modulesPath, ... }: {
            networking.hostName = hostConfig.name;
            facter.reportPath = ./facter.json; 
            
            # 自动配置静态 IP (如果 hostConfig 中定义了 ipv4/ipv6)
            core.hardware.network.single-interface = {
                enable = true;
                ipv4 = lib.mkIf (hostConfig ? ipv4) ({ enable = true; } // (hostConfig.ipv4 or {}));
                ipv6 = lib.mkIf (hostConfig ? ipv6) ({ enable = true; } // (hostConfig.ipv6 or {}));
            };
            
            # 认证
            core.auth.root = {
                mode = "default";
                initialHashedPassword = hostConfig.auth.rootHash;
                authorizedKeys = hostConfig.auth.sshKeys or [];
            };

            # 示例服务：Alist
            core.app.web.alist = {
                enable = true;
                domain = "alist.${hostConfig.name}.${hostConfig.domainRoot}";
                backend = "podman";
            };
        })
        
        # 内联测试 (注意 commonConfig 包含了 cachyos 模块引用，需确保测试环境也能访问)
        ({ config, pkgs, ... }: {
          system.build.vmTest = pkgs.testers.nixosTest {
            name = "${hostConfig.name}-inline-test";
            nodes.machine = { config, lib, ... }: {
                imports = [ 
                    lib-core.nixosModules.default 
                    cachyos.nixosModules.default
                    commonConfig
                ];
                nixpkgs.pkgs = testPkgs;
                _module.args.inputs = lib-core.inputs;
                networking.hostName = "${hostConfig.name}-test";
                core.auth.root.mode = "permit_passwd";
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

## 认证配置说明

### 生成密码 Hash

在任何安装了 Nix 的机器上运行：

```bash
nix run nixpkgs#mkpasswd -- -m sha-512
```

将生成的字符串填入 `hostConfig.auth.rootHash`。

### 添加 SSH 公钥

将你的 SSH 公钥内容 (通常在 `~/.ssh/id_ed25519.pub`) 添加到 `hostConfig.auth.sshKeys` 列表。

### 认证模式

`core.auth.root.mode` 支持以下模式：

| 模式 | SSH 密码登录 | SSH 密钥登录 | 说明 |
|------|-------------|-------------|------|
| `default` | ❌ 禁止 | ✅ 允许 | 推荐，最安全 |
| `permit_passwd` | ✅ 允许 | ✅ 允许 | 开发/调试用，不安全 |

## 内联 VM 测试

我们在配置中包含了一个 `vmTest` 模块。这利用了 NixOS 的测试框架，在构建时启动一个轻量级虚拟机来验证系统能否正常启动。

**运行测试：**

```bash
nix build .#nixosConfigurations.<新主机名>.config.system.build.vmTest
```

如果构建成功，说明系统基本配置无误，容器运行环境正常。
