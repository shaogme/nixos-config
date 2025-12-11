# file: server/vps/tohu.nix
{ mkSystem, pkgSrc }:

let
  # 1. 提取核心业务逻辑 (软件/服务)
  # 这些模块在物理机和虚拟机里都能跑
  serviceModules = [
    ./platform/generic.nix
    ./services/dns/smartdns-oversea.nix
    ./services/web/nginx.nix
    ./profiles/memory/aggressive.nix
    ./software/container/podman.nix
    (import ./software/web/alist.nix {
      enable = true;
      domain = "alist.tohu.shaog.uk";
    })
    (import ./software/proxy/x-ui-yg.nix {
      enable = true;
      domain = "x-ui.tohu.shaog.uk";
    })
    (import ./profiles/update/auto-upgrade.nix { allowReboot = true; })
    
    # 我们定义一个内联模块来包含测试逻辑
    ({ pkgs, lib, inputs, ... }: {
      # 挂载到 system.build 命名空间下，这样不会影响系统本身，但能被外部读取
      system.build.vmTest = pkgs.testers.runNixOSTest {
        name = "tohu-inline-test";
        
        nodes.machine = { config, ... }: {
          # 2. 测试机只导入 serviceModules
          imports = serviceModules ++ [
            ./kernel/cachyos-unstable.nix
          ];

          # 3. 模拟环境适配 (Mock)
          # 因为没有导入硬件配置，我们需要补充一些基础设置
          networking.hostName = "tohu-test";
          networking.useDHCP = true; 
          networking.firewall.enable = false;
          
          # 模拟域名解析到本地
          networking.hosts = {
            "127.0.0.1" = [ "alist.tohu.shaog.uk" "x-ui.tohu.shaog.uk" ];
          };
          
          # 补充 inputs (因为子模块可能依赖它)
          _module.args.inputs = inputs;
        };

        testScript = ''
          start_all()
          machine.wait_for_unit("multi-user.target")
          
          # 验证服务
          machine.wait_for_unit("nginx.service")
          machine.wait_for_unit("podman.service")
          
          # 验证业务逻辑
          assert "200" in machine.succeed("curl -I http://alist.tohu.shaog.uk")
        '';
      };
    })
  ];

  # 4. 提取硬件相关配置 (物理机专用)
  hardwareModules = [
    ./kernel/cachyos-unstable.nix # 虚拟机通常用默认内核测试即可，除非你要测内核特性
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
  
  # 5. 物理机 = 服务模块 + 硬件模块 + 身份验证 + 杂项
  extraModules = serviceModules ++ hardwareModules ++ [
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