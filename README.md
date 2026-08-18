# Nix-environments

Repository to maintain out-of-tree shell.nix files.

For some projects it is non-trivial to get a minimal develop environment that work with Nix/NixOS.
The purpose of this repository is to share shell.nix expression that help to get started with those projects.
The goal of the project is not to build or package those projects (which is often even harder)
but to document the build requirements.

What environments should include:

- dependencies to build, develop or test the project

What environments should **not** include:

- opinionated, user-specific dependencies for example editors or favorite debugging tools

## Current available environments

| Name                                            | Attribute             |
|-------------------------------------------------|-----------------------|
| [Arduino](envs/arduino)                         | `arduino`             |
| [cc2538-bsl](envs/cc2538-bsl)                   | `cc2538-bsl`          |
| [ESP-IDF](envs/esp-idf)                         | `esp-idf`             |
| [Jruby](envs/jruby)                             | `jruby`               |
| [Firefox](envs/firefox)                         | `firefox`             |
| [Git](envs/git)                                 | `git`                 |
| [Github Pages](envs/github-pages)               | `github-pages`        |
| [Homeassistant](envs/home-assistant)            | `home-assistant`      |
| [Nannou](envs/nannou)                           | `nannou`              |
| [Phoronix test suite](envs/phoronix-test-suite) | `phoronix-test-suite` |
| [OpenWRT](envs/openwrt)                         | `openwrt`             |
| [SPEC benchmark](envs/spec-benchmark)           | `spec-benchmark`      |
| [Yocto](envs/yocto)                             | `yocto`               |
| [Xilinx vitis](envs/xilinx-vitis)               | `xilinx-vitis`        |
| [InfiniSim](envs/infinisim)                     | `infinisim`           |
| [Ladybird](envs/ladybird)                       | `ladybird`            |
| [buildroot](envs/buildroot)                     | `buildroot`           |
| [zmk](envs/zmk)                                 | `zmk`                 |

## How to use

### Stable Nix

All environments referenced in [default.nix](default.nix) can be loaded by running nix-shell like that:

```console
$ nix-shell https://github.com/nix-community/nix-environments/archive/master.tar.gz -A PROJECT_NAME
```

for example openwrt:

```console
$ nix-shell https://github.com/nix-community/nix-environments/archive/master.tar.gz -A openwrt
```

To apply custom modification one can also import environments into their own `shell.nix` files and
override them. Note that this approach does currently not work for buildFHSEnv-based environments!

```nix
{ pkgs ? import <nixpkgs> {} }:
let
  envs = (import (builtins.fetchTarball {
    url = "https://github.com/nix-community/nix-environments/archive/master.tar.gz";
  }));
  phoronix = envs.phoronix-test-suite { inherit pkgs; };
in (phoronix.overrideAttrs (old: {
  # this will append python to the existing dependencies
  buildInputs = old.buildInputs ++ [ pkgs.python3 ];
}))
```

To provide additional packages to buildFHSEnv-based environments you can use the `extraPkgs` attribute.
For the Yocto environment, you can use `callPackage` to override `stdenv` or `python3`:

```nix
{pkgs ? import <nixpkgs> {}}: 
let
  yoctoEnv = pkgs.callPackage ((builtins.fetchTarball {
      url = "https://github.com/nix-community/nix-environments/archive/master.tar.gz";
    }) + "/envs/yocto/shell.nix") {
    stdenv = pkgs.gcc11Stdenv;  # Use GCC 11 for older Yocto releases
    python3 = pkgs.python311;   # Use Python 3.11 for older Yocto releases
    extraPkgs = [pkgs.hello];
  };
in
  yoctoEnv
```

For other environments, you can still use the traditional import method:

```nix
{pkgs ? import <nixpkgs> {}}: 
let
  buildrootEnv = ((builtins.fetchTarball {
      url = "https://github.com/nix-community/nix-environments/archive/master.tar.gz";
    })
    + "/envs/buildroot/shell.nix");
in
  (import buildrootEnv) {
    inherit pkgs;
    extraPkgs = [pkgs.hello];
  }
```

### Nix Flakes

Nix-environments are also available as Flake outputs. Flakes are an [experimental new way to handle Nix expressions](https://wiki.nixos.org/wiki/Flakes).

For dropping into the environment for the OpenWRT project, just run:

```
nix develop --no-write-lock-file github:nix-community/nix-environments#openwrt
```

The last part is a flake URL and is an abbreviation of `github:nix-community/nix-environments#devShells.SYSTEM.openwrt`, where `SYSTEM` is your current system, e.g. `x86_64-linux`.

You can also use these environments in your own flake and extend them:

```nix
{
  inputs.nix-environments.url = "github:nix-community/nix-environments";

  outputs = { self, nixpkgs, nix-environments }: let
    # Replace this string with your actual system, e.g. "x86_64-linux"
    system = "SYSTEM";
  in {
    devShell.${system} = let
        pkgs = import nixpkgs { inherit system; };
      in nix-environments.devShells.${system}.phoronix-test-suite.overrideAttrs (old: {
        buildInputs = old.buildInputs ++ [ pkgs.python3 ];
      });
  };
}
```

For the Yocto environment, you can also override parameters like `stdenv` and `python3`:

```nix
{
  inputs.nix-environments.url = "github:nix-community/nix-environments";

  outputs = { self, nixpkgs, nix-environments }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };
  in {
    devShells.${system}.default = 
      nix-environments.devShells.${system}.yocto.override {
        stdenv = pkgs.gcc11Stdenv;
        python3 = pkgs.python311;
      };
  };
}
```

## Similar projects

- generates generic templates for different languages: https://github.com/kampka/nixify
- also templates for different languages: https://github.com/mrVanDalo/nix-shell-mix
- templates for flakes: https://github.com/NixOS/templates
