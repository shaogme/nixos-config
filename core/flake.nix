{
  description = "Core Flake Library";

  inputs = {
    # 基础依赖 (用于定义 module 系统)
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    
    # 外部模块依赖
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, disko, ... }@inputs: {
    # 1. 导出所有模块为一个聚合入口
    nixosModules = {
      default = { config, pkgs, lib, ... }: {
        imports = [
          disko.nixosModules.disko
          
          ./app/default.nix
          ./base/default.nix
          ./hardware/default.nix
        ];
      };
      kernel-xanmod = ./kernel/xanmod.nix;
    };
  };
}