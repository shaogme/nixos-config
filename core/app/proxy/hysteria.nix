{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.core.app.hysteria;
  yamlFormat = pkgs.formats.yaml { };

  hysteriaConfigRaw = let
    s = cfg.settings;
    # 处理混淆密码占位符 logic
    obfsConfig = if (s.obfs != null && s.obfs.type == "salamander") then 
      s.obfs // {
        salamander = s.obfs.salamander // {
          password = if s.obfs.salamander.password != "" 
                     then s.obfs.salamander.password 
                     else "__OBFS_PASSWORD_PLACEHOLDER__";
        };
      }
    else s.obfs;

    # 处理验证密码占位符 logic
    authConfig = if (s.auth != null && s.auth.type == "password") then
      s.auth // {
        password = if s.auth.password != ""
                   then s.auth.password
                   else "__AUTH_PASSWORD_PLACEHOLDER__";
      }
    else s.auth;
  in 
    # 过滤掉 null 值
    filterNulls (s // {
      obfs = obfsConfig;
      auth = authConfig;
    });

  # 过滤掉 null 值的辅助函数
  filterNulls = attrs: lib.filterAttrsRecursive (n: v: v != null) attrs;
  
  # 生成最终的配置文件 (Derivation)
  configFile = yamlFormat.generate "hysteria.yaml" (filterNulls hysteriaConfigRaw);

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

    # 复刻 Hysteria 的配置结构 (参照 example.yaml)
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
        description = "ACME configuration.";
        default = null;
        type = types.nullOr (types.submodule {
          options = {
            domains = mkOption { type = types.listOf types.str; default = []; };
            email = mkOption { type = types.nullOr types.str; default = null; };
            ca = mkOption { type = types.nullOr types.str; default = null; };
            listenHost = mkOption { type = types.str; default = "0.0.0.0"; };
            dir = mkOption { type = types.nullOr types.str; default = null; };
            type = mkOption { type = types.enum [ "http" "tls" "dns" ]; default = "http"; };
            http = mkOption {
              default = {};
              type = types.submodule {
                options = {
                  altPort = mkOption { type = types.port; default = 80; };
                };
              };
            };
            tls = mkOption {
              default = {};
              type = types.submodule {
                options = {
                   altPort = mkOption { type = types.port; default = 443; };
                };
              };
            };
            dns = mkOption {
              default = {};
              type = types.submodule {
                options = {
                  name = mkOption { type = types.str; default = ""; };
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
      
      ignoreClientBandwidth = mkOption { type = types.bool; default = false; };
      speedTest = mkOption { type = types.bool; default = false; };
      disableUDP = mkOption { type = types.bool; default = false; };
      udpIdleTimeout = mkOption { type = types.str; default = "60s"; };

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
            type = mkOption { type = types.enum ["udp" "tcp" "tls" "https"]; default = "udp"; };
            tcp = mkOption { 
              default = {}; 
              type = types.submodule { options = { addr = mkOption { type = types.str; default = ""; }; timeout = mkOption { type = types.str; default = "4s"; }; }; }; 
            };
            udp = mkOption { 
              default = {}; 
              type = types.submodule { options = { addr = mkOption { type = types.str; default = ""; }; timeout = mkOption { type = types.str; default = "4s"; }; }; }; 
            };
            tls = mkOption {
              default = {};
              type = types.submodule {
                options = {
                  addr = mkOption { type = types.str; default = ""; };
                  timeout = mkOption { type = types.str; default = "10s"; };
                  sni = mkOption { type = types.str; default = ""; };
                  insecure = mkOption { type = types.bool; default = false; };
                };
              };
            };
            https = mkOption {
              default = {};
              type = types.submodule {
                options = {
                  addr = mkOption { type = types.str; default = ""; };
                  timeout = mkOption { type = types.str; default = "10s"; };
                  sni = mkOption { type = types.str; default = ""; };
                  insecure = mkOption { type = types.bool; default = false; };
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
            enable = mkOption { type = types.bool; default = true; };
            timeout = mkOption { type = types.str; default = "2s"; };
            rewriteDomain = mkOption { type = types.bool; default = false; };
            tcpPorts = mkOption { type = types.str; default = "80,443"; };
            udpPorts = mkOption { type = types.str; default = "all"; };
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
            geoUpdateInterval = mkOption { type = types.str; default = "168h"; };
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
                   mode = mkOption { type = types.enum ["auto" "4" "6"]; default = "auto"; };
                   bindIPv4 = mkOption { type = types.nullOr types.str; default = null; };
                   bindIPv6 = mkOption { type = types.nullOr types.str; default = null; };
                   bindDevice = mkOption { type = types.nullOr types.str; default = null; };
                   fastOpen = mkOption { type = types.bool; default = false; };
                };
              };
            };
            socks5 = mkOption {
              default = {};
              type = types.submodule {
                options = {
                  addr = mkOption { type = types.str; default = ""; };
                  username = mkOption { type = types.str; default = ""; };
                  password = mkOption { type = types.str; default = ""; };
                };
              };
            };
            http = mkOption {
              default = {};
              type = types.submodule {
                 options = {
                   url = mkOption { type = types.str; default = ""; };
                   insecure = mkOption { type = types.bool; default = false; };
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
                   content = mkOption { type = types.str; default = ""; };
                   headers = mkOption { type = types.attrsOf types.str; default = {}; };
                   statusCode = mkOption { type = types.int; default = 200; };
                };
              };
            };
            listenHTTP = mkOption { type = types.nullOr types.str; default = null; };
            listenHTTPS = mkOption { type = types.nullOr types.str; default = null; };
            forceHTTPS = mkOption { type = types.bool; default = false; };
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
        assertion = cfg.settings.tls == null || cfg.settings.acme == null;
        message = "Hysteria: You cannot enable both TLS and ACME at the same time.";
      }
    ];

    # 1. 确保所选的容器后端已启用
    core.container.${cfg.backend}.enable = true;

    # 2. 创建 Systemd 服务来管理 Docker Compose
    systemd.services.hysteria = {
      description = "Hysteria Server (${cfg.backend} compose)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ] ++ lib.optional (cfg.backend == "docker") "docker.service";
      requires = lib.optional (cfg.backend == "docker") "docker.service";
      
      # 关键：服务启动脚本
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
        # 1. 准备数据目录
        mkdir -p ${cfg.dataDir}/acme
        
        # 2. 准备工作区
        WORK_DIR=/run/hysteria
        mkdir -p $WORK_DIR
        
        # 3. 处理配置文件 (支持运行时生成密码)
        cp ${configFile} ${runtimeConfig}

        # 函数：处理密码生成和替换
        # Usage: handle_secret <placeholder> <secret_file>
        handle_secret() {
          local ph=$1
          local file=$2
          if grep -q "$ph" ${runtimeConfig}; then
            if [ ! -f "$file" ]; then
              echo "Generating new secret for $ph..."
              ${pkgs.openssl}/bin/openssl rand -hex 16 > "$file"
            fi
            SECRET=$(cat "$file")
            # 替换占位符
            sed -i "s|$ph|$SECRET|g" ${runtimeConfig}
          fi
        }

        handle_secret "${obfsPlaceholder}" "${obfsFile}"
        handle_secret "${authPlaceholder}" "${authFile}"
        
        # 4. 链接 Compose 文件
        # 注意：这里我们链接的是 Nix Store 中的只读文件
        ln -sf ${composeFile} $WORK_DIR/docker-compose.yaml

        # 5. 启动容器
        # --project-name 确保容器组名称固定
        ${composeBin} -f $WORK_DIR/docker-compose.yaml -p hysteria-server up --remove-orphans
      '';

      # 停止服务的逻辑
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