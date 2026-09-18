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
    version = "3.2.0";
    owner = "Gentleman-Programming";
    rev = "v3.2.0";
    hash = "sha256-20quvfNYaP6PIOPkIPAcUMTBAHaVaqHp/dRxQXVUB38=";
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
  # v3.2.0 was tagged from the tip of main, so today this channel and `stable`
  # name the same tree; the refs differ because main keeps moving, and the tag
  # and the commit fetch to the same store path because the archive root is
  # stripped.
  beta = {
    version = "3.2.0-main.e8811b53";
    owner = "Gentleman-Programming";
    rev = "e8811b53a736ca160755b370b4d19ce7210365e0";
    hash = "sha256-20quvfNYaP6PIOPkIPAcUMTBAHaVaqHp/dRxQXVUB38=";
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
  #
  # It sits on a tagged generation rather than on the moving tip of main: the
  # chain behind it is a stack of PRs, and rebasing that stack is what keeps it
  # mergeable without upstream having a `config` of its own. It last moved from
  # v3.1.0 to v3.2.0, upstream's telemetry release; the chain's own diff is
  # unchanged by that rebase, the same 97 files and 8512 insertions it has
  # carried since v3.0.0.
  contract = {
    version = "3.2.0-main.b43d8a39-declarative-config";
    owner = "0xErwin1";
    rev = "b43d8a392df6b689b7e34896177768850fff8e4a";
    hash = "sha256-EYWOD4UJlkUSZnyLj0rWKsme882BEhyysNadZVEc7j8=";
    vendorHash = "sha256-A7iVL8Xu6tj6hpU7Xo9D9xhIOKze4H1K5LdQekJ+/oc=";
    providesContract = true;
  };
}
