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
    version = "3.3.0";
    owner = "Gentleman-Programming";
    rev = "v3.3.0";
    hash = "sha256-an8AMBCojIdigvb/3+THNOIwJqk2ZyHlb4Xc0PzzcEc=";
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
  # v3.3.0 was tagged from the tip of main, so today this channel and `stable`
  # name the same tree; the refs differ because main keeps moving, and the tag
  # and the commit fetch to the same store path because the archive root is
  # stripped.
  beta = {
    version = "3.3.0-main.e28af0fd";
    owner = "Gentleman-Programming";
    rev = "e28af0fd7f8a11b5ee1089b3e13465a500590c41";
    hash = "sha256-an8AMBCojIdigvb/3+THNOIwJqk2ZyHlb4Xc0PzzcEc=";
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
  # mergeable without upstream having a `config` of its own.
  #
  # It is deliberately one generation behind `stable`. v3.3.0 is the first
  # release whose renderer probes the OpenCode runtime (`opencode --version`, see
  # internal/opencode/runtime.go) to choose between the v1 and v2 managed
  # assets, and a Nix build sandbox has no client binary to probe: rendering
  # this module's document fails there with "OpenCode runtime version
  # unavailable or unsupported". The chain is rebased onto v3.3.0 in the fork,
  # but this channel stays on the last generation that renders without the
  # client in the build environment until the flake can supply it.
  contract = {
    version = "3.2.1-main.8fa59a4a-declarative-config";
    owner = "0xErwin1";
    rev = "8fa59a4a8ff0ce5f15097966a21d191c13cec53a";
    hash = "sha256-x2p0RXrqP9Nt/gfHROvO28ttFyIPizlBZLR7ld1gGTM=";
    vendorHash = "sha256-A7iVL8Xu6tj6hpU7Xo9D9xhIOKze4H1K5LdQekJ+/oc=";
    providesContract = true;
  };
}
