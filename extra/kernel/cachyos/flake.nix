{
  description = "CachyOS Kernel Module with BBRv3 Network Optimization";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    
    # CachyOS stable 使用 nyxpkgs-unstable 分支
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
    chaotic.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, chaotic, ... }: {
    nixosModules = {
      default = { pkgs, ... }: {
        imports = [
          chaotic.nixosModules.nyx-cache
          chaotic.nixosModules.nyx-overlay
          chaotic.nixosModules.nyx-registry
          ./default.nix
        ];

        # 在自动更新前先拉取 chaotic-nyx 缓存配置
        systemd.services.nixos-upgrade.serviceConfig.ExecStartPre = 
          "${pkgs.cachix}/bin/cachix use chaotic-nyx";

        # 安装 cachix 工具
        environment.systemPackages = [ pkgs.cachix ];
      };
    };
    
    # 暴露 overlay 供外部使用
    overlays.default = chaotic.overlays.default;
    
    # 提供便捷函数用于构建测试 pkgs
    lib.makeTestPkgs = system: import nixpkgs {
      inherit system;
      config.allowUnfree = true;
      overlays = [ chaotic.overlays.default ];
    };
  };
}
