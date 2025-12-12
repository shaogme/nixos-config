{
  description = "hyperv Configuration";

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
            swapSize = 4096;
        };
        
        # Kernel & Performance
        my.performance.kernel.mode = "xanmod";
        my.performance.tuning.enable = true;
        my.memory.mode = "conservative";
        
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
    nixosConfigurations.hyperv = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inputs = my-lib.inputs; };
      modules = [
        # 1. 引入我们的模块库
        my-lib.nixosModules.default
        
        # 2. 通用配置
        commonConfig
        
        # 3. 硬件/Host特有配置 (Production)
        ({ config, pkgs, modulesPath, ... }: {
            networking.hostName = "hyperv";
            facter.reportPath = ./facter.json;
            
            my.hardware.network.single-interface = {
                enable = true;
                dhcp.enable = true;
            };
            
            # Auth
            my.auth.root = {
                mode = "permit_passwd";
                initialHashedPassword = "$6$DhwUDApjyhVCtu4H$mr8WIUeuNrxtoLeGjrMqTtp6jQeQIBuWvq/.qv9yKm3T/g5794hV.GhG78W2rctGDaibDAgS9X9I9FuPndGC01";
                authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBaNS9FByCEaDjPOUpeQZg58zM2wD+jEY6SkIbE1k3Zn ed25519 256-20251206 shaog@duck.com" ];
            };
        })
        
        # 4. 内联测试模块
        ({ config, pkgs, ... }: {
          system.build.vmTest = pkgs.testers.runNixOSTest {
            name = "hyperv-inline-test";
            node.specialArgs = { inputs = my-lib.inputs; };
            node.pkgs = nixpkgs.lib.mkForce pkgs;
            nodes.machine = { config, lib, ... }: {
                imports = [ 
                    my-lib.nixosModules.default 
                    commonConfig
                ];

                networking.hostName = "hyperv-test";
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