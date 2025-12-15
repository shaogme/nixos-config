{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.core.app.web.nginx;
  
  # 定义公共的 ACME Webroot 目录
  # Lego 客户端写入此目录，Nginx 从此目录读取
  acmeWebRoot = "/var/lib/acme/acme-challenge";

  # 定义站点配置的子模块结构
  siteSubmodule = types.submodule {
    options = {
      # Nginx 核心配置
      locations = mkOption {
        type = types.attrs;
        default = {};
        description = "Nginx location configurations";
      };
      
      extraConfig = mkOption {
        type = types.lines;
        default = "";
        description = "Extra Nginx configuration for the server block";
      };

      enableForceSSL = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to force SSL redirection";
      };

      # 新增：HTTP3 和 QUIC 支持
      http3 = mkOption {
        type = types.bool;
        default = false;
        description = "Enable HTTP3 for this site";
      };

      quic = mkOption {
        type = types.bool;
        default = false;
        description = "Enable QUIC listener for this site";
      };

      # ACME 高级配置 (Lego)
      acmePostRun = mkOption {
        type = types.lines;
        default = "";
        description = "Shell commands to run after certificate renewal (e.g. copying certs)";
      };
    };
  };

in {
  options.core.app.web.nginx = {
    enable = mkEnableOption "Nginx Web Server with Standalone ACME";
    
    email = mkOption {
      type = types.str;
      default = "shaog@duck.com";
      description = "Email for ACME registration";
    };

    # 使用自定义的 sites 选项替代直接操作 virtualHosts
    # 这允许我们在模块内部控制 ACME 和 SSL 路径的绑定逻辑
    sites = mkOption {
      type = types.attrsOf siteSubmodule;
      default = {};
      description = "Sites to host. Implicitly configures standalone ACME and Nginx.";
    };
  };

  config = mkIf cfg.enable {
    # 开放 HTTP/HTTPS 端口
    networking.firewall.allowedTCPPorts = [ 80 443 ];
    # 开放 QUIC 需要的 UDP 端口
    networking.firewall.allowedUDPPorts = [ 443 ];

    # 1. 确保 Webroot 目录存在且权限正确
    # acme 用户需要写，nginx 用户需要读
    systemd.tmpfiles.rules = [
      "d ${acmeWebRoot} 0755 acme nginx -"
    ];

    # 2. 自动生成 ACME 配置 (独立服务模式)
    security.acme = {
      acceptTerms = true;
      defaults = {
        email = cfg.email;
        group = "nginx"; # 确保证书文件对 Nginx 可读
      };

      # 遍历 sites 生成对应的证书配置
      certs = mapAttrs (domain: siteCfg: {
        webroot = acmeWebRoot; # 强制使用 HTTP-01 webroot 模式
        postRun = siteCfg.acmePostRun; # 注入用户定义的钩子
        reloadServices = [ "nginx" ];
      }) cfg.sites;
    };

    # 3. 自动生成 Nginx 配置
    services.nginx = {
      enable = true;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true; 
      recommendedTlsSettings = true;   

      virtualHosts = 
        let
          # 生成用户定义的站点
          userSites = mapAttrs (domain: siteCfg: {
            # 核心逻辑：强制指向独立 ACME 生成的证书路径
            # 用户无法覆盖此设置，确保了“隐式使用独立 ACME”
            sslCertificate = "${config.security.acme.certs.${domain}.directory}/fullchain.pem";
            sslCertificateKey = "${config.security.acme.certs.${domain}.directory}/key.pem";
            
            forceSSL = siteCfg.enableForceSSL;
            http3 = siteCfg.http3;
            quic = siteCfg.quic;
            
            # 注入 locations
            locations = siteCfg.locations // {
              # 强制注入 ACME 验证路径，优先级设为最高
              "/.well-known/acme-challenge" = {
                root = acmeWebRoot;
                priority = 100; 
              };
            };

            extraConfig = siteCfg.extraConfig;
          }) cfg.sites;

          # 默认拒绝配置 (防止 IP 直接扫描)
          defaultSite = {
            "_" = {
              default = true;
              rejectSSL = true;
              locations."/" = { return = "444"; };
            };
          };
        in
          userSites // defaultSite;
    };
  };
}