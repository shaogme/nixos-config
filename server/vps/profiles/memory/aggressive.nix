# 小于1G内存特化版本
{ config, pkgs, ... }: {

# 1. 开启 ZRAM (作为高性能的一级 Swap)
  zramSwap = {
    enable = true;
    algorithm = "zstd";    # 压缩率高，适合小内存 VPS
    memoryPercent = 100;   # 激进策略：允许 ZRAM 占用较多内存。
                           # 注意：这并不意味着它立刻吃掉 1G，而是最大可压缩后的容量限制。
    priority = 100;        # 优先级设为 100 (高于默认的磁盘 Swap)
  };

  # 2. 添加物理 Swap 文件 (作为保命的二级 Swap)
  # 1GB 内存建议给 2GB-4GB 的 Swap 文件，防止 nixos-rebuild 爆内存
  swapDevices = [
    {
      device = "/var/lib/swapfile";
      size = 2048; # 2GB
      priority = 0; # 优先级较低，只有 ZRAM 满了才会用它
    }
  ];

  # 3. 关键内核参数优化 (针对 1GB 内存特调)
  boot.kernel.sysctl = {
    # 更加积极地使用 Swap (ZRAM)。
    # 默认 60，改为 100 或更高（最大 200 左右）让内核倾向于把匿名页压缩进 ZRAM，
    # 而不是丢弃文件缓存（会导致磁盘 IO 读写变慢）。
    "vm.swappiness" = 150; 
    
    # 保持一定的文件缓存，防止系统为了腾内存把必要的库文件丢弃导致卡顿
    "vm.vfs_cache_pressure" = 50;
    
    # 遇到 OOM 时，触发 Kernel Panic 自动重启（对于无人值守 VPS 很有用，防止死机失联）
    # "vm.panic_on_oom" = 1; # 可选，看你需求
    # "kernel.panic" = 10;
  };

  # 4. 强烈建议：开启 MGLRU
  # 在小内存下能极大减少“系统假死”的概率
  boot.kernelParams = [ "lru_gen_enabled=1" ];
  systemd.oomd.enable = false; # 关闭 systemd 的 OOMD，防止它误杀服务
  
  nix.settings = {
    cores = 1;     # 仅使用 1 个 CPU 核心
    max-jobs = 1;  # 仅使用 1 个 Job
  };
}
