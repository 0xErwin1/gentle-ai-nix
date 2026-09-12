# The gentle-pi releases Pi can install for this flake's configuration, one
# entry per channel.
#
# Unlike versions.nix and engram-versions.nix this table names no derivation
# this flake builds: gentle-pi is a harness plugin Pi installs itself, by
# running `pi install <source>` with a source this table supplies. `stable`
# names npm, which is what Pi already installs by default, so choosing it
# emits nothing extra. `main` names a revision on gentle-pi's main branch,
# which Pi's own git installer fetches directly at activation -- no Nix hash
# is needed because Nix never touches the bytes, the same way `beta` in
# versions.nix needs no vendorHash of its own beyond what building requires.
#
# Refresh main with:
#   git ls-remote https://github.com/Gentleman-Programming/gentle-pi main
{
  stable = {
    source = "npm:gentle-pi";
  };

  # Tracks gentle-pi's main the same way versions.nix's beta channel tracks
  # Gentle AI's own: a pin is how a flake expresses a branch, and refreshing
  # it is what letting Pi install the tip of main again would have done.
  main = {
    version = "2.5.0-main.6e4478c0";
    rev = "6e4478c04615b0c013a017178dcfefa51579982d";
  };
}
