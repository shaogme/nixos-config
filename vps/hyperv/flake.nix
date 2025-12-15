{
  description = "hyperv Configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable-small";
    lib-core.url = "path:../../core";
    lib-core.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, lib-core, ... }: 
  let
    commonConfig = { config, pkgs, ... }: {
        system.stateVersion = "25.11"; 
        core.base.enable = true;
        
        # Hardware
        core.hardware.type = "vps";
        core.hardware.disk = {
            enable = true;
            swapSize = 4096;
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
    };
  in
  {
    nixosConfigurations.hyperv = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inputs = lib-core.inputs; };
      modules = [
        # 1. 引入我们的模块库
        lib-core.nixosModules.default
        lib-core.nixosModules.kernel-xanmod
        
        # 2. 通用配置
        commonConfig
        
        # 3. 硬件/Host特有配置 (Production)
        ({ config, pkgs, modulesPath, ... }: {
            networking.hostName = "hyperv";
            facter.reportPath = ./facter.json;
            
            core.hardware.network.single-interface = {
                enable = true;
                dhcp.enable = true;
            };
            
            # Auth
            core.auth.root = {
                mode = "permit_passwd";
                initialHashedPassword = "$6$DhwUDApjyhVCtu4H$mr8WIUeuNrxtoLeGjrMqTtp6jQeQIBuWvq/.qv9yKm3T/g5794hV.GhG78W2rctGDaibDAgS9X9I9FuPndGC01";
                authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBaNS9FByCEaDjPOUpeQZg58zM2wD+jEY6SkIbE1k3Zn ed25519 256-20251206 shaog@duck.com" ];
            };
        })
        
        # 4. 内联测试模块 (XanMod 不需要 chaotic overlay)
        # 使用 testers.nixosTest 而非 runtesters.nixosTest，因为后者会将 nixpkgs.* 设为只读
        ({ config, pkgs, ... }: 
        let
          testPkgs = import lib-core.inputs.nixpkgs {
            system = "x86_64-linux";
            config.allowUnfree = true;
          };
        in {
          system.build.vmTest = pkgs.testers.nixosTest {
            name = "hyperv-inline-test";
            
            nodes.machine = { config, lib, ... }: {
                imports = [ 
                    lib-core.nixosModules.default 
                    lib-core.nixosModules.kernel-xanmod
                    commonConfig
                ];
                
                # testers.nixosTest 允许设置 nixpkgs.pkgs
                nixpkgs.pkgs = testPkgs;
                
                # testers.nixosTest 不支持 specialArgs，需要在这里注入 inputs
                _module.args.inputs = lib-core.inputs;
                
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