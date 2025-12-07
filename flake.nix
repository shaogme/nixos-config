# file: flake.nix
{
  description = "My NixOS Flake Configuration";

  nixConfig = {
    extra-substituters = [ "https://nyx.chaotic.cx" "https://chaotic-nyx.cachix.org" ];
    extra-trusted-public-keys = [ "chaotic-nyx.cachix.org-1:HfnXSw4pj95iI/n17rIDy40agHj12WfF+Gqk6SonIT8=" ];
  };


  inputs = {
    # 默认源
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-25-11.url = "github:nixos/nixpkgs/nixos-25.11";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    nixos-facter-modules.url = "github:nix-community/nixos-facter-modules";
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
  };

  outputs = { self, ... }@inputs: {
    nixosConfigurations = import ./server/vps.nix { inherit inputs; };
  };
}