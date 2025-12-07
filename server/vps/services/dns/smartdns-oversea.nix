{ config, pkgs, ... }:

{
  # 禁用 systemd-resolved 的 53 端口监听，防止冲突
  services.resolved.enable = false;

  # 防止 NetworkManager/DHCP 覆盖 DNS 设置
  networking.networkmanager.dns = "none"; 

  # 禁止 dhcpcd（DHCP 客户端）自动修改 /etc/resolv.conf 文件。
  networking.dhcpcd.extraConfig = "nohook resolv.conf";

  # 本地 DNS 解析器地址
  networking.nameservers = [ "127.0.0.1" ];

  # SmartDNS 服务配置
  services.smartdns = {
    enable = true;
    
    # 针对高性能场景的详细配置
    # 注意：新版 Nixpkgs 使用 settings 替代 extraConfig
    settings = {
      # ==========================================
      # 基础服务设置
      # ==========================================
      # 监听本地 53 端口
      bind = "[::]:53";

      # 日志级别 (平时 warn/error 即可，排错用 debug)
      log-level = "warn";
      
      # 缓存大小 (条目数)，海外机器内存通常足够，设大一点
      cache-size = 65536;
      
      # 开启持久化缓存 (重启后不丢失缓存热度)
      # 需要配合 systemd StateDirectory 权限 (见下方 systemd 配置)
      cache-file = "/var/lib/smartdns/smartdns.cache";
      cache-persist = true;

      # ==========================================
      # 性能与测速优化 (核心)
      # ==========================================
      # 开启域名预取：在缓存过期前自动后台刷新，实现"零延迟"体验
      prefetch-domain = true;
      
      # 缓存过期服务：允许在预取失败时短暂返回过期记录，提升可用性
      serve-expired = true;
      serve-expired-ttl = 259200;   # 过期后 3 天内仍可返回
      serve-expired-reply-ttl = 30; # 返回过期记录给客户端时，TTL 设为 30 秒，促使客户端尽快刷新

      # 测速模式：SmartDNS 会向解析到的所有 IP 发送包，选最快的返回给你
      # 海外环境 443 端口通畅，ping + tcp:80 + tcp:443 混合测速最准
      speed-check-mode = "ping,tcp:80,tcp:443";

      # 响应模式：fastest-response (返回最快的 IP)
      response-mode = "fastest-response";

      # 双栈 IP 优选：如果你的 VPS 有 IPv6，这会测试 v4 和 v6 哪个快用哪个
      dualstack-ip-selection = true;
      
      # ==========================================
      # 上游 DNS 配置 (纯净环境推荐全 DoT/DoH)
      # ==========================================
      # 这里的逻辑是：并发查询所有上游，谁先回来且测速最快就用谁

      # 1. Cloudflare DNS (全球最快之一，支持 DoT)
      # -group global 可以省略，因为我们不需要分流，所有请求都走默认
      # 2. Google DNS (由于 ECS 支持好，能精准解析到离你 VPS 最近的 CDN)
      # 3. Quad9 (主打安全和恶意域名拦截，推荐作为备选)
      # 注意：在纯净网络环境下，不建议配置太多上游，
      # 2-3 家顶级服务商即可，多了反而增加系统开销。
      server-tls = [
        "1.1.1.1"
        "1.0.0.1"
        "2606:4700:4700::1111"
        "2606:4700:4700::1001"
        
        "8.8.8.8"
        "8.8.4.4"
        "2001:4860:4860::8888"
        "2001:4860:4860::8844"

        "9.9.9.9"
        "149.112.112.112"
      ];
    };
  };

  # 3. 确保持久化缓存目录的权限
  systemd.services.smartdns.serviceConfig = {
    # 确保 SmartDNS 进程可以写入缓存文件
    StateDirectory = "smartdns"; 
    User = "root"; # 或者 smartdns 专用用户，但在 NixOS module 默认通常是 root 运行，视具体版本而定
  };
}