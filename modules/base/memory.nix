{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.my.memory;
in {
  options.my.memory = {
    mode = mkOption {
      type = types.enum [ "aggressive" "balanced" "conservative" "none" ];
      default = "none";
      description = "Memory optimization mode: aggressive (<1G), balanced (<2G), conservative (>=4G), or none.";
    };
  };

  config = mkIf (cfg.mode != "none") {
    # --- Common Settings ---
    zramSwap.enable = true;
    zramSwap.algorithm = "zstd";
    zramSwap.priority = 100;

    boot.kernelParams = [ "lru_gen_enabled=1" ]; # MGLRU is beneficial for all low-memory scenarios
    systemd.oomd.enable = false;

    # --- Mode Specific Settings ---
    zramSwap.memoryPercent = mkIf (cfg.mode == "aggressive") 100;
    boot.kernel.sysctl = mkIf (cfg.mode == "aggressive") {
      "vm.swappiness" = 150;
      "vm.vfs_cache_pressure" = 50;
    };
    nix.settings = mkIf (cfg.mode == "aggressive") {
      cores = 1;
      max-jobs = 1;
    };

    zramSwap.memoryPercent = mkIf (cfg.mode == "balanced") 80;
    boot.kernel.sysctl = mkIf (cfg.mode == "balanced") {
      "vm.swappiness" = 120;
      "vm.vfs_cache_pressure" = 65;
      "vm.dirty_background_bytes" = "16777216"; # 16MB
      "vm.dirty_bytes" = "50331648";            # 48MB
    };
    nix.settings = mkIf (cfg.mode == "balanced") {
      cores = 2;
      max-jobs = 1;
    };

    zramSwap.memoryPercent = mkIf (cfg.mode == "conservative") 50;
    boot.kernel.sysctl = mkIf (cfg.mode == "conservative") {
      "vm.swappiness" = 80;
      "vm.vfs_cache_pressure" = 100;
      "vm.panic_on_oom" = 0;
    };
    nix.settings = mkIf (cfg.mode == "conservative") {
      cores = 0;    # Use all cores
      max-jobs = 2;
    };
  };
}
