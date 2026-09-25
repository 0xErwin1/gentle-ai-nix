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
    version = "3.7.0";
    owner = "Gentleman-Programming";
    rev = "v3.7.0";
    hash = "sha256-I7WFMonFGsrEftEBFkQezNa0LKn5TYWVfwULw9EmjJc=";
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
  # v3.7.0 was tagged from a main that has moved on since, so the tag and the
  # commit are different revisions that fetch to different store paths -- the tag
  # is the last release, the branch is the tip. Every channel carries the Pi
  # package retirement 3.6.0 lacked, so none installs
  # `@juicesharp/rpiv-ask-user-question`.
  beta = {
    version = "3.7.0-main.c5da5fd0";
    owner = "Gentleman-Programming";
    rev = "c5da5fd0f5f0a0b34cfc9bca0a8b5dd5a46213a8";
    hash = "sha256-cwVOJwTISVWiiG2vkxPq0JXsVoAXXhlW9wfq41kxzqY=";
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
    version = "3.7.0-main.901ab5b5-declarative-config";
    owner = "0xErwin1";
    rev = "901ab5b5f685bd3d750d550f1c6e5ab1ac6472de";
    hash = "sha256-BCOnODLOBPpibYoxPbjsr9K2BYW/LNXdx0tktn1bWpk=";
    vendorHash = "sha256-A7iVL8Xu6tj6hpU7Xo9D9xhIOKze4H1K5LdQekJ+/oc=";
    providesContract = true;
  };
}
