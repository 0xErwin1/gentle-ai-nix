# The Engram releases this flake can build, one entry per channel.
#
# Same shape as versions.nix, for the same reason: adding a release is one entry
# rather than another copy of the package expression.
#
# Refresh a hash with:
#   nix-prefetch-url --unpack https://github.com/Gentleman-Programming/engram/archive/<ref>.tar.gz
#   nix hash convert --hash-algo sha256 --to sri <hash>
{
  # The newest tagged release. Its Pi plugin is `gentle-engram@0.2.0`,
  # the exact npm version the module pins for this channel.
  stable = {
    version = "3.2.1";
    rev = "v3.2.1";
    hash = "sha256-t7YaSqglVDQYJ92kkH35KAT+VscUs+EKFZWQnHUWdGc=";
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
    version = "3.2.1-main.ee7cb292";
    rev = "ee7cb292d54b3de77c6c347a81890be92683b490";
    hash = "sha256-/rMy0XOTwW0ASaeuV+bM64w2WXmNIqkSI1VDVzl+Lv4=";
    vendorHash = "sha256-9RTI+XAdIHDKPkW+s6htk1Me6/gaE0fpuCP0xTLtYio=";
  };
}
