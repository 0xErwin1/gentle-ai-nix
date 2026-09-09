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

  # A 2.0 candidate, and a major version is where a store with history is at
  # risk. It stays selectable and never the default, so taking it is a decision
  # recorded in the configuration rather than a version bump that arrives with a
  # flake update.
  #
  # The rc.1 notes asked outright that a stable installation stay available
  # rather than be replaced, and named two risk areas that apply to any store
  # with history: legacy sessions with blank ownership, which `engram doctor`
  # reports, and Pi/OpenCode session attribution becoming fail-closed on the
  # runtime identity. Later candidates do not restate either, so the reason this
  # is not the default is the prerelease status itself, not a warning that has
  # to be reprinted every time.
  rc = {
    version = "2.0.0-rc.9";
    rev = "v2.0.0-rc.9";
    hash = "sha256-Ega4TTvheVg3iJdVUBwVSntE07Mb7faiKGQBNXwBPHI=";
    vendorHash = "sha256-Bntymb7T9zk31G6WFQIuulnoeFYg0XPellN1nRVcUFA=";
  };
}
