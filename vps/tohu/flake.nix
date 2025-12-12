{
  description = "tohu Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable-small";
    my-lib.url = "path:../../";
    my-lib.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, my-lib, ... }: 
  let
    commonConfig = { config, pkgs, ... }: {
        system.stateVersion = "25.11"; 
        my.base.enable = true;
        
        # Hardware
        my.hardware.type = "vps";
        my.hardware.disk = {
            enable = true;
            swapSize = 2048;
        };
        
        # Kernel & Performance
        my.performance.kernel.mode = "cachyos-unstable";
        my.performance.tuning.enable = true;
        my.memory.mode = "aggressive";
        
        # Services: DNS
        my.dns.smartdns.mode = "oversea";

        # Container
        my.container.podman.enable = true;
        
        # Update
        my.base.update = {
            enable = true;
            allowReboot = true;
        };
    };
  in
  {
    nixosConfigurations.tohu = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inputs = my-lib.inputs; };
      modules = [
        # 1. 引入我们的模块库
        my-lib.nixosModules.default
        
        # 2. 通用配置
        commonConfig
        
        # 3. 硬件/Host特有配置 (Production)
        ({ config, pkgs, modulesPath, ... }: {
            networking.hostName = "tohu";
            facter.reportPath = ./facter.json; 

            # Services: Web Apps
            my.app.web.alist = {
                enable = true;
                domain = "alist.tohu.shaog.uk";
                backend = "podman";
            };
            
            my.app.web.x-ui-yg = {
                enable = true;
                domain = "x-ui.tohu.shaog.uk";
                backend = "podman";
            };
            
            
            my.hardware.network.single-interface = {
                enable = true;
                ipv4 = {
                enable = true;
                address = "66.235.104.29";
                prefixLength = 24;
                gateway = "66.235.104.1";
                };
            };
            
            # Auth
            my.auth.root = {
                mode = "default"; # Key-based only
                initialHashedPassword = "$6$DhwUDApjyhVCtu4H$mr8WIUeuNrxtoLeGjrMqTtp6jQeQIBuWvq/.qv9yKm3T/g5794hV.GhG78W2rctGDaibDAgS9X9I9FuPndGC01";
                authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBaNS9FByCEaDjPOUpeQZg58zM2wD+jEY6SkIbE1k3Zn ed25519 256-20251206 shaog@duck.com" ];
            };
        })
        
        # 4. 内联测试模块
        ({ config, pkgs, ... }: {
          system.build.vmTest = pkgs.testers.runNixOSTest {
            name = "tohu-inline-test";
            node.specialArgs = { inputs = my-lib.inputs; };
            node.pkgs = nixpkgs.lib.mkForce pkgs;
            nodes.machine = { config, lib, ... }: {
                imports = [ 
                    my-lib.nixosModules.default 
                    commonConfig
                ];
                
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