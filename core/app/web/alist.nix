{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.core.app.web.alist;
in {
  options.core.app.web.alist = {
    enable = mkEnableOption "Alist File Listing";
    
    domain = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Domain name for Alist (enables Nginx integration)";
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

    networking.firewall.allowedTCPPorts = mkIf (cfg.domain == null) [ 5244 ];

    systemd.tmpfiles.rules = [
      "d /var/lib/alist 0755 root root -"
    ];

    virtualisation.oci-containers = {
      backend = cfg.backend;
      containers.alist = {
        image = "xhofe/alist:beta";
        ports = [ "5244:5244" ];
        volumes = [
          "/var/lib/alist:/opt/alist/data"
        ];
        environment = {
          PUID = "0";
          PGID = "0";
          UMASK = "022";
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
          proxyPass = "http://127.0.0.1:5244";
          extraConfig = ''
            client_max_body_size 0;
          '';
        };
      };
    };
  };
}
