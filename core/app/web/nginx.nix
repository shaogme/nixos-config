{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.core.app.web.nginx;
in {
  options.core.app.web.nginx = {
    enable = mkEnableOption "Nginx Web Server";
    email = mkOption {
      type = types.str;
      default = "shaog@duck.com";
      description = "Email for ACME registration";
    };
  };

  config = mkIf cfg.enable {
    networking.firewall.allowedUDPPorts = [ 443 ];
    networking.firewall.allowedTCPPorts = [ 80 443 ];

    # ACME (Let's Encrypt) 自动证书配置
    security.acme = {
      acceptTerms = true;
      defaults.email = cfg.email;
    };

    # Nginx 全局配置
    services.nginx = {
      enable = true;

      # 推荐的安全和性能设置
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true; 
      recommendedTlsSettings = true;   

      # 虚拟主机配置
      virtualHosts = {
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
  };
}