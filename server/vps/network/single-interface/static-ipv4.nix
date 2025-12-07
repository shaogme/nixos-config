{ 
    address, 
    prefixLength, 
    gateway, 
    enableDhcpV6 ? false, 
    nameservers ? null 
}:
(import ./common.nix ({
  inherit enableDhcpV6;
  ipv4 = { inherit address prefixLength gateway; };
} // (if nameservers != null then { inherit nameservers; } else {})))
