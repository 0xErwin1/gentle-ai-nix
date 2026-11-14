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
# `stable` is npm's `gentle-pi@4.8.0`, which needs Node >= 22.19 and Pi >= 1.2.0.
# Pinning the npm source makes a switch
# converge on the release this flake tested, rather than whatever `latest`
# resolves to when Pi runs its installer. `rev` is the commit the `v4.8.0`
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

  gentleAi_4_5_0 = {
    version = "4.5.0";
    assets = {
      x86_64-linux = {
        asset = "gentle-ai_4.5.0_linux_amd64.tar.gz";
        assetSha256 = "6dfd0a6fc27122541d20da4b65ec449763e672051daf2069611ca33134270c5b";
        binarySha256 = "76295de0b0abae140f0356d2da5a9955f8770f54c9d7a9b7ac768821126d5fe3";
      };
      aarch64-linux = {
        asset = "gentle-ai_4.5.0_linux_arm64.tar.gz";
        assetSha256 = "a0a8bf642abbdcb8b93013ab3f2ff90d01c9087a27927c93d980ddb57de74378";
        binarySha256 = "7820589547c4dddcc130532643aa5ba001667525d2a0fbec1189a8398ceacfa6";
      };
      x86_64-darwin = {
        asset = "gentle-ai_4.5.0_darwin_amd64.tar.gz";
        assetSha256 = "45c65d04fb429f8065682360d9a3c650d988842fe62f843b36598953c8acc0a1";
        binarySha256 = "4b89ffad9ee7fb1ed70058bd6f73914dc6256aea6c79998838ca2d2c363f24b4";
      };
      aarch64-darwin = {
        asset = "gentle-ai_4.5.0_darwin_arm64.tar.gz";
        assetSha256 = "b8522090394d93aa5dd8d3f5c80982e6163c4d5d2e7952c3c1917da8a150ae31";
        binarySha256 = "699a44555e544447f5db342b918aa8558b5e0e3213bb9404b66863319b1f58d4";
      };
    };
  };
in
{
  stable = {
    source = "npm:gentle-pi@4.8.0";

    version = "4.8.0";
    rev = "3dc9029755912358d0a172b4972e5842c239570c";
    archiveHash = "sha256-omnDN+63kUj8clSzm3cF4z2sOGUVzXJzMvWmXSv871g=";
    pnpmDepsHash = "sha256-WwHXiOokzoneIUqkjzSV8E9TP7+wL8B3xLr9wu70gJE=";
    gentleAi = gentleAi_4_5_0;
  };

  # Tracks gentle-shell's main the same way versions.nix's beta channel tracks
  # Gentle AI's own: a pin is how a flake expresses a branch, and refreshing
  # it is what letting Pi install the tip of main again would have done.
  #
  # This revision is the tip of gentle-shell's `main`, which is the commit the
  # `v4.8.0` tag peels to; `package.json` there reads `4.8.0`,
  # the release `stable` above names on npm. The `-main.` prerelease label keeps a build
  # from here from being mistaken for that published release.
  #
  # The plugin installs Gentle AI v4.5.0 through `INSTALLER_VERSION` in
  # `scripts/gentle-ai-installer.mjs`. That matches this flake's stable channel;
  # selecting the separately pinned beta channel does not change the plugin's
  # installer target.
  main = {
    version = "4.8.0-main.3dc90297";
    rev = "3dc9029755912358d0a172b4972e5842c239570c";
    archiveHash = "sha256-omnDN+63kUj8clSzm3cF4z2sOGUVzXJzMvWmXSv871g=";
    pnpmDepsHash = "sha256-WwHXiOokzoneIUqkjzSV8E9TP7+wL8B3xLr9wu70gJE=";
    gentleAi = gentleAi_4_5_0;
  };
}
