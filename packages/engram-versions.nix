# The Engram releases this flake can build, one entry per channel.
#
# Same shape as versions.nix, for the same reason: adding a release is one entry
# rather than another copy of the package expression.
#
# Refresh a hash with:
#   nix-prefetch-url --unpack https://github.com/Gentleman-Programming/engram/archive/<ref>.tar.gz
#   nix hash convert --hash-algo sha256 --to sri <hash>
{
  # The newest tagged release. Its Pi plugin is `gentle-engram@0.1.15`,
  # the exact npm version the module pins for this channel.
  stable = {
    version = "2.2.0";
    rev = "v2.2.0";
    hash = "sha256-jKj4x75I7CWbcdS/uP0O1YdWqlcQyj7Mvv5GrKTH8cw=";
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
    version = "2.2.0-main.c72dd99d";
    rev = "c72dd99db901945d9bfece6b5cc675037eecf83e";
    hash = "sha256-P1mRe0kTWCFf1M+T5ElaeyNlJ5uBXWEjA9o7Ko1HvBY=";
    vendorHash = "sha256-gDGy1s4JcX/6bI2eoycfsWJTbU2L0RAi3xCJ3AzFwYU=";
  };
}
