{ 
    ipv4 ? null, 
    ipv6 ? null, 
    enableDhcpV4 ? false, 
    enableDhcpV6 ? false, 
    nameservers ? [ 
        "1.1.1.1" 
        "8.8.8.8" 
        "2606:4700:4700::1111" 
        "2001:4860:4860::8888" 
    ] 
}:
{ lib, config, ... }:
let
  hasIpv4 = ipv4 != null;
  hasIpv6 = ipv6 != null;
  isDhcp = (!hasIpv4 && !hasIpv6) || enableDhcpV4 || enableDhcpV6;
in
{
  networking = {
    inherit nameservers;
    networkmanager.enable = false;
    
    # true (默认值)：启用 "Predictable Network Interface Names"。系统会根据网卡的物理位置（PCI插槽）命名，如 ens18, enp3s0。
    # false：禁用该功能。内核会按照枚举顺序命名网卡，对于单网卡的 VPS，这几乎 100% 会是 eth0。
    usePredictableInterfaceNames = false;
    
    interfaces.eth0 = {
      useDHCP = isDhcp;
      ipv4.addresses = lib.mkIf hasIpv4 [ { address = ipv4.address; prefixLength = ipv4.prefixLength; } ];
      ipv6.addresses = lib.mkIf hasIpv6 [ { address = ipv6.address; prefixLength = ipv6.prefixLength; } ];
    };
    
    defaultGateway = lib.mkIf (hasIpv4 && ipv4 ? gateway) ipv4.gateway;
    defaultGateway6 = lib.mkIf (hasIpv6 && ipv6 ? gateway) { address = ipv6.gateway; interface = "eth0"; };
  };
}
