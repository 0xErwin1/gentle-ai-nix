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

  # A release candidate is only ahead of stable while one is open. The 2.4.0
  # candidates were promoted, so the newest build in this channel is the
  # release itself, which is what `gentle-ai upgrade --channel beta` also
  # resolves to. It moves ahead again with the first candidate after 2.4.0.
  beta = {
    version = "2.4.0";
    owner = "Gentleman-Programming";
    rev = "v2.4.0";
    hash = "sha256-53zHrrm1l/Pkh7H5HjbbIcv58ph4jZ5NaXX5KmKK714=";
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
    version = "2.4.0-unstable-declarative-config";
    owner = "0xErwin1";
    rev = "7098e8d41ac77e304bb1bbef5e341725b0b2fe35";
    hash = "sha256-DWqW+PUQSnO2caNZ69K6AJ5+6k9IlSvkwftjlvRZVZc=";
    vendorHash = "sha256-qeeD+omJzlqolHGzGx2E60fEucjweb62UQY3N/0xxgs=";
    providesContract = true;
  };
}
