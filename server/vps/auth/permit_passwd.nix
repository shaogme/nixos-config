{ initialHashedPassword, authorizedKeys }:
{ config, pkgs, lib, ... }:

{
  # --- Root 用户配置 ---
  users.users.root = {
    # 强制禁用 hashedPasswordFile，解决冲突
    hashedPasswordFile = lib.mkForce null;

    initialHashedPassword = initialHashedPassword;
    
    openssh.authorizedKeys.keys = authorizedKeys;
  };

  # --- SSH 安全加固 (配合使用) ---
  services.openssh = {
    settings = {
      # 允许 Root 密码登录
      PermitRootLogin = "yes"; 
      
      # 禁止空密码
      PermitEmptyPasswords = "no";
    };
  };
}