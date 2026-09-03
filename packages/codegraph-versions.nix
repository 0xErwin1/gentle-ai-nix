# The CodeGraph releases this flake can install, one entry per channel.
#
# Same shape as the other version tables, for the same reason: adding a release
# is one entry rather than another copy of the package expression. Upstream
# publishes stable tags only, so there is a single channel here.
#
# Upstream ships prebuilt archives rather than a buildable source tree, so a
# release carries one hash per platform instead of a source and a vendor hash.
#
# Refresh a hash with:
#   nix-prefetch-url https://github.com/colbymchenry/codegraph/releases/download/v<version>/codegraph-<platform>.tar.gz
#   nix hash convert --hash-algo sha256 --to sri <hash>
{
  stable = {
    version = "1.6.0";
    hashes = {
      "x86_64-linux" = "sha256-3jOR957UJiLZN+bNW3ZCp+qLt9FHNgfoC4ebpz7yFrA=";
      "aarch64-linux" = "sha256-bck1p7jxph5oileLmOo0aA6y4217kdsHnWT0AR8aZo8=";
      "x86_64-darwin" = "sha256-y4aiti7mdrYqVr+EI2AOfYZ+dS5X8yPNyYwPYjbv2Qg=";
      "aarch64-darwin" = "sha256-HHMDNRLVX2e+BHF+gVMui+r3vm+4Ux9RoXn6IwZK1IA=";
    };
  };
}
