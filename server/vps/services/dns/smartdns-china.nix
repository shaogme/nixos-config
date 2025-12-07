{ config, pkgs, ... }:

{
  # 1. 基础网络设置：禁用 Systemd-resolved，防止 53 端口冲突
  services.resolved.enable = false;
  
  # 2. 强制将本机 DNS 指向 SmartDNS (127.0.0.1)
  networking.nameservers = [ "127.0.0.1" ];
  
  # 防止 NetworkManager/DHCP 覆盖 DNS 设置
  networking.networkmanager.dns = "none"; 
  networking.dhcpcd.extraConfig = "nohook resolv.conf";

  # 3. SmartDNS 服务配置
  services.smartdns = {
    enable = true;
    
    # 国内环境建议开启 responding-nameservers 以便调试分流情况
    # 注意：新版 Nixpkgs 使用 settings 替代 extraConfig
    settings = {
      # ==========================================
      # 基础服务设置
      # ==========================================
      bind = "[::]:53";
      # 在 settings 中，同一个 key 只能出现一次，如果有多个值需要合并到列表中
      # 这里分开写只是为了对应原有的 extraConfig 结构，实际上 bind-tcp 是独立选项
      bind-tcp = "[::]:53";
      
      # 日志配置
      log-level = "warn";
      
      # 缓存配置：国内环境缓存可以适当减小，因为国内 IP 变动相对频繁
      cache-size = 32768;
      cache-file = "/var/lib/smartdns/smartdns.cache";
      cache-persist = true;

      # ==========================================
      # 性能与测速优化
      # ==========================================
      prefetch-domain = true;
      serve-expired = true;
      serve-expired-ttl = 86400;  # 1天
      
      # 测速模式：国内环境 ping 往往不可靠（很多服务器禁 ping），
      # 建议主要依赖 tcp:80 和 tcp:443
      speed-check-mode = "tcp:80,tcp:443,ping";
      
      # 响应模式：返回最快的 IP
      response-mode = "fastest-response";

      # ==========================================
      # 分组结构设计 (核心逻辑)
      # ==========================================
      # 逻辑：定义两组上游，一组叫 'china'，一组叫 'global'
      # 默认请求全部走 'global' (兜底防污染)，
      # 只有匹配到特定规则的域名才走 'china'。

      # --- 1. 国内上游组 (group china) ---
      # 使用腾讯 (DNSPod) 和 阿里 (AliDNS)
      # -group china: 标记为国内组
      # -exclude-default-group: 禁止它们回答未指定组的查询 (防止污染泄漏)
      server = [
        "119.29.29.29 -group china -exclude-default-group"
        "223.5.5.5    -group china -exclude-default-group"
        "180.76.76.76 -group china -exclude-default-group" # 百度 DNS
      ];

      # --- 2. 国外上游组 (group global) ---
      # 必须使用加密 DNS (DoT/DoH) 以穿透防火墙干扰
      # Cloudflare (DoT)
      # Google (DoT) - 8.8.8.8 在国内通常被阻断或严重丢包，
      # 建议作为备选，或者使用你的代理环境能访问的 DNS
      # Quad9 (DoT) - 在国内连接通常比 Google 稳
      # 以及一个默认兜底的 server-tls (为了容错)
      server-tls = [
        "1.1.1.1 -group global -exclude-default-group"
        "1.0.0.1 -group global -exclude-default-group"
        
        "8.8.4.4 -group global -exclude-default-group"

        "9.9.9.9 -group global -exclude-default-group"

        # 推荐做法：不设置默认 server，全部通过 nameserver 规则指定。
        # 但为了容错，我们添加一个纯净的 DoT 作为默认兜底（不加 group 标记）:
        "9.9.9.9"
      ];

      # ==========================================
      # 分流规则 (Split Horizon)
      # ==========================================
      
      # 1. 默认策略：所有域名默认走 global 组 (白名单模式，最安全，防污染)
      # 但为了速度，我们通常把 default 组指向 global，然后把国内域名指回 china
      # 注意：SmartDNS 如果没有匹配到 nameservers 规则，会向所有未加 -exclude 的 server 发送
      # 这里我们通过 explicit 规则来控制
      
      # 设置默认组为 global (假如你希望没匹配到的都当成国外域名处理)
      # 也可以不设置，让 SmartDNS 默认行为处理。
      
      # 2. 关键规则：.cn 域名必须走 china 组
      # 3. 常见国内大厂域名强制走 china 组 (简单示例)
      # 实际上这里应该引入一个大的 list 文件，见下文说明
      # 4. Apple 优化 (Apple 国内有 CDN，必须走国内解析)
      nameserver = [
        "/cn/china"

        "/baidu.com/china"
        "/qq.com/china"
        "/taobao.com/china"
        "/jd.com/china"
        "/aliyun.com/china"
        "/163.com/china"
        "/bilibili.com/china"

        "/apple.com/china"
        "/icloud.com/china"
        "/cdn-apple.com/china"
      ];

      # ==========================================
      # 其他优化
      # ==========================================
      # 屏蔽 HTTPS 记录 (Type 65)，国内部分老旧网络设备解析此类型可能卡顿
      # force-qtype-SO = "AAAA"; # 如需启用，请取消注释并确保格式正确
      
      # 如果你有 IPv6 且访问国外很慢，可以考虑屏蔽国外的 AAAA 记录
      # address = "/google.com/#6";
    };
  };

  # 确保持久化缓存目录权限
  systemd.services.smartdns.serviceConfig = {
    StateDirectory = "smartdns"; 
    User = "root";
  };
}