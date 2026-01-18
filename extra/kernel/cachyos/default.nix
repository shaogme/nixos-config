{ lib, config, pkgs, ... }:
with lib;
let
  cfg = config.my.kernel.cachyos;
  sysctlConfig = import ./sysctl.nix;
in {
  options.my.kernel.cachyos = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "CachyOS kernel with BBRv3 network optimization";
    };
  };

  config = mkIf cfg.enable {
    boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest;

    # scx_rustland旨在将交互式工作负载优先于后台CPU密集型工作负载
    services.scx.enable = false;

    # 确保加载 BBR 模块 (对于 CachyOS 内核，tcp_bbr 即为 BBRv3)
    boot.kernelModules = [ "tcp_bbr" ];

    # 网络栈参数调优 (从 sysctl.nix 导入)
    boot.kernel.sysctl = sysctlConfig;
  };
}
