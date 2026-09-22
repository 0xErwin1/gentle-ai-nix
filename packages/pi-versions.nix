# The gentle-pi releases Pi can install for this flake's configuration, one
# entry per channel.
#
# Unlike versions.nix and engram-versions.nix this table names no derivation
# this flake builds for Pi's own install: gentle-pi is a harness plugin Pi
# installs itself, by running `pi install <source>` with a `source` this table
# supplies. `stable` names the exact npm release this flake supports, so it is
# installed through the same managed override as `main`. `main` names a
# revision on the canonical gentle-shell repository's main branch; its npm
# package identity remains gentle-pi. Pi's own git installer fetches it
# directly at activation -- no Nix hash is needed for that because Nix never
# touches the bytes, the same way `beta` in versions.nix needs no vendorHash of
# its own beyond what building requires.
#
# Each entry also carries the fields the one derivation this flake does build
# from this table needs: the standalone `gentle-shell` launcher
# (packages/gentle-shell.nix, selected by `providers.pi.launcher`), which is
# fetched from the repository archive (`rev` with `archiveHash`) and built with
# pnpm (`pnpmDepsHash` over the lockfile the repository ships). Those fields
# never reach Pi's installer; `source` is what it reads.
#
# Refresh main with:
#   git ls-remote https://github.com/Gentleman-Programming/gentle-shell main
#
# `stable` is npm's `gentle-pi@3.5.1`. Pinning the npm source makes a switch
# converge on the release this flake tested, rather than whatever `latest`
# resolves to when Pi runs its installer. `rev` is the commit the `v3.5.1`
# tag peels to, which is where the launcher build comes from.
{
  stable = {
    source = "npm:gentle-pi@3.5.1";

    version = "3.5.1";
    rev = "df41b3a2420f8f9910cebd8b4bfb4a29f5fefa60";
    archiveHash = "sha256-hIoHnC0O6+24v8aqt1BtTbW6G2NqzORkvOmN6yyBUZ0=";
    pnpmDepsHash = "sha256-NQXEyRCFoCaOvrpC/D9QTepPnSUTFYSFTH/ejHvhHM8=";
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
    archiveHash = "sha256-DrHveEU21dnT1o9O/bL61HiklhrKl5IMfXBweSFTZHQ=";
    pnpmDepsHash = "sha256-NQXEyRCFoCaOvrpC/D9QTepPnSUTFYSFTH/ejHvhHM8=";
  };
}
