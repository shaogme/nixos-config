# 4G内存特化版本
{ config, pkgs, lib, ... }: {

  # --- ZRAM 配置 ---
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    # 4GB 内存下，默认的 50% (即 2GB ZRAM) 通常够用了。
    # 如果你跑很多容器，可以加到 75%。
    memoryPercent = 50; 
    priority = 100;
  };

  # --- 内核参数 (Sysctl) ---
  boot.kernel.sysctl = {
    # 4GB 内存下，swappiness 设为 60-100 之间即可。
    # 设为 80 是比较现代的 ZRAM 优化值（如 Fedora 的策略）。
    # 这意味着：只有当内存真的开始有点挤了，才开始温和地压缩内存。
    "vm.swappiness" = 80;

    # 接近默认值 (100)。
    # 4GB 内存通常不需要刻意保护文件缓存，
    # 让内核根据 LRU 算法自然淘汰即可。
    "vm.vfs_cache_pressure" = 100;

    # 遇到 OOM 没必要立刻重启，4GB 机器通常能扛过波动。
    "vm.panic_on_oom" = 0;
  };

  # --- 预防机制 ---
  boot.kernelParams = [ "lru_gen_enabled=1" ]; 
  # 4GB 内存下，systemd-oomd 实际上开始变得有用了（比如管理浏览器标签页），
  # 你可以选择开启它，或者继续禁用使用内核的 MGLRU。
  # 推荐继续禁用，因为 MGLRU 更底层、更智能。
  systemd.oomd.enable = false;

  # --- Nix 编译限制 ---
  # 4GB 可以稍微放开手脚了
  nix.settings = {
    cores = 0;    # 0 表示使用所有核心
    max-jobs = 2; # 允许同时进行 2 个构建任务
  };
}