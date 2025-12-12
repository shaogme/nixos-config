{ lib, config, pkgs, inputs, isImportChaotic ? false, ... }:
with lib;
let
  cfg = config.my.performance.kernel;
in {
  # 测试环境 (isTest=true) 不导入 chaotic 模块，避免与 runNixOSTest 只读设置冲突
  imports = lib.optional (!isImportChaotic) inputs.chaotic.nixosModules.default;

  options.my.performance.kernel = {
    mode = mkOption {
      type = types.enum [ "cachyos-unstable" "xanmod" "none" ];
      default = "none";
      description = "Select kernel optimization mode.";
    };
  };

  config = mkMerge [
    # --- CachyOS (Unstable) Configuration ---
    (mkIf (cfg.mode == "cachyos-unstable") {
      nix.settings = {
        extra-substituters = [ "https://nyx.chaotic.cx" "https://chaotic-nyx.cachix.org" ];
        extra-trusted-public-keys = [ "chaotic-nyx.cachix.org-1:HfnXSw4pj95iI/n17rIDy40agHj12WfF+Gqk6SonIT8=" ];
      };

      boot.kernelPackages = pkgs.linuxPackages_cachyos;
      services.scx.enable = false; # scx_rustland旨在将交互式工作负载优先于后台CPU密集型工作负载。出于这个原因，此调度程序的典型用例涉及低延迟交互式应用程序，例如游戏，视频会议和实时流媒体。
      boot.kernelModules = [ "tcp_bbr" ];

      boot.kernel.sysctl = {
        # BBRv3
        "net.ipv4.tcp_congestion_control" = "bbr";
        "net.core.default_qdisc" = "cake";

        # Buffer sizes
        "net.core.rmem_max" = 16777216;
        "net.core.wmem_max" = 16777216;
        "net.ipv4.tcp_rmem" = "4096 87380 16777216";
        "net.ipv4.tcp_wmem" = "4096 65536 16777216";
        
        "net.netfilter.nf_conntrack_max" = 1048576;
        
        # Low latency
        "net.ipv4.tcp_fastopen" = 3;
        "net.ipv4.tcp_slow_start_after_idle" = 0;
        "net.ipv4.tcp_notsent_lowat" = 16384;
        
        # ECN
        "net.ipv4.tcp_ecn" = 1;
        
        # High concurrency
        "net.ipv4.tcp_max_syn_backlog" = 8192;
        "net.core.somaxconn" = 8192;
        "net.ipv4.tcp_tw_reuse" = 1;
        
        # Keepalive
        "net.ipv4.tcp_keepalive_time" = 300;
        "net.ipv4.tcp_keepalive_intvl" = 60;
        "net.ipv4.tcp_keepalive_probes" = 5;
      };
    })

    # --- XanMod Configuration ---
    (mkIf (cfg.mode == "xanmod") {
      boot.kernelPackages = pkgs.linuxKernel.packages.linux_xanmod_latest;
      boot.kernelModules = [ "tcp_bbr" ];

      boot.kernel.sysctl = {
        "net.ipv4.tcp_congestion_control" = "bbr";
        "net.core.default_qdisc" = "fq"; # Google recommends fq for BBRv3 on XanMod

        # Aggressive Buffers
        "net.core.rmem_max" = 33554432;
        "net.core.wmem_max" = 33554432;
        "net.ipv4.tcp_rmem" = "4096 87380 33554432";
        "net.ipv4.tcp_wmem" = "4096 65536 33554432";
        "net.ipv4.udp_rmem_min" = 8192;
        "net.ipv4.udp_wmem_min" = 8192;

        "net.ipv4.tcp_notsent_lowat" = 16384;
        "net.ipv4.tcp_ecn" = 1;
        "net.ipv4.tcp_ecn_fallback" = 1;
        
        "net.ipv4.tcp_slow_start_after_idle" = 0;
        "net.ipv4.tcp_mtu_probing" = 1;
        "net.ipv4.tcp_fastopen" = 3;
        
        "net.netfilter.nf_conntrack_max" = 1048576;
        "net.netfilter.nf_conntrack_tcp_timeout_established" = 7200;
      };

      security.pam.loginLimits = [
        { domain = "*"; item = "nofile"; type = "soft"; value = "1048576"; }
        { domain = "*"; item = "nofile"; type = "hard"; value = "1048576"; }
      ];
    })
  ];
}
