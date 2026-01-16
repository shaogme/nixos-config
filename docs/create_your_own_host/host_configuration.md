# 主机配置详解

本文档聚焦于 `flake.nix` 中需要修改的关键配置项。

## 关键配置修改

你需要重点关注 `hostConfig` 区域的修改。

### 1. 基础信息

```nix
hostConfig = {
    name = "<新主机名>"; // 一定和刚才的文件夹名相同
}
```

### 2. 认证信息 (Auth)

```nix
auth = {
    rootHash = "$6$xxxxxxxx";
    sshKeys = [ "ssh-ed25519 AAAA..." ];
};
```

**配置说明：**

1. **Root 密码 (rootHash)**
   **一定要修改 rootHash**，运行以下命令生成：
   ```bash
   nix run nixpkgs#mkpasswd -- -m sha-512
   ```
   将生成的结果填入 `rootHash`。

2. **SSH 公钥 (sshKeys)**
   将你的 SSH 公钥内容 (通常在 `~/.ssh/id_ed25519.pub`) 添加到 `sshKeys` 列表。

3. **认证模式 (Auth Mode)**
   你可以在 `core.auth.root` 中配置认证模式（默认为 `default`）。支持以下模式：

   | 模式 | SSH 密码登录 | SSH 密钥登录 | 说明 |
   |------|-------------|-------------|------|
   | `default` | ❌ 禁止 | ✅ 允许 | 推荐，最安全 |
   | `permit_passwd` | ✅ 允许 | ✅ 允许 | 开发/调试用，不安全 |

### 3. 静态 IP 配置

如果需要静态 IP，请配置 `ipv4` 块：

```nix
# 静态 IP 配置
      ipv4 = {
        address = "192.168.1.100";
        gateway = "192.168.1.1";
        prefixLength = 24;
      };
```

你可以通过在远程主机运行以下脚本来获取当前网络配置，并直接复制结果：
```bash
curl -O https://raw.githubusercontent.com/shaogme/nixos-config/refs/heads/main/scripts/check-net.sh && chmod +x check-net.sh && ./check-net.sh 
```

### 4. 磁盘配置

在远程主机运行 `lsblk` 命令，查看主磁盘是 `vda` 还是 `sda`。

如果是 `vda`，你需要手动修改 `config.core.hardware.disk` 部分：

```nix
core.hardware.disk = {
    enable = true;
    device = "/dev/vda"; // 增加这行，指定设备为 vda
    swapSize = 2048;
};
```
(如果默认是 `/dev/sda` 且你的设备也是 `sda`，则无需添加 `device` 行)


## 内联 VM 测试

我们在配置中包含了一个 `vmTest` 模块。这利用了 NixOS 的测试框架，在构建时启动一个轻量级虚拟机来验证系统能否正常启动。

**运行测试：**

```bash
nix build .#nixosConfigurations.<新主机名>.config.system.build.vmTest
```

如果构建成功，说明系统基本配置无误，容器运行环境正常。

---

## 完整配置详解

下面展示完整的 `flake.nix` 配置内容及其详细含义。

```nix
{
  description = "My New Host Configuration";

  inputs = {
    # 引用 nixpkgs 仓库，这里使用 unstable-small 分支以减小体积
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable-small";
    # 引用核心模块库
    lib-core.url = "path:../../core";
    lib-core.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, lib-core, ... }: 
  let
    system = "x86_64-linux";

    # ==========================================
    # Host Configuration (集中配置区域)
    # 这里的变量会被下方的配置引用
    # ==========================================
    hostConfig = {
      name = "<新主机名>"; # 主机名，与文件夹名保持一致

      auth = {
        rootHash = "$6$xxxxxxxx"; # Root 密码哈希
        sshKeys = [ "ssh-ed25519 AAAA..." ]; # SSH 公钥列表
      };
      
      # 静态 IP 配置示例 (可选)
      # ipv4 = {
      #   address = "1.2.3.4";
      #   gateway = "1.2.3.1";
      #   prefixLength = 24;
      # };
    };
    # ==========================================

    # 定义测试环境的包集合
    testPkgs = import lib-core.inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };

    # 通用系统配置
    commonConfig = { config, pkgs, ... }: {
        system.stateVersion = "25.11"; 
        core.base.enable = true; # 启用基础系统配置
        
        # 硬件配置
        core.hardware.type = "vps"; # 硬件类型
        core.hardware.disk = {
            enable = true;
            # device = "/dev/vda"; # 如果是 vda 需取消注释并指定
            swapSize = 2048; # Swap 大小 (MB)
        };
        
        # 性能优化
        core.performance.tuning.enable = true;
        core.memory.mode = "aggressive"; 
        
        # 容器支持
        core.container.podman.enable = true;
        
        # 自动更新
        core.base.update = {
            enable = true;
            allowReboot = true;
        };
    };
  in
  {
    nixosConfigurations.${hostConfig.name} = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inputs = lib-core.inputs; };
      modules = [
        lib-core.nixosModules.default
        lib-core.nixosModules.kernel-xanmod # 默认使用 XanMod 内核

        commonConfig
        
        # 主机特有配置块
        ({ config, pkgs, modulesPath, lib, ... }: {
            networking.hostName = hostConfig.name;
            facter.reportPath = ./facter.json; # 硬件报告路径
            
            # 网络配置 
            core.hardware.network.single-interface = {
                enable = true;
                # 如果定义了 ipv4/ipv6 则使用静态 IP，否则默认 DHCP
                ipv4 = lib.mkIf (hostConfig ? ipv4) ({ enable = true; } // (hostConfig.ipv4 or {}));
                ipv6 = lib.mkIf (hostConfig ? ipv6) ({ enable = true; } // (hostConfig.ipv6 or {}));
                dhcp.enable = lib.mkIf (!(hostConfig ? ipv4)) true;
            };
            
            # 认证配置应用
            core.auth.root = {
                mode = "default";
                initialHashedPassword = hostConfig.auth.rootHash;
                authorizedKeys = hostConfig.auth.sshKeys;
            };
        })
        
        # 内联 VM 测试配置
        ({ config, pkgs, ... }: {
          system.build.vmTest = pkgs.testers.nixosTest {
            name = "${hostConfig.name}-inline-test";
            nodes.machine = { config, lib, ... }: {
                imports = [ 
                    lib-core.nixosModules.default 
                    lib-core.nixosModules.kernel-xanmod
                    commonConfig
                ];
                nixpkgs.pkgs = testPkgs;
                _module.args.inputs = lib-core.inputs;
                networking.hostName = "${hostConfig.name}-test";
            };
            testScript = ''
              start_all()
              machine.wait_for_unit("multi-user.target")
              machine.wait_for_unit("podman.socket")
            '';
          };
        })
      ];
    };
  };
}
```
