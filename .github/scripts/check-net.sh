#!/usr/bin/env nix-shell
#!nix-shell -i bash -p jq iproute2

set -e

# 获取拥有默认路由的主网卡接口名称
DEFAULT_IF=$(ip -j route show default | jq -r '.[0].dev')

if [ -z "$DEFAULT_IF" ]; then
    # 备选方案：如果找不到默认路由，尝试直接取第一个非lo接口
    DEFAULT_IF=$(ip -j link show | jq -r '.[] | select(.ifname != "lo") | .ifname' | head -n 1)
fi

if [ -z "$DEFAULT_IF" ]; then
    echo "错误: 未找到有效网卡接口。"
    exit 1
fi

# ==========================================
# IPv4 检测逻辑
# ==========================================

# 提取第一个 Global Scope 的 IPv4 对象 (使用 -c 保证单行 JSON，避免 head 截断问题)
IPV4_JSON=$(ip -j -4 addr show dev "$DEFAULT_IF" | jq -c '.[0].addr_info | map(select(.scope == "global")) | .[0]')

if [ "$IPV4_JSON" != "null" ] && [ -n "$IPV4_JSON" ]; then
    # 提取生存期
    V4_LIFETIME=$(echo "$IPV4_JSON" | jq -r '.valid_life_time')

    # 判定标准：字符串 "forever" 或者 数值 4294967295 (UInt32 Max) 都视为静态
    if [ "$V4_LIFETIME" == "forever" ] || [ "$V4_LIFETIME" == "4294967295" ]; then
        V4_ADDR=$(echo "$IPV4_JSON" | jq -r '.local')
        V4_PREFIX=$(echo "$IPV4_JSON" | jq -r '.prefixlen')
        # 获取网关，如果为空则留空
        V4_GW=$(ip -j -4 route show default | jq -r '.[0].gateway // empty')
        
        # 如果依然没找到网关（也就是 output 为空），设置默认值或报错
        [ -z "$V4_GW" ] && V4_GW=""

        echo "ipv4 = {"
        echo "  address = \"$V4_ADDR\";"
        echo "  prefixLength = $V4_PREFIX;"
        echo "  gateway = \"$V4_GW\";"
        echo "};"
    else
        echo "ipv4是DHCP获取 (剩余租约: ${V4_LIFETIME}秒)"
    fi
else
    echo "未检测到 IPv4 地址"
fi

# ==========================================
# IPv6 检测逻辑
# ==========================================

# 提取第一个 Global Scope 的 IPv6 对象
IPV6_JSON=$(ip -j -6 addr show dev "$DEFAULT_IF" | jq -c '.[0].addr_info | map(select(.scope == "global")) | .[0]')

if [ "$IPV6_JSON" != "null" ] && [ -n "$IPV6_JSON" ]; then
    V6_LIFETIME=$(echo "$IPV6_JSON" | jq -r '.valid_life_time')
    
    # 某些云环境 IPv6 也是 4294967295
    if [ "$V6_LIFETIME" == "forever" ] || [ "$V6_LIFETIME" == "4294967295" ]; then
        V6_ADDR=$(echo "$IPV6_JSON" | jq -r '.local')
        V6_PREFIX=$(echo "$IPV6_JSON" | jq -r '.prefixlen')
        V6_GW=$(ip -j -6 route show default | jq -r '.[0].gateway // empty')

        # 容错处理
        [ -z "$V6_GW" ] && V6_GW=""

        echo "ipv6 = {"
        echo "  address = \"$V6_ADDR\";"
        echo "  prefixLength = $V6_PREFIX;"
        echo "  gateway = \"$V6_GW\";"
        echo "};"
    else
        echo "ipv6是DHCPv6或SLAAC获取 (剩余租约: ${V6_LIFETIME}秒)"
    fi
else
    echo "未检测到 IPv6 全局地址"
fi