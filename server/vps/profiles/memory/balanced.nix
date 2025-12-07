# 小于2G内存特化版本
{ config, pkgs, lib, ... }: {

  # --- ZRAM 配置 ---
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    # 2GB 内存时，依然建议允许 ZRAM 使用较多内存
    # 设置为 75% - 100% 是安全的，因为这只是“上限”
    memoryPercent = 80;
    priority = 100;
  };

  # --- 内核参数 (Sysctl) ---
  boot.kernel.sysctl = {
    # 100 表示内核对待 匿名页(程序内存) 和 文件页(缓存) 的回收意愿是相等的。
    # 配合 ZRAM，这会让不活跃的程序内存被压缩，腾出空间给文件缓存。
    # 相比 1GB 方案的 150，这里稍微降低了激进程度。
    "vm.swappiness" = 120; 

    # 稍微保护文件缓存 (默认 100)。
    # 2GB 内存如果不保护缓存，系统会频繁读取硬盘，导致卡顿。
    # 设置 60-70 是个不错的平衡点。
    "vm.vfs_cache_pressure" = 65;

    # 脏页回写控制
    # 当内存中有 10MB 脏数据时就开始后台回写，避免脏数据积压太多瞬间卡死系统
    "vm.dirty_background_bytes" = "16777216"; # 16MB
    "vm.dirty_bytes" = "50331648";            # 48MB
  };

  # --- 预防机制 ---
  boot.kernelParams = [ "lru_gen_enabled=1" ]; # MGLRU 依然是必须的
  systemd.oomd.enable = false;

  # --- Nix 编译限制 ---
  # 2GB 内存编译大型软件依然危险，建议限制并发
  nix.settings = {
    cores = 2;     # 允许稍微多一点并发
    max-jobs = 1;  # 但 Job 数量依然保持克制
  };
}