{ config, pkgs, ... }:

{
    networking.firewall.allowedUDPPorts = [ 443 ];
    networking.firewall.allowedTCPPorts = [ 80 443 ];

    # ACME (Let's Encrypt) 自动证书配置
    # 需要先同意条款并设置邮箱
    security.acme = {
        acceptTerms = true;
        defaults.email = "shaog@duck.com";
    };

    # Nginx 全局配置
    services.nginx = {
        enable = true;

        # 推荐的安全和性能设置（NixOS 帮你维护最佳实践）
        recommendedGzipSettings = true;
        recommendedOptimisation = true;
        recommendedProxySettings = true; # 自动处理 X-Forwarded-For 等头
        recommendedTlsSettings = true;   # 禁用旧 SSL 协议等

        # 虚拟主机配置
        virtualHosts = {
            
            #  场景 A: 静态网站
            #   "static.example.com" = {
            #     forceSSL = true;
            #     enableACME = true;
            #     root = "/var/www/static";
            #   };

            #  场景 B: 反向代理到后端 (例如你的 Rust App 运行在 3000 端口)
            #   "api.example.com" = {
            #     forceSSL = true;
            #     enableACME = true;
            #     http3 = true;
            #     quic = true;
                
            #     locations."/" = {
            #       proxyPass = "http://127.0.0.1:3000";
                
            #       # 如果你的 Rust 应用涉及 WebSocket (如 tokio tungstenite)
            #       proxyWebsockets = true; 
                
            #       # 额外的 header 设置（如果 recommendedProxySettings 不够用）
            #       extraConfig = ''
            #         client_max_body_size 10M;
            #       '';
            #     };
            #   };
            
            # 场景 C: 默认拒绝直接 IP 访问 (防止扫描)
            "_" = {
                default = true;
                rejectSSL = true;
                locations."/" = {
                    return = "444";
                };
            };
        };
    };
}