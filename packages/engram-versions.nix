# The Engram releases this flake can build, one entry per channel.
#
# Same shape as versions.nix, for the same reason: adding a release is one entry
# rather than another copy of the package expression.
#
# Refresh a hash with:
#   nix-prefetch-url --unpack https://github.com/Gentleman-Programming/engram/archive/<ref>.tar.gz
#   nix hash convert --hash-algo sha256 --to sri <hash>
{
  # The newest tagged release. Its Pi plugin is `gentle-engram@0.6.0`,
  # the exact npm version the module pins for this channel. The pair is read
  # from the release's own `plugin/pi/package.json`, not from npm's `latest`:
  # the plugin's own tags can run ahead of the core release.
  stable = {
    version = "3.6.2";
    rev = "v3.6.2";
    hash = "sha256-JANo2rwSFBdbtovLRob4GmESEJ/uS3pUVMZAfwV4+60=";
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
  # never mistaken for a release. This revision is 46 commits past the commit
  # the `v3.6.2` tag names. Its Pi plugin has moved on to
  # `gentle-engram@0.7.0`, which is built from this same source and linked into
  # the rendered tree; the npm pin the stable channel uses still names the
  # plugin v3.6.2 ships.
  main = {
    version = "3.6.2-main.f96b6130";
    rev = "f96b613952bf7b4fd2d51f30286a68bd5ffdebf2";
    hash = "sha256-RuNg8m+zspKQy5m10ay+Y7dWKCJrDPOGAD0TRPGFSm0=";
    vendorHash = "sha256-uNoFAUJfu3SFU9OqT1AJvHKKN6t6oPo6nC6GEbYhYJs=";
  };
}
