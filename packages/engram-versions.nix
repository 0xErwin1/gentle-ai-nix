# The Engram releases this flake can build, one entry per channel.
#
# Same shape as versions.nix, for the same reason: adding a release is one entry
# rather than another copy of the package expression.
#
# Refresh a hash with:
#   nix-prefetch-url --unpack https://github.com/Gentleman-Programming/engram/archive/<ref>.tar.gz
#   nix hash convert --hash-algo sha256 --to sri <hash>
{
  # The newest tagged release. Its Pi plugin is `gentle-engram@0.1.13`, which is
  # the exact npm version the module pins when Pi installs the plugin for this
  # channel -- npm's `latest` is not it, and a plugin running ahead of the
  # binary is the drift the pin exists to prevent.
  stable = {
    version = "2.0.0";
    rev = "v2.0.0";
    hash = "sha256-d5bxn72roCafsnnRUZcwf66QcgZWXNdY/eqoqBP/W4s=";
    vendorHash = "sha256-Bntymb7T9zk31G6WFQIuulnoeFYg0XPellN1nRVcUFA=";
  };

  # Tracks the tip of Engram's default branch the way versions.nix's beta tracks
  # Gentle AI's own: a pin is how a flake expresses a branch, and refreshing it
  # is what pulling main again would have done.
  #
  # Engram's two lines move independently -- the Go binary on tags, the Pi
  # plugin on npm -- and main is where the plugin gets ahead: 0.1.14 adds
  # `mem_list_projects`, which calls a `GET /projects` route the 2.0.0 tag does
  # not serve. Off stable the plugin is built from this same revision and
  # linked into the rendered tree, so the pair cannot drift here by
  # construction; that is also what keeps the non-stable path exercised.
  #
  # The version carries the `-main.` prerelease tag so a build from here is
  # never mistaken for a release.
  main = {
    version = "2.0.0-main.99b7df24";
    rev = "99b7df243fd933ce3c4e1714e8b27c9273e1d755";
    hash = "sha256-E0eme1qMQkRmrIYV4C9un/NSOeNFsjZcsZPqFCTSLA8=";
    vendorHash = "sha256-Bntymb7T9zk31G6WFQIuulnoeFYg0XPellN1nRVcUFA=";
  };
}
