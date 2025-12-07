# nix run github:nix-community/disko -- --mode disko --flake .#my-machine
# nixos-install --flake .#my-machine
{
  description = "My NixOS Flake Configuration";

  # 1. Inputs: 定义软件源
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    nixos-facter-modules.url = "github:nix-community/nixos-facter-modules";
  };

  # 2. Outputs: 定义构建产物
  outputs = { self, nixpkgs, disko, nixos-facter-modules, ... }@inputs:
    let
      commonArgs = {
        inherit inputs;
        inherit disko;
        inherit nixos-facter-modules;
      };

      # 这个函数接收两个参数：
      # 1. system: 架构字符串 (如 "x86_64-linux" 或 "aarch64-linux")
      # 2. extraModules: 模块列表
      mkSystem = system: extraModules: nixpkgs.lib.nixosSystem {
        inherit system; # 使用传入的 system 参数
        specialArgs = commonArgs;
        modules = [
          # 基础模块
          ./disk/auto-resize.nix
        ] ++ extraModules;
      };
    in
    {
      nixosConfigurations = {
        
        # x86_64 机器
        tohu = mkSystem "x86_64-linux" [
          ./server/vps/hosts/tohu.nix
          ./disk/vps/Swap-2G.nix
        ];

        hyperv = mkSystem "x86_64-linux" [
          ./server/vps/hosts/hyperv.nix
          ./disk/vps/Swap-4G.nix
        ];
        
        # ARM 机器
        # raspi = mkSystem "aarch64-linux" [
        #   ./server/pi/hosts/raspi.nix
        #   ./disk/pi/sd-card.nix
        # ];

      };
    };
}