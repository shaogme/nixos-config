{ lib, config, pkgs, ... }:
with lib;
let
  cfg = config.core.hardware.disk;
  # 处理 swapSize 为 null 的情况，将其视为 0
  safeSwapSize = if cfg.swapSize != null then cfg.swapSize else 0;
  imageSize = "${toString (safeSwapSize + 3072)}M";
in {
  imports = [ ];

  options.core.hardware.disk = {
    enable = mkEnableOption "Disk Configuration";
    
    device = mkOption {
      type = types.str;
      default = "/dev/sda";
      description = "The disk device to use (e.g. /dev/sda)";
    };
    
    swapSize = mkOption {
      type = types.nullOr types.int;
      default = 0;
      description = "Swap size in MB. Set to 0 or null to disable swap.";
    };
  };

  config = mkIf cfg.enable {
    # --- Bootloader Configuration ---
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

    # --- Disk Configuration ---
    disko.devices.disk.main = {
      # 这里指定生成的 raw 文件初始大小。
      inherit imageSize;

      device = cfg.device;
      content = {
        type = "gpt";
        # 使用 // 运算符和 lib.optionalAttrs 来动态构建分区集合
        partitions = {
          # 为了在 BIOS+GPT 上启动
          boot = {
            priority = 0;
            size = "1M";
            type = "EF02"; 
          };
          # 1. ESP 分区
          ESP = {
            priority = 1;
            size = "32M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot/efi";
              mountOptions = [ "defaults" ];
            };
          };
        } 
        # 仅在 safeSwapSize 大于 0 时添加 Swap 分区
        // lib.optionalAttrs (safeSwapSize > 0) {
          swap = {
            priority = 2;
            size = "${toString safeSwapSize}M";
            content = {
              type = "swap";
              discardPolicy = "both";
              resumeDevice = true;
            };
          };
        } 
        # 继续添加剩余的 Root 分区
        // {
          # 3. Root 分区 (直接使用 Btrfs，移除 LUKS 加密层)
          root = {
            priority = 3;
            size = "100%";
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "@" = {
                  mountpoint = "/";
                  mountOptions = [ "compress-force=zstd:3" "noatime" "space_cache=v2" ];
                };
                "@home" = {
                  mountpoint = "/home";
                  mountOptions = [ "compress-force=zstd:3" "noatime" "space_cache=v2" ];
                };
                "@nix" = {
                  mountpoint = "/nix";
                  mountOptions = [ "compress-force=zstd:3" "noatime" "space_cache=v2" ];
                };
                "@log" = {
                  mountpoint = "/var/log";
                  mountOptions = [ "compress-force=zstd:3" "noatime" "space_cache=v2" ];
                };
              };
            };
          };
        };
      };
    };

    fileSystems."/var/log".neededForBoot = true;

    # 启动时自动修复 GPT 分区表并扩容最后一个分区
    boot.growPartition = true;

    # 针对 Btrfs 根分区的自动扩容配置
    fileSystems."/".autoResize = true;

    # 确保必要的工具在系统路径中 (cloud-utils 包含 growpart)
    environment.systemPackages = [ pkgs.cloud-utils ];
  };
}
