# file: server/vps/hyperv.nix
{ mkSystem, pkgSrc }:

let
  # 1. 提取核心业务逻辑 (软件/服务)
  serviceModules = [
    ./platform/generic.nix
    ./profiles/memory/conservative.nix
    ./software/container/podman.nix
    (import ./profiles/update/auto-upgrade.nix { allowReboot = true; })
    
    # 内联测试模块
    ({ pkgs, lib, inputs, ... }: {
      system.build.vmTest = pkgs.testers.runNixOSTest {
        name = "hyperv-inline-test";
        
        nodes.machine = { config, ... }: {
          imports = serviceModules ++ [
            ./kernel/xanmod.nix
          ];

          networking.hostName = "hyperv-test";
          networking.useDHCP = true;
          networking.firewall.enable = false;
          
          _module.args.inputs = inputs;
        };

        testScript = ''
          start_all()
          machine.wait_for_unit("multi-user.target")
          machine.wait_for_unit("podman.socket")
        '';
      };
    })
  ];

  # 2. 硬件/环境相关配置
  hardwareModules = [
    ./kernel/xanmod.nix
    (import ./disk/common.nix { swapSize = 4096; })
    (import ./network/single-interface/dhcp.nix)
  ];

in
mkSystem {
  inherit pkgSrc;
  system = "x86_64-linux";
  diskDevice = "/dev/sda";
  
  extraModules = serviceModules ++ hardwareModules ++ [
    (import ./auth/permit_passwd.nix {
      initialHashedPassword = "$6$DhwUDApjyhVCtu4H$mr8WIUeuNrxtoLeGjrMqTtp6jQeQIBuWvq/.qv9yKm3T/g5794hV.GhG78W2rctGDaibDAgS9X9I9FuPndGC01";
      authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBaNS9FByCEaDjPOUpeQZg58zM2wD+jEY6SkIbE1k3Zn ed25519 256-20251206 shaog@duck.com" ];
    })
    ({ inputs, ... }: {
      networking.hostName = "hyperv";
      facter.reportPath = ./facter/hyperv.json;
      system.stateVersion = "25.11"; 
      environment.etc."nixos".source = inputs.self;
    })
  ];
}