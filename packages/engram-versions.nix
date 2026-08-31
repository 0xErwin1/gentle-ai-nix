# The Engram releases this flake can build, one entry per channel.
#
# Same shape as versions.nix, for the same reason: adding a release is one entry
# rather than another copy of the package expression.
#
# Refresh a hash with:
#   nix-prefetch-url --unpack https://github.com/Gentleman-Programming/engram/archive/<ref>.tar.gz
#   nix hash convert --hash-algo sha256 --to sri <hash>
{
  stable = {
    version = "1.20.0";
    rev = "v1.20.0";
    hash = "sha256-qdKAll7N0HtJRbZYilzatVCUz1Tr+pqM217Y8O+Csjs=";
    vendorHash = "sha256-JBwLW62M6SFXqgYKeSdUI136B42f3h43V9ud1qUW484=";
  };

  # The 2.0 candidate is not a drop-in replacement for the stable build, and its
  # own release notes say so: keep a stable installation available rather than
  # replacing one with it. It stays selectable and never the default, so taking
  # it is a decision recorded in the configuration rather than a version bump
  # that arrives with a flake update.
  #
  # Two of its named risk areas apply to any store with history: legacy sessions
  # with blank ownership, which `engram doctor` reports, and Pi/OpenCode session
  # attribution becoming fail-closed on the runtime identity.
  rc = {
    version = "2.0.0-rc.1";
    rev = "v2.0.0-rc.1";
    hash = "sha256-2H7nRNx2SmL2MOfH1sodFCLD4XC/q2aiJMNoL0HH6KA=";
    vendorHash = "sha256-JBwLW62M6SFXqgYKeSdUI136B42f3h43V9ud1qUW484=";
  };
}
