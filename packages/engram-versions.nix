# The Engram releases this flake can build, one entry per channel.
#
# Same shape as versions.nix, for the same reason: adding a release is one entry
# rather than another copy of the package expression.
#
# Refresh a hash with:
#   nix-prefetch-url --unpack https://github.com/Gentleman-Programming/engram/archive/<ref>.tar.gz
#   nix hash convert --hash-algo sha256 --to sri <hash>
{
  # The newest tagged release. Its Pi plugin is `gentle-engram@0.5.1`,
  # the exact npm version the module pins for this channel. The pair is read
  # from the release's own `plugin/pi/package.json`, not from npm's `latest`:
  # the plugin's own tags can run ahead of the core release.
  stable = {
    version = "3.6.1";
    rev = "v3.6.1";
    hash = "sha256-Rk6zQGrUDnv8rlvEerFFdhubJPmtO7pNcdNAHMb+H30=";
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
  # never mistaken for a release. The tip of main is the commit the `v3.6.1` tag
  # names, so both channels build the same tree and only the label differs; its
  # Pi plugin is still `gentle-engram@0.5.1`, the one the stable channel ships.
  main = {
    version = "3.6.1-main.d33a14a2";
    rev = "d33a14a2ed822784752e5678b1673289ee1c0de4";
    hash = "sha256-Rk6zQGrUDnv8rlvEerFFdhubJPmtO7pNcdNAHMb+H30=";
    vendorHash = "sha256-uNoFAUJfu3SFU9OqT1AJvHKKN6t6oPo6nC6GEbYhYJs=";
  };
}
