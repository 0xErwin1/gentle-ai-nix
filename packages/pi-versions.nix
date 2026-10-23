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
# `stable` is npm's `gentle-pi@4.3.0`, which needs Node >= 22.19 and Pi >= 1.2.0.
# Pinning the npm source makes a switch
# converge on the release this flake tested, rather than whatever `latest`
# resolves to when Pi runs its installer.
{
  stable = {
    source = "npm:gentle-pi@4.3.0";
  };

  # Tracks gentle-shell's main the same way versions.nix's beta channel tracks
  # Gentle AI's own: a pin is how a flake expresses a branch, and refreshing
  # it is what letting Pi install the tip of main again would have done.
  #
  # This revision is the tip of gentle-shell's `main`, 75 commits past the
  # commit the `v4.3.0` tag peels to; `package.json` there still reads `4.3.0`,
  # the release `stable` above names on npm. The `-main.` prerelease label keeps a build
  # from here from being mistaken for that published release.
  #
  # The plugin installs Gentle AI v4.2.0 through `INSTALLER_VERSION` in
  # `scripts/gentle-ai-installer.mjs`. That matches this flake's stable channel;
  # selecting the separately pinned beta channel does not change the plugin's
  # installer target.
  main = {
    version = "4.3.0-main.ca893c9c";
    rev = "ca893c9c4e62a72106d3d68b0e4ac5fbf0dab522";
  };
}
