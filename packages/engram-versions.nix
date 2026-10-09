# The Engram releases this flake can build, one entry per channel.
#
# Same shape as versions.nix, for the same reason: adding a release is one entry
# rather than another copy of the package expression.
#
# Refresh a hash with:
#   nix-prefetch-url --unpack https://github.com/Gentleman-Programming/engram/archive/<ref>.tar.gz
#   nix hash convert --hash-algo sha256 --to sri <hash>
{
  # The newest tagged release. Its Pi plugin is `gentle-engram@0.3.0`,
  # the exact npm version the module pins for this channel -- the plugin's
  # own `pi-v0.4.0` tag is ahead of the core release and pairs with no
  # core version, so the pair is read from the release's own
  # `plugin/pi/package.json`, not from npm's `latest`.
  stable = {
    version = "3.3.0";
    rev = "v3.3.0";
    hash = "sha256-+zEm5sFsAGGjEsBtwSAUlJHybXNYyj9ns7FlHjyvBhU=";
    vendorHash = "sha256-9RTI+XAdIHDKPkW+s6htk1Me6/gaE0fpuCP0xTLtYio=";
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
    version = "3.3.0-main.ba23804f";
    rev = "ba23804f64b8e6d21acd006bea5ce3831fd5337d";
    hash = "sha256-UvDEXq9Hvez6NvjR7Or+tb+w5jH7Lz+A01enbI3igWk=";
    vendorHash = "sha256-9RTI+XAdIHDKPkW+s6htk1Me6/gaE0fpuCP0xTLtYio=";
  };
}
