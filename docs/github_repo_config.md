# GitHub 仓库配置指南

本配置库采用 **Cloud-Native GitOps** 的设计理念：
- **Source of Truth**: 你的 GitHub 仓库是唯一的配置源。
- **CI/CD**: 利用 GitHub Actions 进行构建、检查和发布。
- **Auto Upgrade**: 所有的 VPS 都会定时从 GitHub 拉取最新的配置并自动升级。

为了实现这一套流程，在你 Fork 本仓库后，需要进行以下配置。

## 1. 配置权限 (GitHub Actions)

为了让 GitHub Actions 能够自动发布 Release 和提交代码（自动更新 Flake Lock），你需要赋予 Actions 读写权限。

1. 进入仓库的 **Settings** -> **Actions** -> **General**。
2. 找到 **Workflow permissions**。
3. 选择 **Read and write permissions**。
4. 点击 **Save**。

## 2. 配置 Secrets (PAT)

本仓库包含自动更新依赖 (`flake.lock`) 的工作流。为了让 Actions 能自动创建 PR 并合并，你需要配置一个 Personal Access Token (PAT)。我们**强烈推荐**使用 Fine-grained Token，因为它更安全且权限控制更精细。

### 2.1 选项 A: 使用 Fine-grained Token (推荐)
1. 前往 GitHub 的 [Developer Settings - Personal access tokens (Fine-grained tokens)](https://github.com/settings/tokens?type=beta).
2. 点击 **Generate new token**。
3. **Token name**: `Nixos Config Auto Update`。
4. **Expiration**: 建议设置长一些（如 90 天）。
5. **Repository access**: 选择 **Only select repositories**，并选中你的 `nixos-config` 仓库。
6. **Permissions** (这是关键):
   - **Contents**: `Read and write` (用于提交代码)
   - **Pull requests**: `Read and write` (用于创建和合并 PR)
   - **Workflows**: `Read and write` (允许操作工作流文件)
7. 点击 **Generate token** 并复制。

### 2.2 选项 B: 使用 Classic Token (不推荐)
如果你必须使用 Classic Token，请确保勾选 `repo` 和 `workflow` 权限。

### 2.3 添加到仓库 Secrets
1. 仓库 **Settings** -> **Secrets and variables** -> **Actions**。
2. **New repository secret**。
3. **Name**: `PAT`。
4. **Secret**: 粘贴你的 Token。
5. **Add secret**。

## 3. 分支策略与仓库安全设置 (重要)

为了遵循 GitOps 最佳实践并防止错误配置直接破坏系统，我们采用 **"Main 分支受保护，通过 PR 变更"** 的策略。

### 3.1 开启 PR 自动化与清理
1. 仓库 **Settings** -> **General**。
2. 找到 **Pull Requests** 区域。
3. 勾选 **Allow auto-merge** (允许自动合并，配合 CI 使用)。
4. 勾选 **Automatically delete head branches** (合并后自动删除临时分支)。

### 3.2 设置 Main 分支保护规则
1. 仓库 **Settings** -> **Branches**。
2. 点击 **Add branch protection rule**。
3. **Branch name pattern**: `main`。
4. 勾选以下规则：
   - [x] **Require a pull request before merging** (禁止直接 Push 到 main)。
   - [x] **Require status checks to pass before merging** (确保配置正确才能合并)。
     - 在搜索框中输入并选择: `check-configuration` (这是我们 CI 工作流中的 Job 名称)。
5. 点击 **Create**。

> **提示**: 现在你无法直接 `git push origin main` 了。你需要创建一个新分支（如 `dev` 或 `feature/xxx`），推送到远程后发起 Pull Request。


## 4. 理解工作流 (Workflows)

本仓库包含三个核心 Workflow，它们构成了自动化的基础：

### 4.1 CI (Build NixOS Configuration)
- **文件**: `.github/workflows/ci.yml`
- **触发**: Pull Request 或手动作流。
- **作用**: 检查你的配置是否合法。它会试构建 `toplevel` (系统闭包)，确保你修改配置后不会导致系统构建失败。
- **注意**: 只有通过 CI 检查的代码才建议合并到 `main` 分支。

### 4.2 Release System Images
- **文件**: `.github/workflows/release.yml`
- **触发**: 手动触发 (`workflow_dispatch`)。
- **作用**:
    1. 接收一个版本号参数 (如 `v1.0.1`)。
    2. 构建所有主机的磁盘镜像 (`diskoImages`)。
    3. 压缩并发布到 GitHub Releases。
- **用途**: 用于全新安装。当你要部署一台新机器时，运行此 Workflow，然后使用生成的链接进行一键 DD 安装。

### 4.3 Update Flake Lock
- **文件**: `.github/workflows/update-flake.yml`
- **触发**: 每天 UTC 0点 (北京时间 08:00) 或手动触发。
- **作用**:
    1. 运行 `nix flake update` 更新所有输入源（如 nixpkgs）。
    2. 如果有更新，自动提交并创建一个 Pull Request。
    3. 如果 CI 构建通过，自动合并该 PR。
- **用途**: 保持你的系统软件处于最新状态 (Bleeding Edge)。

## 5. 修改自动升级配置

如果你的 GitHub 用户名不是 `ShaoG-R`，你需要修改系统内的自动升级指向，否则你的 VPS 会一直尝试拉取原作者的仓库。

1. 打开文件 `server/vps/profiles/update/auto-upgrade.nix`。
2. 修改 `flake` 参数：
   
   ```nix
   # 修改 github:ShaoG-R/nixos-config 为 github:<你的用户名>/nixos-config
   flake = "github:<你的用户名>/nixos-config";
   ```

3. 提交并推送修改。

现在，你的 Cloud-Native NixOS 配置环境已经准备就绪！
