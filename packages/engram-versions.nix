# The Engram releases this flake can build, one entry per channel.
#
# Same shape as versions.nix, for the same reason: adding a release is one entry
# rather than another copy of the package expression.
#
# Refresh a hash with:
#   nix-prefetch-url --unpack https://github.com/Gentleman-Programming/engram/archive/<ref>.tar.gz
#   nix hash convert --hash-algo sha256 --to sri <hash>
{
  # The newest tagged release. Its Pi plugin is `gentle-engram@0.4.2`,
  # the exact npm version the module pins for this channel. The pair is read
  # from the release's own `plugin/pi/package.json`, not from npm's `latest`:
  # the plugin's own tags can run ahead of the core release.
  stable = {
    version = "3.4.0";
    rev = "v3.4.0";
    hash = "sha256-nF64HUlc2wnZFYlI8QVPB77IqA6SHY09W6kQH1CdR7E=";
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
  # never mistaken for a release. This revision is the commit the `v3.5.3` tag
  # names, and its Pi plugin is `gentle-engram@0.5.1` -- ahead of the v3.4.0 /
  # 0.4.2 pair the stable channel still ships.
  main = {
    version = "3.5.3-main.2c9c2369";
    rev = "2c9c2369f27a5032386c6ae93cf035288b3a2025";
    hash = "sha256-hLNLGud92KGq60yu0N88HZ3u6+778TIFdAcQFDrsvxU=";
    vendorHash = "sha256-OYP0cZoGgsLWJ7BVvXDKBYoj6oGa1SoCnIB/2+sovx8=";
  };
}
