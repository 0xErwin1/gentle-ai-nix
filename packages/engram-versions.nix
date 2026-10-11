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
  # never mistaken for a release. This revision is the commit `v3.3.2` tags,
  # fetched by commit so it stays a distinct channel when main moves on.
  main = {
    version = "3.3.2-main.35d14520";
    rev = "35d14520fdd3a4de24f989b835611f5585cdebb3";
    hash = "sha256-NpctH9oAOyGvzyfPMme3pzNZ4RqHSdquSkBA3PoEvaw=";
    vendorHash = "sha256-9RTI+XAdIHDKPkW+s6htk1Me6/gaE0fpuCP0xTLtYio=";
  };
}
