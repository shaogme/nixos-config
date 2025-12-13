{ lib, config, pkgs, ... }:
with lib;
let
  cfg = config.core.base.update;
in {
  options.core.base.update = {
    enable = mkEnableOption "System auto-update and garbage collection";
    
    flakeUri = mkOption {
      type = types.str;
      default = "github:ShaoG-R/nixos-config?dir=vps/${config.networking.hostName}";
      description = "Flake URI for auto-upgrade";
    };

    allowReboot = mkOption {
      type = types.bool;
      default = false;
      description = "Allow reboot after update";
    };
  };

  config = mkIf cfg.enable {
    # 安装 cachix 工具用于缓存管理
    environment.systemPackages = [ pkgs.cachix ];

    # --- 自动更新配置 ---
    system.autoUpgrade = {
      enable = true;
      dates = "04:00"; # 每天凌晨 4 点执行
      
      # 指定 Flake URI
      flake = cfg.flakeUri;
      
      flags = [
        "-L" # 打印构建日志
      ];
      
      # 更新后允许重启
      allowReboot = cfg.allowReboot;
      # 随机延迟 10 分钟重启，避免由于定时任务导致的并发高峰
      randomizedDelaySec = "10min";
    };

    # 在自动更新前先拉取 chaotic-nyx 缓存配置
    systemd.services.nixos-upgrade.serviceConfig.ExecStartPre = 
      "${pkgs.cachix}/bin/cachix use chaotic-nyx";

    # --- 垃圾回收与存储优化 ---
    nix.gc = {
      automatic = true;
      dates = "weekly"; # 每周执行
      options = "--delete-older-than 30d"; # 删除 30 天前的旧版本
    };
  };
}
