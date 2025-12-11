{ allowReboot ? false }:
{ config, pkgs, lib, ... }:

{
  # 自动升级依赖于本地的 flake 副本
  system.copyFlakeToNixos.enable = lib.mkDefault true;

  # --- 自动更新配置 ---
  system.autoUpgrade = {
    enable = true;
    dates = "04:00"; # 每天凌晨 4 点执行
    
    # 指定 Flake URI
    flake = "path:/etc/nixos#${config.networking.hostName}";
    
    # 强制更新所有 input以获取新软件
    flags = [
      "--recreate-lock-file"
      "-L" # 打印构建日志
    ];
    
    # 更新后允许重启
    inherit allowReboot;
    # 随机延迟 10 分钟重启，避免由于定时任务导致的并发高峰
    randomizedDelaySec = "10min";
  };

  # --- 垃圾回收与存储优化 ---
  nix.gc = {
    automatic = true;
    dates = "weekly"; # 每周执行
    options = "--delete-older-than 30d"; # 删除 30 天前的旧版本
  };
}
