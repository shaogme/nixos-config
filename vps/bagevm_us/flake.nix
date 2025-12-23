{
  description = "bagevm us Configuration";

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
    
    # ==========================================
    # Host Configuration (集中配置区域)
    # ==========================================
    hostConfig = {
      name = "bagevm_us";
      domainRoot = "shaog.uk"; # 主域名，用于拼接

      auth = {
        # 你的 Hash 密码
        rootHash = "$6$TRZIq7fuvInfHmPR$aownw17xjmJ0ZziV.oIpcaWpdCxndZ/zTiWatFS5gblbagK08eagNJcj78NMhieGEIKI2XvBD0vfx4OMWIHco.";
        # SSH Keys
        sshKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKoWKVpkKI/XjU9UPjdHwB7a1bVMUk0/me8iS2gGewkn ed25519 256-20251215 shaog@duck.com" ];
      };

      ipv4 = {
        address = "148.135.184.91";
        prefixLength = 24;
        gateway = "148.135.184.1";
      };
      ipv6 = {
        address = "2602:f988:90:e55::9e5";
        prefixLength = 64;
        gateway = "2602:f988:90::1";
      };
    };
    # ==========================================
    
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
    # 这里的 key 也动态使用 hostConfig.name
    nixosConfigurations.${hostConfig.name} = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inputs = lib-core.inputs; };
      modules = [
        # 1. 引入我们的模块库
        lib-core.nixosModules.default
        cachyos.nixosModules.default
        
        # 2. 通用配置
        commonConfig
        
        # 3. 硬件/Host特有配置 (Production)
        ({ config, pkgs, lib, modulesPath, ... }: {
            networking.hostName = hostConfig.name;
            facter.reportPath = ./facter.json; 

            # Services: Web Apps
            core.app.web.alist = {
                enable = true;
                # 动态拼接域名: alist.cloudcone.shaog.uk
                domain = "alist.${hostConfig.name}.${hostConfig.domainRoot}";
                backend = "podman";
            };
            
            # cat /var/lib/x-ui-yg/init.log 获取账号密码
            core.app.web.x-ui-yg = {
                enable = true;
                # 动态拼接域名: x-ui.cloudcone.shaog.uk
                domain = "x-ui.${hostConfig.name}.${hostConfig.domainRoot}";
                backend = "podman";
                
                # 手动配置防火墙端口范围 (可选，默认是 10000-10005)
                proxyPorts = {
                  start = 16581;
                  end = 16824;
                };
            };

            # cat /run/hysteria/config.yaml 获取 auth 密码
            core.app.hysteria = {
              enable = true;
              backend = "podman";
              # 动态拼接域名: cloudcone.hy.shaog.uk
              domain = "${hostConfig.name}.hy.${hostConfig.domainRoot}";
              
              portHopping = {
                enable = true;
                range = "20000-50000";
                interface = "eth0"; 
              };
              settings = {
                listen = ":20000";
                bandwidth = {
                  up = "1024 mbps";
                  down = "1024 mbps";
                };
                auth = {
                  type = "password";
                  password = ""; 
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
                ipv4 = lib.mkIf (hostConfig ? ipv4) ({ enable = true; } // (hostConfig.ipv4 or {}));
                ipv6 = lib.mkIf (hostConfig ? ipv6) ({ enable = true; } // (hostConfig.ipv6 or {}));
            };
            
            # Auth - 集中引用
            core.auth.root = {
                mode = "default"; # Key-based only
                initialHashedPassword = hostConfig.auth.rootHash;
                authorizedKeys = hostConfig.auth.sshKeys or [];
            };
        })
        
        # 4. 内联测试模块
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