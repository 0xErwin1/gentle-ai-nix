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
# `stable` is npm's `gentle-pi@4.5.1`, which needs Node >= 22.19 and Pi >= 1.2.0.
# Pinning the npm source makes a switch
# converge on the release this flake tested, rather than whatever `latest`
# resolves to when Pi runs its installer. `rev` is the commit the `v4.5.1`
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
  # Both channels currently pin the same installer version, so they share
  # one table; a channel whose revision moves it gets its own.
  gentleAi_4_3_1 = {
    version = "4.3.1";
    assets = {
      x86_64-linux = {
        asset = "gentle-ai_4.3.1_linux_amd64.tar.gz";
        assetSha256 = "04ec685c56b42c29dff6db10fc7dc2c730217dc9c96736e53ad2acf3226dafb7";
        binarySha256 = "86248792bde3fe5e9ca93b128c07e7caa6a5b31fac0f9fc84b5b3011b123cb90";
      };
      aarch64-linux = {
        asset = "gentle-ai_4.3.1_linux_arm64.tar.gz";
        assetSha256 = "99e7d313a2ff85eaf23a6415e9b3aae67bf74c2fa169b21b93070ada7613f6a0";
        binarySha256 = "df3580506bb5ea63cc4ef5ccebe8b68cfedf66b72f3b51f84ff393183d8cea2b";
      };
      x86_64-darwin = {
        asset = "gentle-ai_4.3.1_darwin_amd64.tar.gz";
        assetSha256 = "6cf57fee0574daef2abed07f54a355fec3b93ac8f01733dc6c4d3674f1746112";
        binarySha256 = "ca44c3fce186b63a7e7ad455c338133ba1982f4a13485301ce4d66edb73d2928";
      };
      aarch64-darwin = {
        asset = "gentle-ai_4.3.1_darwin_arm64.tar.gz";
        assetSha256 = "13e8828447f9081465ee0c35a61b24fb49296d51a310c6999227e2aed178956b";
        binarySha256 = "749d08062b0dec13681678a1a1c018613d223ddcca47b5f27681b1d8ab5d14c2";
      };
    };
  };
in
{
  stable = {
    source = "npm:gentle-pi@4.5.1";

    version = "4.5.1";
    rev = "e8b2814934f98ded9199f49bde8f482c97eece3a";
    archiveHash = "sha256-rjm8PVesjSiX3oYpbj9La8Bj+UzEVPZFoHjmcy14cok=";
    pnpmDepsHash = "sha256-IzSAJVOfq/LqgRIGMyBda+iEHypXUASnzl5vu8XQPjA=";
    gentleAi = gentleAi_4_3_1;
  };

  # Tracks gentle-shell's main the same way versions.nix's beta channel tracks
  # Gentle AI's own: a pin is how a flake expresses a branch, and refreshing
  # it is what letting Pi install the tip of main again would have done.
  #
  # This revision is the tip of gentle-shell's `main`, the same commit the
  # `v4.5.1` tag peels to; `package.json` there reads `4.5.1`,
  # the release `stable` above names on npm. The `-main.` prerelease label keeps a build
  # from here from being mistaken for that published release.
  #
  # The plugin installs Gentle AI v4.3.1 through `INSTALLER_VERSION` in
  # `scripts/gentle-ai-installer.mjs`. That matches this flake's stable channel;
  # selecting the separately pinned beta channel does not change the plugin's
  # installer target.
  main = {
    version = "4.5.1-main.e8b28149";
    rev = "e8b2814934f98ded9199f49bde8f482c97eece3a";
    archiveHash = "sha256-rjm8PVesjSiX3oYpbj9La8Bj+UzEVPZFoHjmcy14cok=";
    pnpmDepsHash = "sha256-IzSAJVOfq/LqgRIGMyBda+iEHypXUASnzl5vu8XQPjA=";
    gentleAi = gentleAi_4_3_1;
  };
}
