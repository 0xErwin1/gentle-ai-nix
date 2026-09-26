# The Engram releases this flake can build, one entry per channel.
#
# Same shape as versions.nix, for the same reason: adding a release is one entry
# rather than another copy of the package expression.
#
# Refresh a hash with:
#   nix-prefetch-url --unpack https://github.com/Gentleman-Programming/engram/archive/<ref>.tar.gz
#   nix hash convert --hash-algo sha256 --to sri <hash>
{
  # The newest tagged release. Its Pi plugin is `gentle-engram@0.1.16`,
  # the exact npm version the module pins for this channel.
  stable = {
    version = "2.2.1";
    rev = "v2.2.1";
    hash = "sha256-unN6bMnxVJAq3S3DsJCq2rUUddycwkYHGFs92hc+tQU=";
    vendorHash = "sha256-gDGy1s4JcX/6bI2eoycfsWJTbU2L0RAi3xCJ3AzFwYU=";
  };

  # Tracks the tip of Engram's default branch the way versions.nix's beta tracks
  # Gentle AI's own: a pin is how a flake expresses a branch, and refreshing it
  # is what pulling main again would have done.
  #
  # Engram's Go binary and Pi plugin are paired at this revision: off stable
  # the plugin is built from the same source and linked into the rendered tree.
  #
  # The version carries the `-main.` prerelease tag so a build from here is
  # never mistaken for a release.
  main = {
    version = "2.2.1-main.c61f601e";
    rev = "c61f601ee9cc3a9cba6abbedd6bef2382318eada";
    hash = "sha256-m0g8yIfH7m8qghlgEEPrMkexyGHIssaez6mTwxuZZQ8=";
    vendorHash = "sha256-gDGy1s4JcX/6bI2eoycfsWJTbU2L0RAi3xCJ3AzFwYU=";
  };
}
