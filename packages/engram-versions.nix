# The Engram releases this flake can build, one entry per channel.
#
# Same shape as versions.nix, for the same reason: adding a release is one entry
# rather than another copy of the package expression.
#
# Refresh a hash with:
#   nix-prefetch-url --unpack https://github.com/Gentleman-Programming/engram/archive/<ref>.tar.gz
#   nix hash convert --hash-algo sha256 --to sri <hash>
{
  # The newest tagged release. Its Pi plugin is `gentle-engram@0.7.0`,
  # the exact npm version the module pins for this channel. The pair is read
  # from the release's own `plugin/pi/package.json`, not from npm's `latest`:
  # the plugin's own tags can run ahead of the core release.
  stable = {
    version = "3.7.0";
    rev = "v3.7.0";
    hash = "sha256-RuNg8m+zspKQy5m10ay+Y7dWKCJrDPOGAD0TRPGFSm0=";
    vendorHash = "sha256-uNoFAUJfu3SFU9OqT1AJvHKKN6t6oPo6nC6GEbYhYJs=";
  };

  # Tracks the tip of Engram's default branch the way versions.nix's beta tracks
  # Gentle AI's own: a pin is how a flake expresses a branch, and refreshing it
  # is what pulling main again would have done.
  #
  # Engram's Go binary and Pi plugin are paired at this revision: off stable
  # the plugin is built from the same source and linked into the rendered tree.
  #
  # The version carries the `-main.` prerelease tag so a build from here is
  # never mistaken for a release. This revision is eleven commits past the commit
  # the `v3.7.0` tag names; its Pi plugin is still `gentle-engram@0.7.0`, the one
  # the stable channel ships. Main has moved past it, but the commits since raise
  # the `go` directive to 1.26.11 while this flake's nixpkgs still ships 1.26.8,
  # so the channel stays on the newest revision that builds.
  main = {
    version = "3.7.0-main.8dd4cb22";
    rev = "8dd4cb227178aef4e391172ff3d8d7b6a593d1fb";
    hash = "sha256-t7Ng29PoA/rrNsljMbSyAzI3bQjbgEq9Eneae64c+48=";
    vendorHash = "sha256-uNoFAUJfu3SFU9OqT1AJvHKKN6t6oPo6nC6GEbYhYJs=";
  };
}
