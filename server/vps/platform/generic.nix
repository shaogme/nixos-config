# 编辑此配置文件以定义系统安装内容
# 帮助文档：man configuration.nix 或 nixos-help
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    # 引入 QEMU Guest 支持 (包含 virtio 驱动，对 VPS 很重要)
    "${modulesPath}/profiles/qemu-guest.nix"
  ];

  # 启用实验性功能 (Flakes 和 nix-command)
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  
  # 使用 XanMod 稳定版内核
  boot.kernelPackages = pkgs.linuxKernel.packages.linux_xanmod_stable;
  
  # 内核参数 (启用串口终端，通常用于 VPS 调试)
  boot.kernelParams = [ "console=ttyS0,115200n8" "console=tty0" ];
  
  # --- SSH 服务 ---
  services.openssh.enable = true;
  
  # --- 自动更新配置 ---
  system.autoUpgrade = {
    enable = true;
    dates = "04:00"; # 每天凌晨 4 点执行
    
    # 指定 Flake URI
    flake = "file:///etc/nixos#${config.networking.hostName}";
    
    # 强制更新 nixpkgs input 以获取新软件版本
    flags = [
      "--update-input"
      "nixpkgs"
      "-L" # 打印构建日志
    ];
    
    # 更新后允许重启 (VPS 建议设为 false 防止服务中断)
    allowReboot = true;
    # 随机延迟 10 分钟重启，避免由于定时任务导致的并发高峰
    randomizedDelaySec = "10min";
  };

  # --- 垃圾回收与存储优化 ---
  nix.gc = {
    automatic = true;
    dates = "weekly"; # 每周执行
    options = "--delete-older-than 30d"; # 删除 30 天前的旧版本
  };

  # 每次构建时自动去重存储池以节省空间
  nix.settings.auto-optimise-store = true;

  # --- Podman 容器配置 ---
  virtualisation.podman = {
    enable = true;
    # Docker 兼容模式 (创建 docker.sock 别名，适配 docker-compose 等工具)
    dockerCompat = true;
    # 启用容器间 DNS 解析 (支持容器名互访)
    defaultNetwork.settings.dns_enabled = true;
  };

  # 安装系统级常用工具
  environment.systemPackages = with pkgs; [
    podman-compose
    git        
  ];

  # --- 通用系统设置 ---

  # 设置时区
  time.timeZone = "Asia/Shanghai";

  # 国际化设置：默认使用中文
  i18n.defaultLocale = "zh_CN.UTF-8";
  
  # 显式添加支持的 Locale，防止部分程序报错
  i18n.supportedLocales = [ "zh_CN.UTF-8/UTF-8" "en_US.UTF-8/UTF-8" ];

  # 控制台字体设置
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  # fonts.packages = with pkgs; [
  #   maple-mono.NF-CN # 对应字体名: Maple Mono NF CN
  # ];

  # fonts.fontconfig = {
  #   enable = true;
  #   defaultFonts = {
  #     # 指定你的终端和代码编辑器主要使用的字体
  #     monospace = [ "Maple Mono NF CN" ];
  #     # 由于没有安装其他 UI 字体，这里也强制回退到 Maple Mono
  #     sansSerif = [ "Maple Mono NF CN" ];
  #     serif = [ "Maple Mono NF CN" ];
  #   };
  # };

  # --- 图形界面 (X11) ---
  services.xserver.enable = false; # VPS 不需要图形界面

  # 键盘布局配置 (已注释)
  # services.xserver.xkb.layout = "us";
  # services.xserver.xkb.options = "eurosign:e,caps:escape";

  # --- 其他服务 (已注释) ---

  # --- 用户账户 ---
  # 记得使用 `passwd` 修改密码
  # users.users.alice = {
  #   isNormalUser = true;
  #   extraGroups = [ "wheel" ]; # 允许使用 sudo
  #   packages = with pkgs; [
  #     tree
  #   ];
  # };

  # Firefox 浏览器
  # programs.firefox.enable = true;

  # 防火墙设置
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # networking.firewall.enable = false;
}