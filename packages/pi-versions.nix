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
# `stable` is npm's `gentle-pi@4.7.0`, which needs Node >= 22.19 and Pi >= 1.2.0.
# Pinning the npm source makes a switch
# converge on the release this flake tested, rather than whatever `latest`
# resolves to when Pi runs its installer. `rev` is the commit the `v4.7.0`
# tag peels to, which is where the launcher build comes from.
#
# `gentleAi` is the Gentle AI runtime the launcher build carries in its package
# root, the one the package's `postinstall` would download into
# `.gentle-ai/v<version>/` (pnpm runs with --ignore-scripts, so it never does).
# Its values are that revision's `INSTALLER_VERSION` and `GENTLE_AI_RELEASE_ASSETS`
# in `scripts/gentle-ai-installer.mjs`, keyed by Nix system: `asset` is the
# release archive name, `assetSha256` its hex digest (what fetchurl checks), and
# `binarySha256` the hex digest of the `gentle-ai` binary inside it. The
# launcher's resolver checks the binary against those three fields, so they must
# be copied verbatim. Refresh them together with `rev`:
#   curl -sL https://raw.githubusercontent.com/Gentleman-Programming/gentle-shell/<rev>/scripts/gentle-ai-installer.mjs \
#     | grep -E 'INSTALLER_VERSION =|asset\("'
let
  # Both channels pin the same installer version, so they share one table; a
  # channel whose revision moves `INSTALLER_VERSION` gets its own.

  gentleAi_4_4_0 = {
    version = "4.4.0";
    assets = {
      x86_64-linux = {
        asset = "gentle-ai_4.4.0_linux_amd64.tar.gz";
        assetSha256 = "1f72ca13b32e87cb7f65b29e7fae6df4490b53d69d4763cdf23e944165880cd6";
        binarySha256 = "9f39a94cef0b9882be4cd519fac3ef3602e602e3bf437df7db55c8cbd42f358d";
      };
      aarch64-linux = {
        asset = "gentle-ai_4.4.0_linux_arm64.tar.gz";
        assetSha256 = "2d8874464cbe54b66a77d7c9fe66ce577933de00936ed1a035c81de6406a95fc";
        binarySha256 = "b9913af83cbeff2719e33d4b6c09e6ed568a000c4d6b885b4806ec5ce796f2b7";
      };
      x86_64-darwin = {
        asset = "gentle-ai_4.4.0_darwin_amd64.tar.gz";
        assetSha256 = "95686ea30615516aa29ebb6257227b1cdd4c67649dff63ec7adb576ca26a678d";
        binarySha256 = "634189866db1db635aed6257716969e87e7cde6830c26627795becbd2969e104";
      };
      aarch64-darwin = {
        asset = "gentle-ai_4.4.0_darwin_arm64.tar.gz";
        assetSha256 = "b6e00957eb81115f18e33197ae2035f75812a624c6d53e72826ecf7b4a635539";
        binarySha256 = "5bb53e7e32da585f08b668444209bde7a9b5c9c26489e2052bf180b05a2aab81";
      };
    };
  };
in
{
  stable = {
    source = "npm:gentle-pi@4.7.0";

    version = "4.7.0";
    rev = "8e11f0e2fb19af2a28233d1774848f7a3a33bbf1";
    archiveHash = "sha256-3nNC6jFpYO2UoJ9gl2Rjpgt3i55zExeNiDNmevlJDOY=";
    pnpmDepsHash = "sha256-IzSAJVOfq/LqgRIGMyBda+iEHypXUASnzl5vu8XQPjA=";
    gentleAi = gentleAi_4_4_0;
  };

  # Tracks gentle-shell's main the same way versions.nix's beta channel tracks
  # Gentle AI's own: a pin is how a flake expresses a branch, and refreshing
  # it is what letting Pi install the tip of main again would have done.
  #
  # This revision is the tip of gentle-shell's `main`, 204 commits past the
  # commit the `v4.7.0` tag peels to; `package.json` there still reads `4.7.0`,
  # the release `stable` above names on npm. The `-main.` prerelease label keeps a build
  # from here from being mistaken for that published release.
  #
  # The plugin installs Gentle AI v4.4.0 through `INSTALLER_VERSION` in
  # `scripts/gentle-ai-installer.mjs`. That matches this flake's stable channel;
  # selecting the separately pinned beta channel does not change the plugin's
  # installer target.
  main = {
    version = "4.7.0-main.b6f25565";
    rev = "b6f2556540ef2ca3fd8f686a4bb458f9c7390ddb";
    archiveHash = "sha256-bLxGm1NkfWEDHLIBtiNfBwaIh9gqrADcVdln16cavuE=";
    pnpmDepsHash = "sha256-WwHXiOokzoneIUqkjzSV8E9TP7+wL8B3xLr9wu70gJE=";
    gentleAi = gentleAi_4_4_0;
  };
}
