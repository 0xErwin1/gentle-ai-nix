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
    version = "2.4.0";
    owner = "Gentleman-Programming";
    rev = "v2.4.0";
    hash = "sha256-53zHrrm1l/Pkh7H5HjbbIcv58ph4jZ5NaXX5KmKK714=";
    vendorHash = "sha256-qeeD+omJzlqolHGzGx2E60fEucjweb62UQY3N/0xxgs=";
    providesContract = false;
  };

  # Gentle AI's own beta channel is not a release candidate: `gentle-ai upgrade
  # --channel beta` runs `go install .../cmd/gentle-ai@main`, so beta means the
  # tip of main. A pin is how a flake expresses that, and refreshing it is what
  # re-running the upgrade would have done.
  #
  # The version carries the `-main.` prerelease tag Gentle AI uses to classify a
  # build's evidence channel, so a build from here is never mistaken for stable.
  beta = {
    version = "2.4.0-main.9d223036";
    owner = "Gentleman-Programming";
    rev = "9d22303623a91e6db9a1781a7f253a847663f985";
    hash = "sha256-Sm5jte8TB1Y+k3jURylIbukjYBHgeNu5jCuqviFMzj0=";
    vendorHash = "sha256-qeeD+omJzlqolHGzGx2E60fEucjweb62UQY3N/0xxgs=";
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
    version = "2.4.0-main.da4226ec-declarative-config";
    owner = "0xErwin1";
    rev = "da4226ec";
    hash = "sha256-lN7B5r0BCB/ykmBK9ZgdSxIQ6n0Un8JDvmCquT/GV8k=";
    vendorHash = "sha256-qeeD+omJzlqolHGzGx2E60fEucjweb62UQY3N/0xxgs=";
    providesContract = true;
  };
}
