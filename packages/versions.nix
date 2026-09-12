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
    version = "2.7.0";
    owner = "Gentleman-Programming";
    rev = "v2.7.0";
    hash = "sha256-xlna0OcDRp/LT9eL/K3A5vCk/91SilydWgySQ3ZjuJ0=";
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
  # Main is 23 commits past v2.7.0, so this channel is ahead of stable again.
  beta = {
    version = "2.7.0-main.5c184843";
    owner = "Gentleman-Programming";
    rev = "5c184843b127295156cfb17675cb643fea81ea9c";
    hash = "sha256-+6Fk5XrPQ3C0IhQcIEsRBz2tn2a7lCWWPtQOE7AqBrc=";
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
    version = "2.7.0-main.a5cb6905-declarative-config";
    owner = "0xErwin1";
    rev = "a5cb69050f48ba9340696de73401decb2f831e7e";
    hash = "sha256-EEWGzmkvj+YyW8dg3CsxRlf32AN4HqiD4xEEzIiR7Lw=";
    vendorHash = "sha256-A7iVL8Xu6tj6hpU7Xo9D9xhIOKze4H1K5LdQekJ+/oc=";
    providesContract = true;
  };
}
