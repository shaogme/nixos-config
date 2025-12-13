{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.core.auth;
in {
  options.core.auth = {
    root = {
      mode = mkOption {
        type = types.enum [ "default" "permit_passwd" ];
        default = "default";
        description = ''
          Root login mode:
          - default: prohibit-password (key-based only recommended)
          - permit_passwd: allow password login (less secure)
        '';
      };

      initialHashedPassword = mkOption {
        type = types.str;
        default = "";
        description = "Initial hashed password for root user (empty = no password login)";
      };

      authorizedKeys = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "List of authorized SSH keys for root user";
      };
    };
  };

  config = {
    # --- Root 用户配置 ---
    users.users.root = {
      # 强制禁用 hashedPasswordFile，解决冲突
      hashedPasswordFile = mkForce null;

      initialHashedPassword = cfg.root.initialHashedPassword;
      openssh.authorizedKeys.keys = cfg.root.authorizedKeys;
    };

    # --- SSH 安全加固 ---
    services.openssh.settings = {
      PermitEmptyPasswords = "no";
      
      # 根据 mode 动态设定 PermitRootLogin
      PermitRootLogin = if cfg.root.mode == "permit_passwd" 
                        then "yes" 
                        else "prohibit-password";
    };
  };
}
