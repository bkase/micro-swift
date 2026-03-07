{ pkgs, ... }:
{
  packages = [
    pkgs.git
    pkgs.elan
  ];

  env = {
    LEAN_PATH = ".lake/packages";
    LEAN_SRC_PATH = ".";
  };

  scripts.build.exec = "lake build";

  enterShell = ''
    echo "Lean 4 + Mathlib4 environment loaded (elan-managed)"
    echo "Installing toolchain from lean-toolchain..."
    elan install $(cat lean-toolchain | grep -oP 'v\d+\.\d+\.\d+.*') 2>/dev/null || true
    lean --version
    echo "Try: lake build"
  '';
}
