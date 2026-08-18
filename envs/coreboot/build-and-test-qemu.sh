#!/usr/bin/env bash
# Build coreboot + EDK2 for emulation/qemu-q35 and test in QEMU.
# Requires: Nix with the nix-environments repo available.
# Usage:
#   ./envs/coreboot/build-and-test-qemu.sh              # build and test
#   ./envs/coreboot/build-and-test-qemu.sh --build-only # just build
#   ./envs/coreboot/build-and-test-qemu.sh --test-only  # just test (ROM must exist)
#   COREBOOT_DIR=/path/to/coreboot ./envs/coreboot/build-and-test-qemu.sh

set -euo pipefail

BUILD_ONLY=false
TEST_ONLY=false

case "${1:-}" in
  --build-only) BUILD_ONLY=true ;;
  --test-only)  TEST_ONLY=true ;;
  "")           ;; # do both
  *) echo "Usage: $0 [--build-only|--test-only]" >&2; exit 1 ;;
esac

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
COREBOOT_DIR="${COREBOOT_DIR:-$HOME/coreboot}"
ROM="$COREBOOT_DIR/build/coreboot.rom"

export NIX_PATH="${NIX_PATH:-nixpkgs=https://github.com/NixOS/nixpkgs/archive/nixpkgs-unstable.tar.gz}"

# ── Build ──────────────────────────────────────────────────────────────

if ! $TEST_ONLY; then
  if [ ! -d "$COREBOOT_DIR" ]; then
    echo "=== Cloning coreboot ==="
    git clone --depth 1 https://review.coreboot.org/coreboot "$COREBOOT_DIR"
  fi

  # Write the build script with resolved paths substituted
  cat > /tmp/coreboot-build.sh << BUILDSCRIPT
set -euo pipefail
cd '$COREBOOT_DIR'

echo "=== Configuring coreboot + EDK2 for QEMU Q35 ==="
rm -rf build/
cp configs/config.emulation_qemu_x86_q35_smm_tseg .config
echo "CONFIG_PAYLOAD_EDK2=y" >> .config

make olddefconfig

# On a fresh clone the edk2 workspace might not exist yet. Run a target
# that clones it so the make wrapper can patch tools_def.template before
# the actual EDK2 build starts.
make -C payloads/external/edk2 fetch 2>/dev/null || true

make -j"\$(nproc)"
BUILDSCRIPT

  echo "bash /tmp/coreboot-build.sh; echo BUILD_EXIT=\$? > /tmp/build-exit" | \
    nix-shell "$REPO_ROOT/default.nix" -A coreboot
  if [ "$(cat /tmp/build-exit 2>/dev/null)" != "BUILD_EXIT=0" ]; then
    echo "Build failed!" >&2
    exit 1
  fi

  echo "=== Build complete ==="
  ls -lh "$ROM"
fi

# ── Test ───────────────────────────────────────────────────────────────

if ! $BUILD_ONLY; then
  # Write the test script with resolved paths substituted
  cat > /tmp/coreboot-test.sh << TESTSCRIPT
set -euo pipefail
ROM='$ROM'

if [ ! -f "\$ROM" ]; then
  echo "ROM not found at \$ROM" >&2
  exit 1
fi

echo "=== Booting \$ROM in QEMU ==="
timeout 30 qemu-system-x86_64 \
  -bios "\$ROM" \
  -M q35 \
  -nographic \
  -serial mon:stdio \
  2>&1 | tee /tmp/qemu.log || true

echo ""
echo "=== Verifying boot output ==="

fail=false

if grep -q "coreboot-" /tmp/qemu.log; then
  echo "PASS: coreboot banner seen"
else
  echo "FAIL: coreboot banner not found"
  fail=true
fi

if grep -q "Jumping to boot code" /tmp/qemu.log; then
  echo "PASS: EDK2 UEFI payload executed"
else
  echo "FAIL: EDK2 payload not reached"
  fail=true
fi

if \$fail; then
  echo ""
  echo "=== QEMU log ==="
  cat /tmp/qemu.log
  exit 1
fi

echo ""
echo "=== All checks passed ==="
TESTSCRIPT

  echo "bash /tmp/coreboot-test.sh; echo TEST_EXIT=\$? > /tmp/test-exit" | \
    nix-shell "$REPO_ROOT/default.nix" -A coreboot
  if [ "$(cat /tmp/test-exit 2>/dev/null)" != "TEST_EXIT=0" ]; then
    echo "Test failed!" >&2
    exit 1
  fi
fi
