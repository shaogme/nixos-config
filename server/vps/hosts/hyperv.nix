# 编辑此配置文件以定义系统安装内容
# 帮助文档：man configuration.nix 或 nixos-help
{ config, lib, pkgs, nixos-facter-modules, ... }:

{
  imports =
    [
      ../platform/generic.nix
      (import ../auth/permit_passwd.nix {
        # 注意：这是 "initial" 密码，仅在第一次部署时生效。
        # 以后如果你用 passwd 命令改了密码，这个配置不会覆盖它（这是为了安全性）。
        # 使用 nix run nixpkgs#mkpasswd -- -m sha-512 生成密码
        initialHashedPassword = "$6$DhwUDApjyhVCtu4H$mr8WIUeuNrxtoLeGjrMqTtp6jQeQIBuWvq/.qv9yKm3T/g5794hV.GhG78W2rctGDaibDAgS9X9I9FuPndGC01";
        
        authorizedKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBaNS9FByCEaDjPOUpeQZg58zM2wD+jEY6SkIbE1k3Zn ed25519 256-20251206 shaog@duck.com" ];
      })
      nixos-facter-modules.nixosModules.facter
    ];

  facter.reportPath = ./facter/hyperv.json;

  # --- 系统状态版本 ---
  # 定义首次安装时的 NixOS 版本，用于保持数据兼容性。
  # 除非你清楚后果，否则不要更改此值 (这不会影响系统升级)。
  system.stateVersion = "25.11"; 
}