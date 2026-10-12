# The Engram releases this flake can build, one entry per channel.
#
# Same shape as versions.nix, for the same reason: adding a release is one entry
# rather than another copy of the package expression.
#
# Refresh a hash with:
#   nix-prefetch-url --unpack https://github.com/Gentleman-Programming/engram/archive/<ref>.tar.gz
#   nix hash convert --hash-algo sha256 --to sri <hash>
{
  # The newest tagged release. Its Pi plugin is `gentle-engram@0.4.1`,
  # the exact npm version the module pins for this channel. The pair is read
  # from the release's own `plugin/pi/package.json`, not from npm's `latest`:
  # the plugin's own tags can run ahead of the core release.
  stable = {
    version = "3.3.2";
    rev = "v3.3.2";
    hash = "sha256-NpctH9oAOyGvzyfPMme3pzNZ4RqHSdquSkBA3PoEvaw=";
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
  # never mistaken for a release. This revision is past `v3.3.2` and carries
  # the Pi plugin `gentle-engram@0.4.2`, which pairs with no core release.
  main = {
    version = "3.3.2-main.5c417184";
    rev = "5c4171845958f046968c14d7d57a325eb4a83b7e";
    hash = "sha256-nF64HUlc2wnZFYlI8QVPB77IqA6SHY09W6kQH1CdR7E=";
    vendorHash = "sha256-9RTI+XAdIHDKPkW+s6htk1Me6/gaE0fpuCP0xTLtYio=";
  };
}
