{
  description = "My NixOS Flake Library";

  inputs = {
    # 基础依赖 (用于定义 module 系统)
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    
    # 外部模块依赖
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    
    nixos-facter-modules.url = "github:nix-community/nixos-facter-modules";
    
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
  };

  outputs = { self, nixpkgs, disko, nixos-facter-modules, chaotic, ... }@inputs: {
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
        
        # 将 inputs 注入到模块系统中，方便子模块使用
        _module.args.inputs = inputs;
      };
      
      # 2. 细分导出 - 内核优化模块（闭包包装以解决 inputs 在 imports 中的无限递归问题）
      kernel-cachyos = {
        imports = [
          chaotic.nixosModules.nyx-cache
          chaotic.nixosModules.nyx-overlay
          chaotic.nixosModules.nyx-registry
          ./modules/kernel/cachyos.nix
        ];
        _module.args.inputs = inputs;
      };
      kernel-cachyos-unstable = {
        imports = [
          chaotic.nixosModules.default
          ./modules/kernel/cachyos-unstable.nix
        ];
        _module.args.inputs = inputs;
      };
      kernel-xanmod = ./modules/kernel/xanmod.nix;
    };
  };
}