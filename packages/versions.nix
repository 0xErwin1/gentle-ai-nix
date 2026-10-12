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
    version = "4.1.1";
    owner = "Gentleman-Programming";
    rev = "v4.1.1";
    hash = "sha256-d3QlYWeQgo9KyslKVMeI/BsT26FVmZf6Sa19Eh+rWok=";
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
  # At this pin the tip of main is the commit v4.1.1 tags, so both channels
  # fetch the same tree; they stay separate entries because main moves on after
  # a release and the tag does not. Every channel carries the Pi
  # package retirement 3.6.0 lacked, so none installs
  # `@juicesharp/rpiv-ask-user-question`.
  beta = {
    version = "4.1.1-main.898d3976e";
    owner = "Gentleman-Programming";
    rev = "898d3976e8049a7238eaa7de60bff325c30d2b3d";
    hash = "sha256-d3QlYWeQgo9KyslKVMeI/BsT26FVmZf6Sa19Eh+rWok=";
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
  # It sits on the tip of main rather than on a release tag: the chain is a
  # stack of PRs rebased onto whatever main is, which is what keeps it mergeable
  # without upstream having a `config` of its own. It is rebased as one unit and
  # carries that feature and nothing else, so nothing from outside the
  # declarative configuration contract justifies a commit here.
  #
  # This generation also stages the injections no component owns, starting with
  # the always-on routing guidance that carries the mandatory ODD protocol:
  # before that, a declaratively rendered tree was missing guidance every
  # imperative install writes. See the fork's
  # `feat/declarative-config-9-routing-guidance`.
  #
  # Rendering through it needs the clients Gentle AI interrogates. v3.3.0 taught
  # the renderer to run `opencode --version` and choose between the v1 and v2
  # managed assets, which a build sandbox cannot answer on its own: that is what
  # `providers.<name>.package` exists for, and why an OpenCode configuration
  # without it fails to render from this generation on.
  contract = {
    version = "4.1.1-main.060c169a-declarative-config";
    owner = "0xErwin1";
    rev = "060c169a5ac2b2cee591f425b490f7adcaf379a2";
    hash = "sha256-hQx3jX3v6t4RCfhnIO0VCKJQUenATdV+q1U7GDqHW7A=";
    vendorHash = "sha256-A7iVL8Xu6tj6hpU7Xo9D9xhIOKze4H1K5LdQekJ+/oc=";
    providesContract = true;
  };
}
