{ pkgs ? import <nixpkgs> { }
, extraPkgs ? [ ]
, shellHookPost ? ""
}:

let
  # Both crossgcc toolchains produce iasl and nasm, so use buildEnv
  # with ignoreCollisions to combine them (the colliding tools are equivalent).
  coreboot-toolchain-combined = pkgs.buildEnv {
    name = "coreboot-toolchain-combined";
    paths = [ pkgs.coreboot-toolchain.i386 pkgs.coreboot-toolchain.x64 ];
    pathsToLink = [ "/bin" ];
    ignoreCollisions = true;
  };

  fhs = pkgs.buildFHSEnvBubblewrap {
    name = "coreboot-fhs";
    targetPkgs = pkgs: with pkgs; [
      acpica-tools          # provides iasl (ACPI compiler)
      bc
      binutils
      bison
      bzip2
      coreboot-toolchain-combined
      curl
      flex
      gcc
      git
      gnat14                # Ada compiler, required by EDK2 CryptoPkg/OpensslLib
      gnumake
      imagemagick           # required by EDK2 build
      ncurses
      nasm                  # x86 assembler, required by EDK2
      openssl               # required by EDK2 CryptoPkg
      patch
      perl
      pkg-config
      python3
      qemu                  # for testing firmware images
      unzip
      util-linux            # provides libuuid (uuid-dev), required by EDK2 build
      wget
      which
      xz
      zlib
      zstd
    ] ++ extraPkgs;
    multiPkgs = ps: [ ];
    extraOutputsToInstall = [ "dev" ];
    profile = ''
      # Prevent conflict with libpayload/Makefile.payload
      unset STRIP

      # Tell coreboot to use the cross-compilers in PATH rather
      # than trying to build its own toolchain (make crossgcc).
      # Setting XGCCPATH to the toolchain dir lets coreboot find
      # both i386-elf-* and x86_64-elf-* tools.
      export XGCCPATH=${coreboot-toolchain-combined}/bin

      # Wrapper around make that patches EDK2's toolchain before building.
      # The mrchromebox edk2 fork defaults both IA32 and X64 to the host gcc.
      # We override them to coreboot cross-compilers (i386-elf-*, x86_64-elf-*).
      # Must be a function (not a one-shot check) because the edk2 workspace
      # may not exist yet when the shell starts — it's cloned by make itself.
      make() {
        local cbt="payloads/external/edk2/workspace/mrchromebox/BaseTools/Conf/tools_def.template"
        if [ -f "$cbt" ] && ! grep -q 'DEFINE GCC_IA32_PREFIX *= *i386-elf-' "$cbt" 2>/dev/null; then
          sed -i \
            -e 's|DEFINE GCC5_IA32_PREFIX *=.*|DEFINE GCC5_IA32_PREFIX = i386-elf-|' \
            -e 's|DEFINE GCC5_X64_PREFIX *=.*|DEFINE GCC5_X64_PREFIX = x86_64-elf-|' \
            -e 's|DEFINE GCC_IA32_PREFIX *=.*|DEFINE GCC_IA32_PREFIX = i386-elf-|' \
            -e 's|DEFINE GCC_X64_PREFIX *=.*|DEFINE GCC_X64_PREFIX = x86_64-elf-|' \
            "$cbt"
          echo "coreboot: patched EDK2 toolchain for cross-compilers"
        fi
        command make "$@"
      }

      ${shellHookPost}
    '';
  };
in
fhs.env
