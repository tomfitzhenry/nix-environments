# ESP-IDF

Development environment for [ESP-IDF](https://github.com/espressif/esp-idf) —
the Espressif IoT development framework for ESP32-family chips.

Provides `idf.py`, the toolchains for every supported target, and the
Python environment ESP-IDF expects.

## Usage

```sh
nix develop ~/src/nix-environments#esp-idf   # or: nix develop path:~/src/nix-environments#esp-idf
idf.py set-target esp32s3
idf.py build
```

To build firmware non-interactively from another project, import this
environment and use its packages:

```nix
let env = import ~/src/nix-environments/envs/esp-idf/shell.nix { inherit pkgs; };
in pkgs.stdenv.mkDerivation {
  buildInputs = [ env.idf ];   # Xtensa targets (ESP32/ESP32-S2/S3)
  # buildInputs = [ env.idf-riscv ];  # RISC-V targets (ESP32-C3/C6/H2/P4)
  ...
}
```

## ESP-IDF version

Defaults to the latest stable release (currently v6.0.2), overridable:

```nix
import ~/src/nix-environments/envs/esp-idf/shell.nix {
  inherit pkgs;
  espIdfRev = "v5.5.5";
  espIdfSha256 = "...";  # placeholder hash; the build error prints the real one
}
```

## Bumping ESP-IDF

1. Change `rev`/`sha256` defaults in `esp-idf.nix` (or pass them in).
   The fetch includes git submodules, so use a placeholder sha256 and
   read the `got:` from the resulting error.
2. Regenerate the Python pins: `./update-python-packages.py > python-packages.nix`
   (pins come from the ESP-IDF checkout's own requirements and
   constraints files, so this is mechanical).
3. Build something to verify.

## Background

The toolchain derivations are driven by the `tools/tools.json` manifest
that ships with each ESP-IDF release: per-platform tarball URLs and
hashes come from Espressif, so toolchains track the pinned ESP-IDF
version automatically.

Adapted from [mirrexagon/nixpkgs-esp-dev](https://github.com/mirrexagon/nixpkgs-esp-dev)
(CC0-1.0), rev 5287d6e1, with the following changes:

- ESP-IDF v6.0.2 (upstream default was v5.5.2).
- esptool 5.x no longer depends on the `ecdsa` package, so the
  insecure-package exemption the upstream overlay needed is gone.
- Python pins are generated (`update-python-packages.py`) instead of
  hand-snapshotted.
- `esp-idf-size` and `tree-sitter(-c)` come from nixpkgs, which now has
  versions satisfying ESP-IDF 6.0's constraints.
