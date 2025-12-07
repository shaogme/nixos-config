{ 
    address, 
    prefixLength, 
    gateway, 
    enableDhcpV4 ? false, 
    nameservers ? null 
}:
(import ./common.nix ({
  inherit enableDhcpV4;
  ipv6 = { inherit address prefixLength gateway; };
} // (if nameservers != null then { inherit nameservers; } else {})))
