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
  # never mistaken for a release. This revision is thirty commits past the
  # commit the `v3.6.2` tag names; its Pi plugin is still `gentle-engram@0.6.0`,
  # the one the stable channel ships.
  main = {
    version = "3.6.2-main.ed533793";
    rev = "ed533793d78dbc6922688510f6b4484c904bed49";
    hash = "sha256-xkq+nStz+Ep6jlKa8TfAOLqg/7IZ8FjV7KUCEe0W1cw=";
    vendorHash = "sha256-uNoFAUJfu3SFU9OqT1AJvHKKN6t6oPo6nC6GEbYhYJs=";
  };
}
