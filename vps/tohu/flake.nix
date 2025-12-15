{
  description = "tohu Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable-small";
    lib-core.url = "path:../../core";
    lib-core.inputs.nixpkgs.follows = "nixpkgs";
    cachyos.url = "path:../../extra/kernel/cachyos-unstable";
    cachyos.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, lib-core, cachyos, ... }: 
  let
    system = "x86_64-linux";
    
    # 使用 kernel flake 暴露的便捷函数构建 testPkgs
    testPkgs = cachyos.lib.makeTestPkgs system;
    
    commonConfig = { config, pkgs, ... }: {
        system.stateVersion = "25.11"; 
        core.base.enable = true;
        
        # Hardware
        core.hardware.type = "vps";
        core.hardware.disk = {
            enable = true;
            swapSize = 2048;
        };
        
        # Performance
        core.performance.tuning.enable = true;
        core.memory.mode = "aggressive";
        
        # Services: DNS
        core.dns.smartdns.mode = "oversea";

        # Container
        core.container.podman.enable = true;
        
        # Update
        core.base.update = {
            enable = true;
            allowReboot = true;
        };
    };
  in
  {
    nixosConfigurations.tohu = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inputs = lib-core.inputs; };
      modules = [
        # 1. 引入我们的模块库
        lib-core.nixosModules.default
        cachyos.nixosModules.default
        
        # 2. 通用配置
        commonConfig
        
        # 3. 硬件/Host特有配置 (Production)
        ({ config, pkgs, modulesPath, ... }: {
            networking.hostName = "tohu";
            facter.reportPath = ./facter.json; 

            # Services: Web Apps
            core.app.web.alist = {
                enable = true;
                domain = "alist.tohu.shaog.uk";
                backend = "podman";
            };
            
            core.app.web.x-ui-yg = {
                enable = true;
                domain = "x-ui.tohu.shaog.uk";
                backend = "podman";
            };

            core.app.hysteria = {
              enable = true;
              backend = "podman";
              portHopping = {
                enable = true;
                range = "20000-50000";
                interface = "eth0"; # Assuming eth0 based on common patterns, user can adjust if needed
              };
              settings = {
                listen = ":20000";
                acme = {
                  domains = [ "tohu.hy.shaog.uk" ];
                  email = "shaog@duck.com";
                };
                bandwidth = {
                  up = "512 mbps";
                  down = "512 mbps";
                };
                auth = {
                  type = "password";
                  password = ""; # Placeholder for auto-generation/user setting
                };
                outbounds = [
                  {
                    name = "default";
                    type = "direct";
                  }
                ];
              };
            };
            core.hardware.network.single-interface = {
                enable = true;
                ipv4 = {
                enable = true;
                address = "66.235.104.29";
                prefixLength = 24;
                gateway = "66.235.104.1";
                };
            };
            
            # Auth
            core.auth.root = {
                mode = "default"; # Key-based only
                initialHashedPassword = "$6$DhwUDApjyhVCtu4H$mr8WIUeuNrxtoLeGjrMqTtp6jQeQIBuWvq/.qv9yKm3T/g5794hV.GhG78W2rctGDaibDAgS9X9I9FuPndGC01";
                authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBaNS9FByCEaDjPOUpeQZg58zM2wD+jEY6SkIbE1k3Zn ed25519 256-20251206 shaog@duck.com" ];
            };
        })
        
        # 4. 内联测试模块
        ({ config, pkgs, ... }: {
          system.build.vmTest = pkgs.testers.nixosTest {
            name = "tohu-inline-test";
            
            nodes.machine = { config, lib, ... }: {
                imports = [ 
                    lib-core.nixosModules.default 
                    cachyos.nixosModules.default
                    commonConfig
                ];
                
                # 使用 kernel flake 提供的 testPkgs
                nixpkgs.pkgs = testPkgs;
                
                # testers.nixosTest 不支持 specialArgs，需要在这里注入 inputs
                _module.args.inputs = lib-core.inputs;
                
                networking.hostName = "tohu-test";
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