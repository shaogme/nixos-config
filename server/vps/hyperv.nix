# file: server/vps/hyperv.nix
{ mkSystem, pkgSrc }:

mkSystem {
  inherit pkgSrc;
  system = "x86_64-linux";
  diskDevice = "/dev/sda";
  extraModules = [
    ./platform/generic.nix
    ./kernel/xanmod.nix
    ./profiles/memory/conservative.nix
    ./software/container/podman.nix
    (import ./profiles/update/auto-upgrade.nix { allowReboot = true; })
    (import ./disk/common.nix { swapSize = 4096; })
    (import ./auth/permit_passwd.nix {
      initialHashedPassword = "$6$DhwUDApjyhVCtu4H$mr8WIUeuNrxtoLeGjrMqTtp6jQeQIBuWvq/.qv9yKm3T/g5794hV.GhG78W2rctGDaibDAgS9X9I9FuPndGC01";
      authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBaNS9FByCEaDjPOUpeQZg58zM2wD+jEY6SkIbE1k3Zn ed25519 256-20251206 shaog@duck.com" ];
    })
    (import ./network/single-interface/dhcp.nix)
    {
      networking.hostName = "hyperv";
      facter.reportPath = ./facter/hyperv.json;
      system.stateVersion = "25.11"; 
      # 启用 copyFlakeToNixos 模块，用于初始化 /etc/nixos
      system.copyFlakeToNixos.enable = true;
    }
  ];
}