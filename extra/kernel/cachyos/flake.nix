{
  description = "CachyOS Kernel Module with BBRv3 Network Optimization";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";
  };

  outputs = { self, nixpkgs, nix-cachyos-kernel, ... }: {
    nixosModules = {
      default = { pkgs, lib, config, ... }: {
        imports = [
          ./default.nix
        ];

        nixpkgs.overlays = [
          nix-cachyos-kernel.overlays.pinned
        ];

        nix.settings = {
          substituters = [
            "https://attic.xuyh0120.win/lantian"
            "https://cache.garnix.io"
          ];
          trusted-public-keys = [
            "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
            "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
          ];
        };
      };
    };
    
    overlays.default = nix-cachyos-kernel.overlays.default;
    
    lib.makeTestPkgs = system: import nixpkgs {
      inherit system;
      config.allowUnfree = true;
      overlays = [ nix-cachyos-kernel.overlays.default ];
    };
  };
}
