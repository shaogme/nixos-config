# GitHub 仓库配置指南

本配置库采用 **Cloud-Native GitOps** 的设计理念：
- **Source of Truth**: 你的 GitHub 仓库是唯一的配置源。
- **CI/CD**: 利用 GitHub Actions 进行构建、检查和发布。
- **Auto Upgrade**: 所有的 VPS 都会定时从 GitHub 拉取最新的配置并自动升级。

为了实现这一套流程，在你 Fork 本仓库后，需要进行以下配置。

## 1. 配置权限 (GitHub Actions)

为了让 GitHub Actions 能够自动发布 Release 和提交代码（自动更新 Flake Lock），你需要赋予 Actions 默认的读写权限。

1. 进入仓库的 **Settings** -> **Actions** -> **General**。
2. 找到 **Workflow permissions**。
3. 选择 **Read and write permissions**。
4. 点击 **Save**。

## 2. 配置 Secrets (PAT)

本仓库包含复杂的自动化工作流（如 `update-flake.yml` 和 `sync-no-lock-update.yml`），它们涉及自动创建 PR、合并 PR 以及跨工作流触发。为了支持这些操作，你需要配置一个具有更高权限的 Personal Access Token (PAT)。

**注意**：由于 GitHub Actions 的安全限制，默认的 `GITHUB_TOKEN` 无法触发后续的工作流（例如自动合并 PR 后触发 CI）。因此，必须使用 PAT。

### 2.1 选项 A: 使用 Fine-grained Token (强烈推荐)

Fine-grained Token 更安全，且支持精细化权限控制。

1. 前往 GitHub 的 [Developer Settings - Personal access tokens (Fine-grained tokens)](https://github.com/settings/tokens?type=beta).
2. 点击 **Generate new token**。
3. **Token name**: `Nixos Config Auto Update`。
4. **Expiration**: 建议设置长一些（如 90 天或更久）。
5. **Repository access**: 选择 **Only select repositories**，并选中你的 `nixos-config` 仓库。
6. **Permissions (Repository permissions)** - 请务必准确勾选以下权限：
   - **Actions**: `Read and write` (用于管理和触发 Actions 运行)
   - **Contents**: `Read and write` (用于提交代码、更新 Lock 文件)
   - **Pull requests**: `Read and write` (用于自动创建和合并 PR)
   - **Workflows**: `Read and write` (用于修改或操作工作流文件)
7. 点击 **Generate token** 并复制。

### 2.2 选项 B: 使用 Classic Token
如果你必须使用 Classic Token，请确保勾选以下 Scopes：
- [x] **repo** (包含所有仓库权限)
- [x] **workflow** (允许更新 GitHub Action 工作流)

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
     - 在搜索框中输入并选择: `ci-success` (这是 CI 工作流最后的汇总 Job 状态)。
   - [x] **Do not allow bypassing the above settings** (可选，强制执行)。
5. 点击 **Create**。

> **提示**: 现在你无法直接 `git push origin main` 了。你需要创建一个新分支（如 `dev` 或 `feature/xxx`），推送到远程后发起 Pull Request。

## 4. 理解工作流 (Workflows)

本仓库包含几个核心 Workflow，它们构成了自动化的基础：

### 4.1 CI (Build & Test)
- **文件**: `.github/workflows/ci.yml`
- **触发**: Pull Request (针对 `main` 分支)。
- **动态矩阵**: 自动扫描 `vps/` 目录下所有包含 `flake.nix` 的子目录作为测试对象。
- **作用**: 
    - 检查 Flake 语法。
    - 运行 VM 集成测试 (测试多种内核配置)。
    - 验证 VPS 静态构建 (自动发现所有主机)。
    - 运行 VPS 专用的 VM 测试 (自动发现所有主机)。
- **注意**: 这是 `main` 分支的守门员，只有 CI 通过 (`ci-success`) 才能合并。

### 4.2 Auto Update Flake Lock
- **文件**: `.github/workflows/auto-update-flake.yml` (调度) & `update-flake.yml` (执行)
- **触发**: 每天 UTC 19:40 (北京时间 03:40) 或手动。
- **作用**:
    1. 定时检查上游依赖（如 `nixpkgs`）更新。
    2. 自动遍历 `vps/` 下所有主机并更新其 `flake.lock`。
    3. 如果有更新，创建 PR。
    4. 如果 CI 测试通过，自动合并 PR。
- **用途**: 保持系统处于 Bleeding Edge 状态。

### 4.3 Release System Images
- **文件**: `.github/workflows/release.yml`
- **触发**: 手动触发 (`workflow_dispatch`)。
- **作用**: 自动构建 `vps/` 下所有主机的磁盘镜像，并发布到 GitHub Releases。无需手动维护发布列表。
- **用途**: 用于全新安装服务器。

### 4.4 Sync No-Lock-Update
- **文件**: `.github/workflows/sync-no-lock-update.yml`
- **触发**: 推送到 `no-lock-update` 分支。
- **作用**: 开发辅助流程，用于将不带 Lock 变更的提交同步到 `pre-release` 分支进行测试。

## 5. 修改自动升级配置

如果你的 GitHub 用户名不是 `ShaoG-R`，你需要修改系统内的自动升级指向，否则你的 VPS 会一直尝试拉取原作者的仓库。

1. 打开文件 `server/vps/profiles/update/auto-upgrade.nix` (如果文件位置不同，请查找定义 `system.autoUpgrade` 的位置)。
2. 修改 `flake` 参数：
   
   ```nix
   # 修改 github:ShaoG-R/nixos-config 为 github:<你的用户名>/nixos-config
   flake = "github:<你的用户名>/nixos-config";
   ```

3. 提交并推送修改。

现在，你的 Cloud-Native NixOS 配置环境已经准备就绪！
