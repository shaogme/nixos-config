{
  description = "My NixOS Flake Library";

  inputs = {
    # 基础依赖 (用于定义 module 系统)
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    
    # 外部模块依赖
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    
    nixos-facter-modules.url = "github:nix-community/nixos-facter-modules";
  };

  outputs = { self, nixpkgs, disko, nixos-facter-modules, ... }@inputs: {
    # 1. 导出所有模块为一个聚合入口
    nixosModules = {
      default = { config, pkgs, lib, ... }: {
        imports = [
          nixos-facter-modules.nixosModules.facter
          disko.nixosModules.disko
          
          ./modules/app/default.nix
          ./modules/base/default.nix
          ./modules/hardware/default.nix
        ];
      };
      
      # 2. 细分导出 - 内核优化模块（通过独立 Git 仓库管理）
      # 使用 builtins.getFlake 引用外部仓库，实现依赖隔离
      # chaotic 依赖完全隔离在 nixos-config-extra 仓库中
      kernel-cachyos = { ... }: {
        imports = [
          (builtins.getFlake "github:ShaoG-R/nixos-config-extra?dir=kernel/cachyos").nixosModules.default
        ];
      };
      kernel-cachyos-unstable = { ... }: {
        imports = [
          (builtins.getFlake "github:ShaoG-R/nixos-config-extra?dir=kernel/cachyos-unstable").nixosModules.default
        ];
      };
      kernel-xanmod = ./modules/kernel/xanmod.nix;
    };
  };
}