{
  description = "My NixOS Flake Library";

  inputs = {
    # 基础依赖 (用于定义 module 系统)
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    
    # 外部模块依赖
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    
    nixos-facter-modules.url = "github:nix-community/nixos-facter-modules";
    
    # chaotic 不在这里！它被隔离到 kernel 子目录中
  };

  outputs = { self, nixpkgs, disko, nixos-facter-modules, ... }@inputs: 
  let
    # === 子 Flake 加载器 ===
    # 使用 builtins.fetchTree + import 手动加载子 flake
    # 这样可以完全隔离子 flake 的依赖
    loadSubFlake = path: 
      let
        # 1. 获取子 flake 目录（放入 store 保证纯净性）
        src = builtins.fetchTree {
          type = "path";
          path = toString path;
        };
        # 2. 导入子 flake.nix 文件
        flakeFile = import "${src}/flake.nix";
        # 3. 解析子 flake 的 inputs（递归获取其依赖）
        resolvedInputs = builtins.mapAttrs (name: input:
          if builtins.hasAttr "url" input then
            builtins.getFlake input.url
          else
            input
        ) (flakeFile.inputs or {});
        # 4. 调用子 flake 的 outputs 函数
        outputs = flakeFile.outputs (resolvedInputs // { 
          self = outputs; 
        });
      in outputs;
  in {
    # 1. 导出所有模块为一个聚合入口
    nixosModules = {
      default = { config, pkgs, lib, ... }: {
        imports = [
          nixos-facter-modules.nixosModules.facter
          disko.nixosModules.disko
          
          ./modules/app/default.nix
          ./modules/base/default.nix
          ./modules/hardware/default.nix
        ];
      };
      
      # 2. 细分导出 - 内核优化模块（真正的惰性加载）
      # loadSubFlake 在模块函数内调用，只有当模块被 import 时才会求值
      # 这意味着：不使用 kernel-cachyos 的用户永远不会下载 chaotic
      kernel-cachyos = { ... }: {
        imports = [
          (loadSubFlake ./modules/kernel/cachyos).nixosModules.default
        ];
      };
      kernel-cachyos-unstable = { ... }: {
        imports = [
          (loadSubFlake ./modules/kernel/cachyos-unstable).nixosModules.default
        ];
      };
      kernel-xanmod = ./modules/kernel/xanmod.nix;
    };
  };
}
