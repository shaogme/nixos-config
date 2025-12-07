{ config, pkgs, lib, ... }:

{
  # 启动时自动修复 GPT 分区表并扩容最后一个分区
  boot.growPartition = true;

  # 针对 Btrfs 根分区的自动扩容配置
  fileSystems."/" = {
    autoResize = true;
    # 确保挂载选项中有 compress 等原有配置，这里不需要重复写 mountOptions，
    # 因为 Disko 中已经定义了，这里主要是追加 autoResize 属性。
  };

  # 确保必要的工具在系统路径中 (cloud-utils 包含 growpart)
  environment.systemPackages = [ pkgs.cloud-utils ];
}