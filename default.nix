{ pkgs ? import <nixpkgs> {}
, pkgsUnfree ? import <nixpkgs> { config = { allowUnfree = true; }; }
}: {
  arduino = import ./envs/arduino/shell.nix { inherit pkgs; };
  buildroot = import ./envs/buildroot/shell.nix { inherit pkgs; };
  cc2538-bsl = import ./envs/cc2538-bsl/shell.nix { inherit pkgs; };
  coreboot = import ./envs/coreboot/shell.nix { inherit pkgs; };
  esp-idf = (import ./envs/esp-idf/shell.nix { inherit pkgs; }).env;
  firefox = import ./envs/firefox/shell.nix { inherit pkgs; };
  infinisim = import ./envs/infinisim/shell.nix { inherit pkgs; };
  git = import ./envs/git/shell.nix { inherit pkgs; };
  github-pages = import ./envs/github-pages/shell.nix { inherit pkgs; };
  home-assistant = import ./envs/home-assistant/shell.nix { inherit pkgs; };
  jruby = import ./envs/jruby/shell.nix { inherit pkgs; };
  ladybird = import ./envs/ladybird/shell.nix { inherit pkgs; };
  nannou = import ./envs/nannou/shell.nix { inherit pkgs; };
  openwrt = (import ./envs/openwrt/shell.nix { inherit pkgs; }).env;
  openwrt-ci = import ./envs/openwrt/shell.nix { inherit pkgs; };
  phoronix-test-suite = import ./envs/phoronix-test-suite/shell.nix { inherit pkgs; };
  spec-benchmark = import ./envs/spec-benchmark/shell.nix { inherit pkgs; };
  xilinx-vitis = import ./envs/xilinx-vitis/shell.nix { inherit pkgs; };
  yocto = pkgs.callPackage ./envs/yocto/shell.nix { };
  zmk = import ./envs/zmk/shell.nix { inherit pkgs; };
}
