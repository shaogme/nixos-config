{
  description = "My NixOS Flake Library";

  inputs = {
    # 基础依赖
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    
    # flake-parts - 模块化 flake 框架
    flake-parts.url = "github:hercules-ci/flake-parts";
    
    # 外部模块依赖
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    
    nixos-facter-modules.url = "github:nix-community/nixos-facter-modules";
    
    # 注意：chaotic 不在这里！它被隔离到 kernel 分区中
  };

  outputs = inputs@{ self, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } ({ config, ... }: {
      # 导入 partitions 支持
      imports = [
        flake-parts.flakeModules.partitions
      ];

      # 定义系统架构
      systems = [ "x86_64-linux" "aarch64-linux" ];

      # === 分区配置 ===
      # kernel 分区包含 chaotic 依赖，只有使用 kernel 模块时才会获取
      partitions.kernel = {
        # 子 flake 包含 chaotic input
        extraInputsFlake = ./modules/kernel;
        # flake-parts 模块定义 kernel NixOS 模块
        module.imports = [ ./modules/kernel/flake-module.nix ];
      };

      # === 主要 Flake 输出 ===
      flake = {
        # 核心 NixOS 模块（不需要 chaotic）
        nixosModules = {
          # 聚合入口 - 导入所有基础模块
          default = { config, pkgs, lib, ... }: {
            imports = [
              inputs.nixos-facter-modules.nixosModules.facter
              inputs.disko.nixosModules.disko
              
              ./modules/app/default.nix
              ./modules/base/default.nix
              ./modules/hardware/default.nix
            ];
          };
          
          # Xanmod 内核（无需 chaotic）
          kernel-xanmod = ./modules/kernel/xanmod.nix;
        } 
        # 合并 kernel 分区的模块
        // config.partitions.kernel.module.flake.nixosModules;
      };
    });
}