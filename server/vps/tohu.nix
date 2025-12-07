# file: server/vps/tohu.nix
{ mkSystem, pkgSrc }:

mkSystem {
  inherit pkgSrc;
  system = "x86_64-linux";
  diskDevice = "/dev/sda";
  extraModules = [
    ./platform/generic.nix
    ./disk/specific/Swap-2G.nix
    (import ./auth/default.nix {
      initialHashedPassword = "$6$DhwUDApjyhVCtu4H$mr8WIUeuNrxtoLeGjrMqTtp6jQeQIBuWvq/.qv9yKm3T/g5794hV.GhG78W2rctGDaibDAgS9X9I9FuPndGC01";
      authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBaNS9FByCEaDjPOUpeQZg58zM2wD+jEY6SkIbE1k3Zn ed25519 256-20251206 shaog@duck.com" ];
    })
    (import ./network/single-interface/static-ipv4.nix {
        address = "66.235.104.29";
        prefixLength = 24;
        gateway = "66.235.104.1";
    })
    {
      networking.hostName = "tohu";
      facter.reportPath = ./facter/tohu.json;
      system.stateVersion = "25.11";
    }
  ];
}