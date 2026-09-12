# The engram source checkout, shared between the Go binary (engram.nix) and
# the Pi plugin package (gentle-engram-pi.nix): both are built from the exact
# same revision, and a single fetch is what keeps them from drifting apart
# the way two independent fetchFromGitHub calls on the same rev could.
{ fetchFromGitHub }:
release:
fetchFromGitHub {
  inherit (release) rev hash;
  owner = "Gentleman-Programming";
  repo = "engram";
}
