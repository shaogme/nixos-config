{ mkSystem, pkgSrc }:

let
  baseModules = [
    ./platform/generic.nix
    ./services/dns/smartdns-oversea.nix
    ./services/web/nginx.nix
    ./profiles/memory/aggressive.nix
    ./software/container/podman.nix
  ];

  appModules = [
    (import ./software/web/alist.nix {
      enable = true;
      domain = "alist.tohu.shaog.uk";
    })
    (import ./software/proxy/x-ui-yg.nix {
      enable = true;
      domain = "x-ui.tohu.shaog.uk";
    })
    (import ./profiles/update/auto-upgrade.nix { allowReboot = true; })
  ];

  # 内联测试模块
  testModule = { pkgs, lib, inputs, ... }: {
    system.build.vmTest = pkgs.testers.runNixOSTest {
      name = "tohu-inline-test";
      
      # 1. 确保参数中有 lib 和 inputs
      nodes.machine = { config, lib, inputs, ... }: 
      let
        # 2. 手动构建一个带有 CachyOS Overlay 的 pkgs 实例
        # 必须使用 inputs.nixpkgs 重新实例化，因为宿主 pkgs 是锁定的
        pkgsWithChaotic = import inputs.nixpkgs {
          inherit (pkgs) system;
          config.allowUnfree = true;
          overlays = [ inputs.chaotic.overlays.default ];
        };
      in {
        # 3. 导入模块，并显式传入我们构建好的 pkgsWithChaotic
        # 这样 cachyos-unstable.nix 就能找到 linuxPackages_cachyos 了
        imports = serviceModules ++ [
          (import ./kernel/cachyos-unstable.nix { 
            pkgs = pkgsWithChaotic; 
            inherit inputs; 
          })
        ];

        # 4. 强制测试虚拟机使用这个新的 pkgs 实例
        # 解决 "is not of type Nixpkgs package set" 报错
        nixpkgs.pkgs = lib.mkForce pkgsWithChaotic;

        # 5. 强制清空 overlays 配置
        # 因为 pkgsWithChaotic 已经包含了 overlay，不需要再通过模块系统添加
        # 这样可以解决 "overlays defined multiple times" 的冲突报错
        nixpkgs.overlays = lib.mkForce [];

        _module.args.inputs = inputs;
      };

      testScript = ''
        start_all()
        machine.wait_for_unit("multi-user.target")
        machine.wait_for_unit("nginx.service")
        machine.wait_for_unit("podman.socket")
      '';
    };
  };

  hardwareModules = [
    ./kernel/cachyos-unstable.nix
    (import ./disk/common.nix { swapSize = 2048; })
    (import ./network/single-interface/static-ipv4.nix {
        address = "66.235.104.29";
        prefixLength = 24;
        gateway = "66.235.104.1";
    })
  ];

in
mkSystem {
  inherit pkgSrc;
  system = "x86_64-linux";
  diskDevice = "/dev/sda";
  
  extraModules = baseModules ++ appModules ++ hardwareModules ++ [
    testModule
    (import ./auth/default.nix {
      initialHashedPassword = "$6$DhwUDApjyhVCtu4H$mr8WIUeuNrxtoLeGjrMqTtp6jQeQIBuWvq/.qv9yKm3T/g5794hV.GhG78W2rctGDaibDAgS9X9I9FuPndGC01";
      authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBaNS9FByCEaDjPOUpeQZg58zM2wD+jEY6SkIbE1k3Zn ed25519 256-20251206 shaog@duck.com" ];
    })
    ({ inputs, ... }: {
      networking.hostName = "tohu";
      facter.reportPath = ./facter/tohu.json;
      system.stateVersion = "25.11";
      environment.etc."nixos".source = inputs.self;
    })
  ];
}