{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.core.app.hysteria;
  yamlFormat = pkgs.formats.yaml { };

  removeEmpty = let
    isSecret = v: isString v && (hasPrefix "__" v);
    isEmpty = v: v == null || v == [] || v == {} || (isString v && v == "" && !isSecret v);
  in
    attr:
    if isAttrs attr then
      let
        filtered = mapAttrs (n: v: removeEmpty v) attr;
        result = filterAttrs (n: v: !isEmpty v) filtered;
      in result
    else if isList attr then
      let
        filtered = map (v: removeEmpty v) attr;
        result = filter (v: !isEmpty v) filtered;
      in result
    else attr;

  hysteriaConfigRaw = let
    s = cfg.settings;

    # logic helpers
    pick = set: keys: if set == null then null else
      let
        picked = filterAttrs (n: v: elem n keys) set;
      in if picked == {} then null else picked;

    # 1. ACME
    acmeRaw = if s.acme == null then null else
      let
        a = s.acme;
        common = { inherit (a) domains email ca listenHost dir type; };
        specific = if a.type == "http" then { inherit (a) http; }
                   else if a.type == "tls" then { inherit (a) tls; }
                   else if a.type == "dns" then { inherit (a) dns; }
                   else {};
      in common // specific;

    # 2. Auth (handle placeholder)
    authRaw = if s.auth == null then null else
      let
        a = s.auth;
        common = { inherit (a) type; };
        specific = if a.type == "password" then {
            password = if a.password != "" then a.password else "__AUTH_PASSWORD_PLACEHOLDER__";
          }
          else if a.type == "userpass" then { inherit (a) userpass; }
          else if a.type == "http" then { inherit (a) http; }
          else if a.type == "command" then { inherit (a) command; }
          else {};
      in common // specific;

    # 3. Obfs (handle placeholder)
    obfsRaw = if s.obfs == null then null else
      let
        o = s.obfs;
        common = { inherit (o) type; };
        specific = if o.type == "salamander" then {
            salamander = {
               password = if o.salamander.password != "" then o.salamander.password else "__OBFS_PASSWORD_PLACEHOLDER__";
            };
          } else {};
      in common // specific;

   # 4. Outbounds
    outboundsRaw = if s.outbounds == [] then null else
      map (o:
        let
          common = { inherit (o) name type; };
          specific = if o.type == "direct" then { inherit (o) direct; }
                     else if o.type == "socks5" then { inherit (o) socks5; }
                     else if o.type == "http" then { inherit (o) http; }
                     else {};
        in common // specific
      ) s.outbounds;
    
    # 5. Resolver 
    resolverRaw = if s.resolver == null then null else
       let
         r = s.resolver;
         common = { inherit (r) type; };
         specific = if r.type == "udp" then { inherit (r) udp; }
                    else if r.type == "tcp" then { inherit (r) tcp; }
                    else if r.type == "tls" then { inherit (r) tls; }
                    else if r.type == "https" then { inherit (r) https; }
                    else {};
       in common // specific;

    # 6. Masquerade
    masqueradeRaw = if s.masquerade == null then null else
       let
         m = s.masquerade;
         common = { inherit (m) type listenHTTP listenHTTPS forceHTTPS; };
         specific = if m.type == "file" then { inherit (m) file; }
                    else if m.type == "proxy" then { inherit (m) proxy; }
                    else if m.type == "string" then { inherit (m) string; }
                    else {};
       in common // specific;

  in 
    removeEmpty {
      inherit (s) listen quic bandwidth ignoreClientBandwidth speedTest disableUDP udpIdleTimeout sniff acl trafficStats;
      tls = s.tls;
      acme = acmeRaw;
      obfs = obfsRaw;
      auth = authRaw;
      resolver = resolverRaw;
      outbounds = outboundsRaw;
      masquerade = masqueradeRaw;
    };

  # 生成最终的配置文件 (Derivation)
  configFile = pkgs.runCommand "hysteria.yaml" {
    nativeBuildInputs = [ pkgs.yq-go ];
    value = builtins.toJSON hysteriaConfigRaw;
    passAsFile = [ "value" ];
  } ''
    yq -P '.' "$valuePath" > $out
  '';

  # --- 2. 定义 Docker Compose 结构 ---
  composeConfigRaw = {
    version = "3.9";
    services.hysteria = {
      image = cfg.image;
      container_name = "hysteria-service";
      restart = "always";
      network_mode = "host"; # Hysteria 强烈建议 Host 模式
      cap_add = [ "NET_ADMIN" ];
      volumes = [
        "${cfg.dataDir}/acme:/acme" # 持久化 ACME 数据
        "/run/hysteria/config.yaml:/etc/hysteria.yaml" # 挂载运行时的配置文件
      ];
      command = [ "server" "-c" "/etc/hysteria.yaml" ];
    };
  };

  # 生成 Compose 文件 (Derivation)
  composeFile = yamlFormat.generate "docker-compose.yaml" composeConfigRaw;

in {
  # ==========================================
  # 接口定义 (Options)
  # ==========================================
  options.core.app.hysteria = {
    enable = mkEnableOption "Hysteria Server";

    # 新增：通过 Nginx/Lego 托管 ACME 的域名
    domain = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Domain for ACME (managed via nginx.nix standalone mode).";
    };

    backend = mkOption {
      type = types.enum [ "docker" "podman" ];
      default = "docker";
      description = "The container backend to use.";
    };

    image = mkOption {
      type = types.str;
      default = "tobyxdd/hysteria:latest";
      description = "The container image to use.";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/hysteria";
      description = "Directory to store persistent data (ACME certs).";
    };

    portHopping = {
      enable = mkEnableOption "Hysteria Port Hopping";
      range = mkOption {
        type = types.str;
        default = "20000-50000";
        description = "UDP port range for hopping.";
      };
      interface = mkOption {
        type = types.str;
        default = "eth0";
        description = "Ingress interface for port hopping.";
      };
    };

    # 复刻 Hysteria 的配置结构
    settings = {
      listen = mkOption { type = types.str; default = ":443"; description = "Server listen address."; };
      
      tls = mkOption {
        description = "TLS configuration.";
        default = null;
        type = types.nullOr (types.submodule {
          options = {
            cert = mkOption { type = types.str; };
            key = mkOption { type = types.str; };
            sniGuard = mkOption { type = types.nullOr (types.enum [ "strict" "disable" "dns-san" ]); default = null; };
            clientCA = mkOption { type = types.nullOr types.str; default = null; };
          };
        });
      };

      acme = mkOption {
        description = "ACME configuration (Internal Hysteria ACME).";
        default = null;
        type = types.nullOr (types.submodule {
          options = {
            domains = mkOption { type = types.listOf types.str; default = []; };
            email = mkOption { type = types.nullOr types.str; default = null; };
            ca = mkOption { type = types.nullOr types.str; default = null; };
            listenHost = mkOption { type = types.nullOr types.str; default = null; };
            dir = mkOption { type = types.nullOr types.str; default = null; };
            type = mkOption { type = types.nullOr (types.enum [ "http" "tls" "dns" ]); default = null; };
            http = mkOption {
              default = {};
              type = types.submodule {
                options = {
                  altPort = mkOption { type = types.nullOr types.port; default = null; };
                };
              };
            };
            tls = mkOption {
              default = {};
              type = types.submodule {
                options = {
                   altPort = mkOption { type = types.nullOr types.port; default = null; };
                };
              };
            };
            dns = mkOption {
              default = {};
              type = types.submodule {
                options = {
                  name = mkOption { type = types.nullOr types.str; default = null; };
                  config = mkOption { type = types.attrsOf types.str; default = {}; };
                };
              };
            };
          };
        });
      };
      
      obfs = mkOption {
        default = null;
        description = "Obfuscation configuration.";
        type = types.nullOr (types.submodule {
          options = {
            type = mkOption { type = types.enum [ "salamander" ]; default = "salamander"; };
            salamander = mkOption {
              default = {};
              type = types.submodule {
                options = {
                  password = mkOption { type = types.str; default = ""; description = "Leave empty to auto-generate."; };
                };
              };
            };
          };
        });
      };

      quic = mkOption {
        description = "QUIC parameters.";
        default = null;
        type = types.nullOr (types.submodule {
           options = {
             initStreamReceiveWindow = mkOption { type = types.nullOr types.int; default = null; };
             maxStreamReceiveWindow = mkOption { type = types.nullOr types.int; default = null; };
             initConnReceiveWindow = mkOption { type = types.nullOr types.int; default = null; };
             maxConnReceiveWindow = mkOption { type = types.nullOr types.int; default = null; };
             maxIdleTimeout = mkOption { type = types.nullOr types.str; default = null; };
             maxIncomingStreams = mkOption { type = types.nullOr types.int; default = null; };
             disablePathMTUDiscovery = mkOption { type = types.nullOr types.bool; default = null; };
           };
        });
      };
      
      bandwidth = mkOption {
        description = "Bandwidth limits.";
        default = null;
        type = types.nullOr (types.submodule {
          options = {
            up = mkOption { type = types.str; example = "1 gbps"; };
            down = mkOption { type = types.str; example = "1 gbps"; };
          };
        });
      };
      
      ignoreClientBandwidth = mkOption { type = types.nullOr types.bool; default = null; };
      speedTest = mkOption { type = types.nullOr types.bool; default = null; };
      disableUDP = mkOption { type = types.nullOr types.bool; default = null; };
      udpIdleTimeout = mkOption { type = types.nullOr types.str; default = null; };

      auth = mkOption {
        default = null;
        description = "Authentication configuration.";
        type = types.nullOr (types.submodule {
          options = {
            type = mkOption { type = types.enum [ "password" "userpass" "http" "command" ]; default = "password"; };
            password = mkOption { type = types.str; default = ""; description = "Leave empty to auto-generate."; };
            userpass = mkOption { type = types.attrsOf types.str; default = {}; };
            http = mkOption {
              default = {};
              type = types.submodule {
                options = {
                  url = mkOption { type = types.str; default = ""; };
                  insecure = mkOption { type = types.bool; default = false; };
                };
              };
            };
            command = mkOption { type = types.str; default = ""; };
          };
        });
      };

      resolver = mkOption {
        description = "DNS resolver configuration.";
        default = null;
        type = types.nullOr (types.submodule {
          options = {
            type = mkOption { type = types.nullOr (types.enum ["udp" "tcp" "tls" "https"]); default = null; };
            tcp = mkOption { 
              default = {}; 
              type = types.submodule { options = { addr = mkOption { type = types.nullOr types.str; default = null; }; timeout = mkOption { type = types.nullOr types.str; default = null; }; }; }; 
            };
            udp = mkOption { 
              default = {}; 
              type = types.submodule { options = { addr = mkOption { type = types.nullOr types.str; default = null; }; timeout = mkOption { type = types.nullOr types.str; default = null; }; }; }; 
            };
            tls = mkOption {
              default = {};
              type = types.submodule {
                options = {
                  addr = mkOption { type = types.nullOr types.str; default = null; };
                  timeout = mkOption { type = types.nullOr types.str; default = null; };
                  sni = mkOption { type = types.nullOr types.str; default = null; };
                  insecure = mkOption { type = types.nullOr types.bool; default = null; };
                };
              };
            };
            https = mkOption {
              default = {};
              type = types.submodule {
                options = {
                  addr = mkOption { type = types.nullOr types.str; default = null; };
                  timeout = mkOption { type = types.nullOr types.str; default = null; };
                  sni = mkOption { type = types.nullOr types.str; default = null; };
                  insecure = mkOption { type = types.nullOr types.bool; default = null; };
                };
              };
            };
          };
        });
      };

      sniff = mkOption {
        description = "SNI sniffing configuration.";
        default = null;
        type = types.nullOr (types.submodule {
          options = {
            enable = mkOption { type = types.nullOr types.bool; default = null; };
            timeout = mkOption { type = types.nullOr types.str; default = null; };
            rewriteDomain = mkOption { type = types.nullOr types.bool; default = null; };
            tcpPorts = mkOption { type = types.nullOr types.str; default = null; };
            udpPorts = mkOption { type = types.nullOr types.str; default = null; };
          };
        });
      };

      acl = mkOption {
        description = "ACL configuration.";
        default = null;
        type = types.nullOr (types.submodule {
          options = {
            file = mkOption { type = types.nullOr types.str; default = null; };
            geoip = mkOption { type = types.nullOr types.str; default = null; };
            geosite = mkOption { type = types.nullOr types.str; default = null; };
            geoUpdateInterval = mkOption { type = types.nullOr types.str; default = null; };
            inline = mkOption { type = types.listOf types.str; default = []; };
          };
        });
      };
      
      outbounds = mkOption {
        description = "Outbound chains.";
        default = [];
        type = types.listOf (types.submodule {
          options = {
            name = mkOption { type = types.str; };
            type = mkOption { type = types.enum ["direct" "socks5" "http"]; default = "direct"; };
            direct = mkOption {
              default = {};
              type = types.submodule {
                options = {
                   mode = mkOption { type = types.nullOr (types.enum ["auto" "4" "6"]); default = null; };
                   bindIPv4 = mkOption { type = types.nullOr types.str; default = null; };
                   bindIPv6 = mkOption { type = types.nullOr types.str; default = null; };
                   bindDevice = mkOption { type = types.nullOr types.str; default = null; };
                   fastOpen = mkOption { type = types.nullOr types.bool; default = null; };
                };
              };
            };
            socks5 = mkOption {
              default = {};
              type = types.submodule {
                options = {
                  addr = mkOption { type = types.nullOr types.str; default = null; };
                  username = mkOption { type = types.nullOr types.str; default = null; };
                  password = mkOption { type = types.nullOr types.str; default = null; };
                };
              };
            };
            http = mkOption {
              default = {};
              type = types.submodule {
                 options = {
                   url = mkOption { type = types.nullOr types.str; default = null; };
                   insecure = mkOption { type = types.nullOr types.bool; default = null; };
                 };
              };
            };
          };
        });
      };

      trafficStats = mkOption {
        description = "Traffic statistics API.";
        default = null;
        type = types.nullOr (types.submodule {
          options = {
            listen = mkOption { type = types.str; };
            secret = mkOption { type = types.str; };
          };
        });
      };
      
      masquerade = mkOption {
        description = "Impersonation/Masquerade configuration.";
        default = null;
        type = types.nullOr (types.submodule {
          options = {
            type = mkOption { type = types.enum ["file" "proxy" "string"]; };
            file = mkOption {
              default = {};
              type = types.submodule {
                options = { dir = mkOption { type = types.str; default = ""; }; };
              };
            };
            proxy = mkOption {
              default = {};
              type = types.submodule {
                options = {
                  url = mkOption { type = types.str; default = ""; };
                  rewriteHost = mkOption { type = types.bool; default = true; };
                  insecure = mkOption { type = types.bool; default = false; };
                };
              };
            };
            string = mkOption {
              default = {};
              type = types.submodule {
                options = {
                   content = mkOption { type = types.nullOr types.str; default = null; };
                   headers = mkOption { type = types.attrsOf types.str; default = {}; };
                   statusCode = mkOption { type = types.nullOr types.int; default = null; };
                };
              };
            };
            listenHTTP = mkOption { type = types.nullOr types.str; default = null; };
            listenHTTPS = mkOption { type = types.nullOr types.str; default = null; };
            forceHTTPS = mkOption { type = types.nullOr types.bool; default = null; };
          };
        });
      };
    };
  };

  # ==========================================
  # 实现逻辑 (Config)
  # ==========================================
  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !(cfg.settings.tls != null && cfg.settings.acme != null);
        message = "Hysteria: You cannot enable both TLS and internal ACME at the same time.";
      }
      {
        assertion = !(cfg.domain != null && cfg.settings.acme != null);
        message = "Hysteria: You cannot enable 'domain' (managed ACME) and 'settings.acme' (internal ACME) at the same time.";
      }
    ];

    # 1. ACME 与 Nginx 集成逻辑
    # 当设置了 cfg.domain 时，自动配置 Nginx 的 site 和 Lego 钩子
    core.app.web.nginx.enable = mkIf (cfg.domain != null) true;
    
    core.app.web.nginx.sites = mkIf (cfg.domain != null) {
      "${cfg.domain}" = {
        # 仅返回 404，不暴露任何服务，只为了占用端口进行 ACME 验证
        locations."/" = { return = "404"; };
        
        # 核心逻辑：ACME Hook
        # 证书更新后，将其复制到 Hysteria 的数据目录
        # Lego 运行在 acme 用户下，需要确保目标目录可写 (通过下面的 tmpfiles 处理)
        acmePostRun = ''
          mkdir -p ${cfg.dataDir}/acme
          cp fullchain.pem ${cfg.dataDir}/acme/server.crt
          cp key.pem ${cfg.dataDir}/acme/server.key
          
          # 设置权限，确保容器内 (root) 或指定用户可读
          chmod 644 ${cfg.dataDir}/acme/server.crt
          chmod 644 ${cfg.dataDir}/acme/server.key
          
          # 可选：如果支持热重载，则不需要重启。Hysteria 支持文件监听热重载。
        '';
      };
    };

    # 自动配置 Hysteria TLS 指向复制过来的证书
    core.app.hysteria.settings.tls = mkIf (cfg.domain != null) {
      cert = "/acme/server.crt";
      key = "/acme/server.key";
    };

    # 权限修复：确保 acme 用户组可以写入 Hysteria 的证书目录
    # /var/lib/hysteria 默认是 root:root 0755
    # 我们创建子目录 acme 并允许 acme 组写入
    systemd.tmpfiles.rules = mkIf (cfg.domain != null) [
      "d ${cfg.dataDir}/acme 0770 root acme -"
    ];

    # 2. 确保所选的容器后端已启用
    core.container.${cfg.backend}.enable = true;

    # 3. 自动配置防火墙
    networking.firewall = {
      allowedTCPPorts = mkIf (cfg.settings.acme != null && (cfg.settings.acme.type == null || cfg.settings.acme.type == "http")) [ 80 ];
      allowedUDPPorts = let
        portStr = last (splitString ":" cfg.settings.listen);
        port = toInt portStr;
      in [ port ];
      allowedUDPPortRanges = mkIf cfg.portHopping.enable (let 
        parts = splitString "-" cfg.portHopping.range;
        from = toInt (head parts);
        to = toInt (last parts);
      in [ { inherit from to; } ]);
    };

    # 4. 创建 Systemd 服务来管理 Docker Compose
    systemd.services.hysteria = {
      description = "Hysteria Server (${cfg.backend} compose)";
      path = if cfg.backend == "docker" then [ pkgs.docker ] else [ pkgs.podman ];
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ] ++ lib.optional (cfg.backend == "docker") "docker.service";
      requires = lib.optional (cfg.backend == "docker") "docker.service";
      
      script = let
        composeBin = if cfg.backend == "docker" 
          then "${pkgs.docker-compose}/bin/docker-compose" 
          else "${pkgs.podman-compose}/bin/podman-compose";
          
        obfsPlaceholder = "__OBFS_PASSWORD_PLACEHOLDER__";
        authPlaceholder = "__AUTH_PASSWORD_PLACEHOLDER__";
        
        runtimeConfig = "/run/hysteria/config.yaml";
        
        obfsFile = "${cfg.dataDir}/obfs_password";
        authFile = "${cfg.dataDir}/auth_password";
      in ''
        # 1. 准备数据目录 (确保存在，tmpfiles 也会创建但这里双重保险)
        mkdir -p ${cfg.dataDir}/acme
        
        # 2. 准备工作区
        WORK_DIR=/run/hysteria
        mkdir -p $WORK_DIR
        
        # 3. 处理配置文件
        cp ${configFile} ${runtimeConfig}

        # 函数：处理密码生成和替换
        handle_secret() {
          local ph=$1
          local file=$2
          if grep -q "$ph" ${runtimeConfig}; then
            if [ ! -f "$file" ]; then
              echo "Generating new secret for $ph..."
              ${pkgs.openssl}/bin/openssl rand -hex 16 > "$file"
            fi
            SECRET=$(cat "$file")
            sed -i "s|$ph|$SECRET|g" ${runtimeConfig}
          fi
        }

        handle_secret "${obfsPlaceholder}" "${obfsFile}"
        handle_secret "${authPlaceholder}" "${authFile}"
        
        # 4. 链接 Compose 文件
        ln -sf ${composeFile} $WORK_DIR/docker-compose.yaml

        # 5. 启动容器
        ${composeBin} -f $WORK_DIR/docker-compose.yaml -p hysteria-server up --remove-orphans
      '';

      preStop = let
        composeBin = if cfg.backend == "docker" 
          then "${pkgs.docker-compose}/bin/docker-compose" 
          else "${pkgs.podman-compose}/bin/podman-compose";
      in ''
        WORK_DIR=/run/hysteria
        ${composeBin} -f $WORK_DIR/docker-compose.yaml -p hysteria-server down
      '';

      serviceConfig = {
        Restart = "always";
        RestartSec = "5s";
      };
    };

    networking.nftables.tables.hysteria_porthopping = mkIf cfg.portHopping.enable {
      family = "inet";
      content = let
        port = last (splitString ":" cfg.settings.listen);
      in ''
        chain prerouting {
          type nat hook prerouting priority dstnat; policy accept;
          iifname "${cfg.portHopping.interface}" udp dport ${cfg.portHopping.range} counter redirect to :${port}
        }
      '';
    };
  };
}