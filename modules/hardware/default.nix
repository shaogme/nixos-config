{ config, lib, pkgs, modulesPath, ... }:

let
  cfg = config.my.hardware;
in
{
  imports = [
    ./disk.nix
    ./network/single-interface.nix
  ];

  options.my.hardware = {
    type = lib.mkOption {
      type = lib.types.enum [ "physical" "vps" ];
      default = "physical";
      description = "Type of the hardware: physical or vps";
    };
  };

  config = lib.mkIf (cfg.type == "vps") (import "${modulesPath}/profiles/qemu-guest.nix" { inherit config lib pkgs; });
}
