{ 
    ipv4, 
    ipv6, 
    nameservers ? null 
}:
(import ./common.nix ({
  inherit ipv4 ipv6;
} // (if nameservers != null then { inherit nameservers; } else {})))
