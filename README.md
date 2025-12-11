# NixOS Configuration (Cloud-Native)

> **Note**: 本仓库是个人配置文件库。如果你正在寻找一个开箱即用的 NixOS 配置模板，请使用 [NixOS Config Template](https://github.com/ShaoG-R/nixos-config-template)。

这是一个基于 **GitOps** 理念设计的 NixOS 配置仓库。它旨在实现：
1. **完全的所有权**: 你拥有自己的 Git 仓库作为唯一真理源 (Source of Truth)。
2. **云端构建**: 使用 GitHub Actions 构建系统镜像和验证配置，无需本地强大的机器。
3. **自动交付**: 每日自动更新依赖，VPS 自动拉取最新配置并平滑升级。

---

## 快速开始

### 1. 初始化你的仓库

要建立你自己的配置中心，请先 Fork 本仓库，并完成必要的 GitHub 设置（如 Token 配置）。

👉 **[GitHub 仓库配置指南](docs/github_repo_config.md)** *(Start Here)*

### 2. 添加/修改主机

配置好仓库后，你可以在 `server/vps/` 下定义你自己的主机。我们推荐根据是否有 DHCP 环境来选择不同的模板。

👉 **[如何创建新的主机配置](docs/create_your_own_host.md)**

---

## 全新安装指南

当你添加了新主机并推送到 GitHub 后，可以通过以下方式进行安装。

### 方式一：云端构建 + 一键 DD (推荐)

最简单的安装方式。你不需要准备任何 Nix 环境。

1. 在 GitHub Actions 页面手动运行 **Release System Images** 工作流。
2. 等待构建完成，在 Releases 页面获取你的主机镜像链接 (`.tar.zst`)。
3. 登录目标 VPS，执行通用 DD 脚本：

```bash
# 下载重装脚本 (以 bin456789/reinstall 为例)
curl -O https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh || wget -O ${_##*/} $_

# 替换为你的 Release 链接
export IMAGE_URL="https://github.com/<你的用户名>/nixos-config/releases/latest/download/<主机名>.tar.zst"

# 执行 DD
bash reinstall.sh dd --img "$IMAGE_URL"
```

### 方式二：Nixos-Anywhere (本地部署)

如果你有本地 Nix 环境且能 SSH 到目标机器：

```bash
# 直接使用 flake 部署
nix run github:nix-community/nixos-anywhere -- \
  --flake .#<主机名> \
  --target-host root@<IP地址> \
  --build-on local
```

---

## 日常维护

### 自动升级
默认情况下，所有部署的主机都会在 **每天凌晨 04:00** 自动检查你的 GitHub 仓库 (`main` 分支)。如果有新提交（无论是你手动修改的，还是 CI 自动更新的依赖），系统都会自动下载并应用更新。

### 手动触发更新
如果你不想等待自动更新，可以在 VPS 上直接运行：

```bash
nixos-rebuild switch --flake github:<你的用户名>/nixos-config
```

### 依赖更新
GitHub Actions (`update-flake.yml`) 会每天自动检查并更新 `flake.lock`，并通过 CI 测试后自动合并。你只需要坐享其成，或者处理 CI 失败的构建。

