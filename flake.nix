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

      # 接收一个属性集作为参数：
      # { system, diskDevice, extraModules }
      mkSystem = { system, diskDevice, extraModules }: nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = commonArgs // { inherit diskDevice; };
        modules = [
          # 基础模块
          ./disk/auto-resize.nix
        ] ++ extraModules;
      };
    in
    {
      nixosConfigurations = {
        
        # x86_64 机器
        tohu = mkSystem {
          system = "x86_64-linux";
          diskDevice = "/dev/sda";
          extraModules = [
            ./server/vps/hosts/tohu.nix
            ./disk/vps/Swap-2G.nix
          ];
        };

        hyperv = mkSystem {
          system = "x86_64-linux";
          diskDevice = "/dev/sda";
          extraModules = [
            ./server/vps/hosts/hyperv.nix
            ./disk/vps/Swap-4G.nix
          ];
        };
        
        # ARM 机器
        # raspi = mkSystem {
        #   system = "aarch64-linux";
        #   diskDevice = "/dev/sda";
        #   extraModules = [
        #     ./server/vps/hosts/raspi.nix
        #     ./disk/pi/sd-card.nix
        #   ];
        # };
      };
    };
}