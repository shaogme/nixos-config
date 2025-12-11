{ lib, config, inputs, ... }:
let
  cfg = config.system.copyFlakeToNixos;
in {
  options.system.copyFlakeToNixos = {
    enable = lib.mkEnableOption "copying system configuration to /etc/nixos";
    
    force = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to overwrite existing configuration";
    };
  };

  config = lib.mkIf cfg.enable {
    system.activationScripts.copy-nixos-config = {
      text = ''
        if [ ${if cfg.force then "true" else "! -f /etc/nixos/flake.nix"} ]; then
          echo "Initializing /etc/nixos from flake source..."
          mkdir -p /etc/nixos
          # --no-preserve=mode 确保复制后文件不是只读的
          cp -rT --no-preserve=mode ${inputs.self} /etc/nixos
          chmod -R u+w /etc/nixos
        fi
      '';
    };
  };
}
