{ domain, enable ? true }:
{ config, pkgs, lib, ... }:

{
  imports = [
    ../container/podman.nix
    ../../services/web/nginx.nix
  ];

  config = lib.mkIf enable {
    # networking.firewall.allowedTCPPorts = [ 5244 ];

    systemd.tmpfiles.rules = [
      "d /var/lib/alist 0755 root root -"
    ];

    virtualisation.oci-containers = {
      backend = "podman";
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

    services.nginx.virtualHosts."${domain}" = {
      forceSSL = true;
      enableACME = true;
      http3 = true;
      quic = true;
      
      locations."/" = {
        proxyPass = "http://127.0.0.1:5244";
        # proxyWebsockets is not needed if we rely on recommendedProxySettings or if standard proxying is enough, 
        # but user removed it in previous step. I'll stick to what was there or standard.
        # User removed proxyWebsockets = true; in previous step. Explicitly keeping it removed.
        extraConfig = ''
          client_max_body_size 0;
        '';
      };
    };
  };
}
