# The gentle-pi releases Pi can install for this flake's configuration, one
# entry per channel.
#
# Unlike versions.nix and engram-versions.nix this table names no derivation
# this flake builds: gentle-pi is a harness plugin Pi installs itself, by
# running `pi install <source>` with a source this table supplies. `stable`
# names the exact npm release this flake supports, so it is installed through
# the same managed override as `main`. `main` names a revision on the canonical
# gentle-shell repository's main branch; its npm package identity remains
# gentle-pi. Pi's own git installer fetches it directly at activation -- no Nix
# hash is needed because Nix never touches the bytes, the same way `beta` in
# versions.nix needs no vendorHash of its own beyond what building requires.
#
# Refresh main with:
#   git ls-remote https://github.com/Gentleman-Programming/gentle-shell main
#
# `stable` is npm's `gentle-pi@3.1.1`. Pinning the npm source makes a switch
# converge on the release this flake tested, rather than whatever `latest`
# resolves to when Pi runs its installer.
{
  stable = {
    source = "npm:gentle-pi@3.1.1";
  };

  # Tracks gentle-shell's main the same way versions.nix's beta channel tracks
  # Gentle AI's own: a pin is how a flake expresses a branch, and refreshing
  # it is what letting Pi install the tip of main again would have done.
  #
  # v3.1.1 was tagged from the tip of main, so this revision is also the release;
  # a later push to main moves this entry alone.
  #
  # That release pins Gentle AI v3.0.1 through `INSTALLER_VERSION` in its
  # `scripts/gentle-ai-installer.mjs`, so a copy of Gentle AI the plugin
  # downloads for itself is one release behind the v3.0.2 this flake builds.
  main = {
    version = "3.1.1-main.ce47bae0";
    rev = "ce47bae0168d4a60b43cc45d660d83901c8868dd";
  };
}
