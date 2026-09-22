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
# `stable` is npm's `gentle-pi@3.5.1`. Pinning the npm source makes a switch
# converge on the release this flake tested, rather than whatever `latest`
# resolves to when Pi runs its installer.
{
  stable = {
    source = "npm:gentle-pi@3.5.1";
  };

  # Tracks gentle-shell's main the same way versions.nix's beta channel tracks
  # Gentle AI's own: a pin is how a flake expresses a branch, and refreshing
  # it is what letting Pi install the tip of main again would have done.
  #
  # This revision is past the `v3.5.1` release: the tag peels to an earlier
  # commit, so the pin no longer coincides with the release. The `-main.`
  # prerelease label keeps a build from here from being mistaken for the
  # release: `package.json` at the tip reads `3.6.0`.
  #
  # The release pins Gentle AI v3.6.0 through `INSTALLER_VERSION` in its
  # `scripts/gentle-ai-installer.mjs` -- the exact release this flake builds, so
  # the copy of Gentle AI the plugin downloads for itself and the package a
  # switch puts on PATH are the same one.
  main = {
    version = "3.6.0-main.c0aadd8b";
    rev = "c0aadd8b218c250218769f4fc39af698c23df2df";
  };
}
