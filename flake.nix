{
  description = "NixOS Configuration Library - Core + Extra Integration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    
    # Core library
    lib-core.url = "path:./core";
    lib-core.inputs.nixpkgs.follows = "nixpkgs";
    
    # Extra kernel modules
    kernel-cachyos.url = "path:./extra/kernel/cachyos";
    kernel-cachyos.inputs.nixpkgs.follows = "nixpkgs";
    
    kernel-cachyos-unstable.url = "path:./extra/kernel/cachyos-unstable";
    kernel-cachyos-unstable.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { 
    self, 
    nixpkgs, 
    lib-core, 
    kernel-cachyos, 
    kernel-cachyos-unstable, 
    ... 
  }@inputs: 
  let
    system = "x86_64-linux";
    
    # ============================================================
    # 共用测试配置
    # ============================================================
    
    # 所有测试共享的基础配置
    testCommonConfig = { config, pkgs, ... }: {
      system.stateVersion = "25.11";
      core.base.enable = true;
      
      # Hardware
      core.hardware.type = "vps";
      core.hardware.disk = {
        enable = true;
        swapSize = 2048;
      };
      
      # Performance
      core.performance.tuning.enable = true;
      core.memory.mode = "aggressive";
      
      # Container
      core.container.podman.enable = true;
      
      # Update
      core.base.update = {
        enable = true;
        allowReboot = false;  # 测试中禁用自动重启
      };
    };
    
    # 共用的测试脚本
    testScript = ''
      start_all()
      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("podman.socket")
      
      # 验证内核版本
      kernel_version = machine.succeed("uname -r").strip()
      print(f"Kernel version: {kernel_version}")
      
      # 验证 BBR 拥塞控制算法已启用
      congestion = machine.succeed("sysctl -n net.ipv4.tcp_congestion_control").strip()
      assert congestion == "bbr", f"Expected bbr, got {congestion}"
      print(f"TCP congestion control: {congestion}")
      
      # 验证 BBR 在可用拥塞控制算法列表中
      # 注意: CachyOS 内核将 BBR 内置编译，所以不能用 lsmod 检查
      available = machine.succeed("cat /proc/sys/net/ipv4/tcp_available_congestion_control").strip()
      assert "bbr" in available, f"bbr not in available algorithms: {available}"
      print(f"Available congestion controls: {available}")
    '';
    
    # ============================================================
    # 测试 pkgs 构建函数
    # ============================================================
    
    # 标准 pkgs (用于 XanMod 测试)
    standardTestPkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
    
    # CachyOS pkgs (需要 chaotic overlay)
    cachyosTestPkgs = kernel-cachyos.lib.makeTestPkgs system;
    
    # CachyOS Unstable pkgs  
    cachyosUnstableTestPkgs = kernel-cachyos-unstable.lib.makeTestPkgs system;
    
    # ============================================================
    # 测试构建器
    # ============================================================
    
    # 创建测试的辅助函数
    mkKernelTest = { 
      name, 
      testPkgs, 
      kernelModule,
      extraConfig ? {}
    }: nixpkgs.legacyPackages.${system}.testers.nixosTest {
      name = "kernel-test-${name}";
      
      nodes.machine = { config, lib, ... }: {
        imports = [ 
          lib-core.nixosModules.default 
          kernelModule
          testCommonConfig
        ];
        
        # 使用对应内核的 testPkgs
        nixpkgs.pkgs = testPkgs;
        
        # 注入 inputs
        _module.args.inputs = lib-core.inputs;
        
        networking.hostName = "test-${name}";
      } // extraConfig;
      
      inherit testScript;
    };
    
  in {
    # ============================================================
    # 导出聚合模块
    # ============================================================
    
    nixosModules = {
      # 核心模块 (不含内核配置)
      default = lib-core.nixosModules.default;
      
      # 内核模块选项
      kernel-xanmod = lib-core.nixosModules.kernel-xanmod;
      kernel-cachyos = kernel-cachyos.nixosModules.default;
      kernel-cachyos-unstable = kernel-cachyos-unstable.nixosModules.default;
      
      # 完整预设: core + 内核
      full-xanmod = {
        imports = [
          lib-core.nixosModules.default
          lib-core.nixosModules.kernel-xanmod
        ];
      };
      
      full-cachyos = {
        imports = [
          lib-core.nixosModules.default
          kernel-cachyos.nixosModules.default
        ];
      };
      
      full-cachyos-unstable = {
        imports = [
          lib-core.nixosModules.default
          kernel-cachyos-unstable.nixosModules.default
        ];
      };
    };
    
    # ============================================================
    # 导出 Overlays
    # ============================================================
    
    overlays = {
      cachyos = kernel-cachyos.overlays.default;
      cachyos-unstable = kernel-cachyos-unstable.overlays.default;
    };
    
    # ============================================================
    # 测试 (nix flake check)
    # ============================================================
    
    checks.${system} = {
      # 测试 1: XanMod 内核 (标准内核)
      kernel-xanmod = mkKernelTest {
        name = "xanmod";
        testPkgs = standardTestPkgs;
        kernelModule = lib-core.nixosModules.kernel-xanmod;
      };
      
      # 测试 2: CachyOS 内核
      kernel-cachyos = mkKernelTest {
        name = "cachyos";
        testPkgs = cachyosTestPkgs;
        kernelModule = kernel-cachyos.nixosModules.default;
      };
      
      # 测试 3: CachyOS Unstable 内核
      kernel-cachyos-unstable = mkKernelTest {
        name = "cachyos-unstable";
        testPkgs = cachyosUnstableTestPkgs;
        kernelModule = kernel-cachyos-unstable.nixosModules.default;
      };
    };
    
    # ============================================================
    # 便捷函数
    # ============================================================
    
    lib = {
      # 创建测试 pkgs 的便捷函数
      makeTestPkgs = {
        standard = system: import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
        cachyos = kernel-cachyos.lib.makeTestPkgs;
        cachyos-unstable = kernel-cachyos-unstable.lib.makeTestPkgs;
      };
      
      # 创建内核测试的便捷函数
      inherit mkKernelTest;
    };
    
    # ============================================================
    # 传递 inputs (供子 flake 使用)
    # ============================================================
    
    inherit inputs;
  };
}
