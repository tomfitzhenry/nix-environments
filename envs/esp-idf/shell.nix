# ESP-IDF development environment.
#
# Returns { env, idf, idf-riscv }:
#   env       a devShell with `idf.py` and the full toolchain set, for
#             `nix develop` / building projects interactively;
#   idf       the ESP-IDF package with Xtensa toolchains only (ESP32,
#             ESP32-S2, ESP32-S3) — small enough to import from another
#             project's derivation to build firmware non-interactively;
#   idf-riscv same, for RISC-V targets (ESP32-C3/C6/H2/P4).
#
# The pinned ESP-IDF version can be overridden:
#   import ./envs/esp-idf/shell.nix { pkgs = ...; espIdfRev = "v5.5.5"; espIdfSha256 = "..."; }
{
  pkgs ? import <nixpkgs> { },
  espIdfRev ? "v6.0.2",
  espIdfSha256 ? "sha256-dVdJ+aUjMJyWoz+wOwA0R6XH3JRq0VBpC1sAH/aLECs=",
}:

let
  esp-idf-full = pkgs.callPackage ./esp-idf.nix {
    rev = espIdfRev;
    sha256 = espIdfSha256;
  };

  idf = esp-idf-full.override {
    toolsToInclude = [
      "xtensa-esp-elf"
      "esp32ulp-elf"
      "openocd-esp32"
      "xtensa-esp-elf-gdb"
      "esp-rom-elfs"
    ];
  };

  idf-riscv = esp-idf-full.override {
    toolsToInclude = [
      "riscv32-esp-elf"
      "openocd-esp32"
      "riscv32-esp-elf-gdb"
      "esp-rom-elfs"
    ];
  };
in
{
  env = pkgs.mkShell {
    packages = [ esp-idf-full ];
  };

  inherit idf idf-riscv;
}
