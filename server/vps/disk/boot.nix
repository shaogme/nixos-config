{ config, pkgs, ... }:

{
  # 禁用 systemd-boot
  boot.loader.systemd-boot.enable = false;
  
  # 指定 EFI 挂载点 (必须与 Disko 配置一致)
  boot.loader.efi.efiSysMountPoint = "/boot/efi";

  # GRUB 配置
  boot.loader.grub = {
    enable = true;
    device = "nodev";
    efiSupport = true;
    
    # 作用：将引导文件同时也复制到默认位置，防止主板“失忆”找不到启动项
    efiInstallAsRemovable = true;
  };
  
  boot.supportedFilesystems = [ "btrfs" ];
}