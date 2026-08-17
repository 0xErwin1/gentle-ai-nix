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
    version = "2.3.0";
    owner = "Gentleman-Programming";
    rev = "v2.3.0";
    hash = "sha256-APKVSlsz8BOBDXQGNNOCdpgyFKSiZwku1Y1c3ZVzYv8=";
    vendorHash = "sha256-qeeD+omJzlqolHGzGx2E60fEucjweb62UQY3N/0xxgs=";
    providesContract = false;
  };

  beta = {
    version = "2.4.0-rc.8";
    owner = "Gentleman-Programming";
    rev = "v2.4.0-rc.8";
    hash = "sha256-plB9mxudrfZJBPpHjPRyTFi318TyggiEVQrOxdjwYAc=";
    vendorHash = "sha256-qeeD+omJzlqolHGzGx2E60fEucjweb62UQY3N/0xxgs=";
    providesContract = false;
  };

  # The declarative configuration contract this flake renders through is not in
  # a release yet, so the channel that carries it is a branch. It is the default
  # for that reason alone: a released channel builds, and then the renderer
  # fails on `config`, which no version below has.
  #
  # When the contract lands upstream, this entry goes away and `stable` becomes
  # the default again.
  contract = {
    version = "2.3.0-unstable-declarative-config";
    owner = "0xErwin1";
    rev = "bf32f10e460388d79eb25e70b67d30e3a3d2e05c";
    hash = "sha256-D7Ql34R5sFA8/eCVcIoanmZgAhtizc7Fo4n2zasdihU=";
    vendorHash = "sha256-qeeD+omJzlqolHGzGx2E60fEucjweb62UQY3N/0xxgs=";
    providesContract = true;
  };
}
