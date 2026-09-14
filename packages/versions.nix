# The Gentle AI releases this flake can build, one entry per channel.
#
# Keeping them as data rather than as three near-identical derivations means
# adding a release is one entry, and the package expression never learns which
# channel it is building.
#
# Refresh a hash with:
#   nix-prefetch-url --unpack https://github.com/<owner>/gentle-ai/archive/<ref>.tar.gz
#   nix hash convert --hash-algo sha256 --to sri <hash>
#
# providesContract records whether a release has `gentle-ai config`, which this
# flake renders through. Recording it as data means choosing a release without
# it fails while the configuration is still being evaluated, naming the reason,
# rather than deep inside the renderer with a command-not-found.
{
  stable = {
    version = "2.9.1";
    owner = "Gentleman-Programming";
    rev = "v2.9.1";
    hash = "sha256-ZYitdIUDUautUeS0KjWMwgbbrCB4fM5t4c3HJAZnfuk=";
    vendorHash = "sha256-A7iVL8Xu6tj6hpU7Xo9D9xhIOKze4H1K5LdQekJ+/oc=";
    providesContract = false;
  };

  # Gentle AI's own beta channel is not a release candidate: `gentle-ai upgrade
  # --channel beta` runs `go install .../cmd/gentle-ai@main`, so beta means the
  # tip of main. A pin is how a flake expresses that, and refreshing it is what
  # re-running the upgrade would have done.
  #
  # The version carries the `-main.` prerelease tag Gentle AI uses to classify a
  # build's evidence channel, so a build from here is never mistaken for stable.
  # Main is ahead of the latest stable tag; this channel tracks its tip.
  beta = {
    version = "2.8.2-main.e3f53de6";
    owner = "Gentleman-Programming";
    rev = "e3f53de6cb5b4e944fc02f52469a6d7797dde03f";
    hash = "sha256-sFAhgb1wkc/jOIyjZT9l9D1MV0FWli5/KPgvZnNCcUI=";
    vendorHash = "sha256-A7iVL8Xu6tj6hpU7Xo9D9xhIOKze4H1K5LdQekJ+/oc=";
    providesContract = false;
  };

  # The declarative configuration contract this flake renders through is not in
  # a release yet, so the channel that carries it is a branch. It is the default
  # for that reason alone: a released channel builds, and then the renderer
  # fails on `config`, which no version below has.
  #
  # It tracks main the same way beta does, with the contract commits on top.
  #
  # When the contract lands upstream, this entry goes away and `stable` becomes
  # the default again.
  contract = {
    version = "2.9.1-main.c3d0290f-declarative-config";
    owner = "0xErwin1";
    rev = "c3d0290fd5f95f4726448a8ff0a8525abf7f3d49";
    hash = "sha256-uRPln98REvZuW/YImAXPPqYl4t6zqej+t778nYG1tyY=";
    vendorHash = "sha256-A7iVL8Xu6tj6hpU7Xo9D9xhIOKze4H1K5LdQekJ+/oc=";
    providesContract = true;
  };
}
