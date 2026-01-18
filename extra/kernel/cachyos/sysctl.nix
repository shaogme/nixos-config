# 共享的 BBRv3 网络优化 sysctl 配置
# 被 kernel/cachyos 使用
{
  # --- 核心拥塞控制与队列管理 ---
  
  # 启用 BBR (在 CachyOS 内核中，这将激活 BBRv3)
  "net.ipv4.tcp_congestion_control" = "bbr";
  
  # 队列管理算法：建议使用 CAKE (Common Applications Kept Enhanced)
  # 它是 fq_codel 的继任者，能更好地处理 Bufferbloat，与 BBRv3 配合极佳
  "net.core.default_qdisc" = "cake";

  # --- TCP 窗口与缓冲区 (针对现代千兆/万兆网络) ---
  
  # 增加 TCP 读写缓冲区上限 (单位: 字节)
  # 下面的值设为 16MB/32MB，适合大多数高带宽场景
  "net.core.rmem_max" = 16777216;
  "net.core.wmem_max" = 16777216;
  "net.ipv4.tcp_rmem" = "4096 87380 16777216";
  "net.ipv4.tcp_wmem" = "4096 65536 16777216";
  
  # 增加连接追踪表大小 (防止高并发下丢包)
  "net.netfilter.nf_conntrack_max" = 1048576;
  
  # --- 低延迟优化 ---
  
  # 开启 TCP Fast Open (减少握手延迟)
  # 3 = 允许作为客户端和服务器使用 TFO
  "net.ipv4.tcp_fastopen" = 3;
  
  # 禁用空闲后的慢启动
  # 默认情况下，TCP 在空闲一段时间后会重置拥塞窗口(cwnd)，这会降低突发流量的速度
  # 设置为 0 可以保持窗口大小，这对 HTTP/2 和长连接非常重要
  "net.ipv4.tcp_slow_start_after_idle" = 0;
  
  # 降低 tcp_notsent_lowat
  # 能够减少本地缓冲区中的未发送数据，降低 Head-of-line blocking，让 BBR 能够更精确地控制发包节奏
  "net.ipv4.tcp_notsent_lowat" = 16384;

  # --- ECN (显式拥塞通知) ---
  
  # BBRv3 对 ECN 的处理比 v1 更好。在丢包发生前利用 ECN 信号降低速率。
  # 1 = 启用 ECN (如果对方支持)
  "net.ipv4.tcp_ecn" = 1;
  
  # --- 其他高并发优化 ---
  
  # 增加半连接队列长度 (防止 SYN Flood 攻击或高并发连接丢失)
  "net.ipv4.tcp_max_syn_backlog" = 8192;
  # 增加全连接队列长度
  "net.core.somaxconn" = 8192;
  
  # 快速回收 TIME_WAIT 状态的 socket (注意：tw_recycle 已在旧版内核废弃，不要开启)
  # 开启 tw_reuse 允许重用 TIME_WAIT socket
  "net.ipv4.tcp_tw_reuse" = 1;
  
  # 缩短 Keepalive 探测时间 (默认 2 小时太长了，改为 5 分钟)
  "net.ipv4.tcp_keepalive_time" = 300;
  "net.ipv4.tcp_keepalive_intvl" = 60;
  "net.ipv4.tcp_keepalive_probes" = 5;
}
