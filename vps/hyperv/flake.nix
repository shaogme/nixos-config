{
  description = "Hyperv 临时配置";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
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
      name = "hyperv";

      auth = {
        # 你的 Hash 密码
        rootHash = "$6$/IQfGTA5Et3n24DW$1oIQHcGY0JcoQi9SRGEORUzslt26QRU8DmuOezps7iJeiQOJG0EP4.6zl2fdKhUI3qYgo09nVBUGKQFrulsFh0";
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
        
        boot.kernelPackages = pkgs.linuxPackages_5_15;
        
        # Hardware
        core.hardware.type = "vps";
        core.hardware.disk = {
            enable = true;
        };
        
        # Performance
        core.performance.tuning.enable = true;
        core.memory.mode = "conservative";
        
        # Container
        core.container.podman.enable = true;
        
        # Update
        core.base.update = {
            enable = true;
            allowReboot = true;
        };

        ###################### 以下是开发环境配置 ######################

        # 启用 nix-ld
        # 这是在 NixOS 上运行 VS Code Remote Server 的现代标准解决方案
        programs.nix-ld.enable = true;
        programs.nix-ld.libraries = with pkgs; [
            # VS Code Server 需要的一些常见库
            stdenv.cc.cc
            zlib
            openssl
            glib
            # ... 其他库通常 nix-ld 会自动处理大部分
        ];

        # 安装并启用 direnv
        # 这让系统能识别 .envrc 文件，自动加载 flake 环境
        programs.direnv = {
            enable = true;
            nix-direnv.enable = true; # 启用 nix 集成，速度更快
        };

        # 确保系统包里有 git (flake 需要)
        environment.systemPackages = with pkgs; [
            git
            vim
            wget
        ];
    };
  in
  {
    nixosConfigurations.${hostConfig.name} = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inputs = lib-core.inputs; };
      modules = [
        # 1. 引入我们的模块库
        lib-core.nixosModules.default
        
        # 2. 通用配置
        commonConfig
        
        # 3. 硬件/Host特有配置 (Production)
        ({ config, pkgs, lib, modulesPath, ... }: {
            networking.hostName = hostConfig.name;
            facter.reportPath = ./facter.json;
            
            core.hardware.network.single-interface = {
                enable = true;
                ipv4 = lib.mkIf (hostConfig ? ipv4) ({ enable = true; } // (hostConfig.ipv4 or {}));
                ipv6 = lib.mkIf (hostConfig ? ipv6) ({ enable = true; } // (hostConfig.ipv6 or {}));
            };
            
            # Auth - 集中引用
            core.auth.root = {
                mode = "permit_passwd"; # Key-based only
                initialHashedPassword = hostConfig.auth.rootHash;
                authorizedKeys = hostConfig.auth.sshKeys or [];
            };
        })
        
        # 4. 内联测试模块
        # 使用 testers.nixosTest 而非 runtesters.nixosTest，因为后者会将 nixpkgs.* 设为只读
        ({ config, pkgs, ... }: {
          system.build.vmTest = pkgs.testers.nixosTest {
            name = "${hostConfig.name}-inline-test";
            
            nodes.machine = { config, lib, ... }: {
                imports = [ 
                    lib-core.nixosModules.default 
                    commonConfig
                ];
                
                # testers.nixosTest 允许设置 nixpkgs.pkgs
                nixpkgs.pkgs = testPkgs;
                
                # testers.nixosTest 不支持 specialArgs，需要在这里注入 inputs
                _module.args.inputs = lib-core.inputs;
                
                networking.hostName = "${hostConfig.name}-test";
                core.auth.root.mode = "permit_passwd";
            };
            testScript = ''
              start_all()
              machine.wait_for_unit("multi-user.target")
              machine.wait_for_unit("podman.socket")
              
              # Check kernel version
              kernel_version = machine.succeed("uname -r").strip()
              print(f"Kernel version: {kernel_version}")
              assert kernel_version.startswith("5.15"), f"Expected kernel 5.15, but got {kernel_version}"
            '';
          };
        })
      ];
    };
  };
}