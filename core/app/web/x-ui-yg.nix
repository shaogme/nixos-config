{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.core.app.web.x-ui-yg;
in {
  options.core.app.web.x-ui-yg = {
    enable = mkEnableOption "X-UI-YG Panel";

    domain = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Domain name for X-UI-YG (enables Nginx integration)";
    };

    username = mkOption {
      type = types.str;
      default = "";
      description = "Initial username (leave empty for random generation on first run)";
    };

    password = mkOption {
      type = types.str;
      default = "";
      description = "Initial password (leave empty for random generation on first run)";
    };
    
    backend = mkOption {
      type = types.enum [ "docker" "podman" ];
      default = "podman";
      description = "Container backend to use";
    };
  };

  config = mkIf cfg.enable {
    # Ensure backend is enabled
    core.container.${cfg.backend}.enable = true;
    
    # Ensure Nginx is enabled if domain is set
    core.app.web.nginx.enable = mkIf (cfg.domain != null) true;

    networking.firewall = {
      allowedTCPPorts = mkIf (cfg.domain == null) [ 54321 ];
      allowedTCPPortRanges = [
        { from = 10000; to = 10005; }
      ];
      allowedUDPPortRanges = [
        { from = 10000; to = 10005; }
      ];
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/x-ui-yg 0755 root root -"
      "d /var/lib/x-ui-yg/cert 0755 root root -"
    ];

    virtualisation.oci-containers = {
      backend = cfg.backend;
      containers.x-ui-yg = {
        image = "ghcr.io/shaog-r/x-ui-yg-docker:alpine";
        # 使用 host 网络模式
        extraOptions = [
          "--network=host"
          "--tty"
          "--memory=512m"
        ];
        volumes = [
          "/var/lib/x-ui-yg:/usr/local/x-ui"
          "/var/lib/x-ui-yg/cert:/root/cert"
        ];
        environment = {
          TZ = "Asia/Shanghai";
          XUI_USER = cfg.username;
          XUI_PASS = cfg.password;
          XUI_PORT = "54321";
        };
        autoStart = true;
      };
    };

    services.nginx.virtualHosts = mkIf (cfg.domain != null) {
      "${cfg.domain}" = {
        forceSSL = true;
        enableACME = true;
        http3 = true;
        quic = true;
        
        locations."/" = {
          proxyPass = "http://127.0.0.1:54321";
          proxyWebsockets = true;
          extraConfig = ''
            client_max_body_size 0;
          '';
        };
      };
    };
  };
}
