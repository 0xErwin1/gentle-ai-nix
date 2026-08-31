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
  # The newest candidate is v2.5.0-rc.3, and main is already 20 commits past it.
  # The channel is main rather than any tag: it moves with the branch.
  beta = {
    version = "2.5.0-main.3ef1e663";
    owner = "Gentleman-Programming";
    rev = "3ef1e663";
    hash = "sha256-YKMt7tss7Q3ixD+8UnymLMv2Ut0DHnUl+PPFn2/SCbg=";
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
    version = "2.5.0-main.1bb90c3a-declarative-config";
    owner = "0xErwin1";
    rev = "1bb90c3a";
    hash = "sha256-vpJ8RnQRpcUswbPvbCl165lqtT+22wQT6uuKhyBjsgE=";
    vendorHash = "sha256-qeeD+omJzlqolHGzGx2E60fEucjweb62UQY3N/0xxgs=";
    providesContract = true;
  };
}
