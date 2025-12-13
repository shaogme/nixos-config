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
          
          ./core/app/default.nix
          ./core/base/default.nix
          ./core/hardware/default.nix
        ];
      };
      kernel-xanmod = ./core/kernel/xanmod.nix;
    };
  };
}