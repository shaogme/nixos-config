# 如何检测主机是否支持 DHCP

本文档介绍了几种检测主机网络环境是否支持 DHCP 分配 IP 的方法，通过这些方法，你可以在不破坏现有网络配置的情况下确认是否可以使用 DHCP 方案。

## 方案一：使用 dhcpcd 的测试模式

`dhcpcd` 是一个常见的 DHCP 客户端，它有一个 `-T` (`--test`) 参数，会执行完整的 DHCP 握手过程（发送 Discover，接收 Offer），打印结果，但 **绝对不会修改系统的 IP 地址或路由表**，也不会后台驻留。

1. **进入临时 Shell (如果未安装 dhcpcd)**：
   ```bash
   nix-shell -p dhcpcd
   ```

2. **执行测试命令**：
   假设你的网卡名称是 `eth0` (请通过 `ip addr` 确认)：
   ```bash
   sudo dhcpcd -T eth0
   ```

   或者使用 `-4` 强制仅测试 IPv4：
   ```bash
   sudo dhcpcd -4 -T eth0
   ```

3. **判断结果**：
   - **支持 DHCP**：你会看到类似 `received OFFER of x.x.x.x from x.x.x.x` 的日志，最后显示 `forked to background` (在测试模式下并不会真的 fork，只是表示流程成功)。
   - **不支持 DHCP**：命令会超时，显示 `timed out`。

## 方案二：使用 nmap 发送广播探测

`nmap` 有一个专门的脚本 `broadcast-dhcp-discover`，可以模拟发送 DHCP 请求并监听回应，这完全是一个用户态的探测行为，对网卡配置无任何影响。

1. **使用 nix-shell 运行 nmap**：
   ```bash
   nix-shell -p nmap
   ```

2. **执行探测**：
   ```bash
   sudo nmap --script broadcast-dhcp-discover -e eth0
   ```
   *(将 `eth0` 替换为你的网卡名称)*

3. **判断结果**：
   - **支持 DHCP**：输出中会包含 `Response 1 of 1`，并列出 DHCP 服务器的 IP、提供的 IP 地址、子网掩码等详细信息。
   - **不支持 DHCP**：脚本执行完毕后没有任何关于 DHCP 的输出。
