# file: server/vps.nix
{ inputs }:

let
  inherit (inputs) nixpkgs disko nixos-facter-modules;

  # 定义部分 (机制)
  commonArgs = {
    inherit inputs;
    inherit disko;
    inherit nixos-facter-modules;
  };

  mkSystem = { system, diskDevice, extraModules, pkgSrc ? inputs.nixpkgs }:
    let
      pkgs = import pkgSrc {
        inherit system;
        config.allowUnfree = true;
      };
    in
    pkgSrc.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit inputs diskDevice disko nixos-facter-modules;
      };
      modules = [
        nixos-facter-modules.nixosModules.facter
        ./vps/profiles/performance/generic.nix
        {
          nixpkgs.pkgs = pkgs;
        }
      ] ++ extraModules;
    };

  tohuConfig = import ./vps/tohu.nix {
    inherit mkSystem;
    pkgSrc = inputs.nixpkgs-small;
  };

  hypervConfig = import ./vps/hyperv.nix {
    inherit mkSystem;
    pkgSrc = inputs.nixpkgs-small;
  };
in
{
  nixosConfigurations = {
    tohu = tohuConfig;
    hyperv = hypervConfig;
  };

  checks = {
    x86_64-linux = {
      tohu-test = tohuConfig.config.system.build.vmTest;
      hyperv-test = hypervConfig.config.system.build.vmTest;
    };
  };
}