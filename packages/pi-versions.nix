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
# `stable` is npm's `gentle-pi@4.3.0`, which needs Node >= 22.19 and Pi >= 1.2.0.
# Pinning the npm source makes a switch
# converge on the release this flake tested, rather than whatever `latest`
# resolves to when Pi runs its installer. `rev` is the commit the `v4.3.0`
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
  gentleAi_4_2_0 = {
    version = "4.2.0";
    assets = {
      x86_64-linux = {
        asset = "gentle-ai_4.2.0_linux_amd64.tar.gz";
        assetSha256 = "552c1642fd10f5d96cfe9bb1cc3b66b30eb47d3074cc7ca0559b598eb086defc";
        binarySha256 = "9212c7b16ea9abfe93e3a16b29d8390e7762b5c07730cf05df1f3e7892ff96a4";
      };
      aarch64-linux = {
        asset = "gentle-ai_4.2.0_linux_arm64.tar.gz";
        assetSha256 = "2bebe91b8808ce48d86c4d3700d098e37cb6b0658f196c666d9deeeb7c7c1a7a";
        binarySha256 = "e1b88bd3dcdc8a15ddbcaf8731fd44561f05b06fbcb59d9385bbe82c4b96b5c4";
      };
      x86_64-darwin = {
        asset = "gentle-ai_4.2.0_darwin_amd64.tar.gz";
        assetSha256 = "8f6a91e0f99cac3aea138705d7d222ea342f53a47602d48cb01488952a1c12f8";
        binarySha256 = "784855e99f1bc45579f01420c923b7dc1dc6d63492cdc0174a9a32e611849e57";
      };
      aarch64-darwin = {
        asset = "gentle-ai_4.2.0_darwin_arm64.tar.gz";
        assetSha256 = "d5e9a6521de5f08a393635f083f64dc7afc1b8e97884f7aab5ae5eb1f17c7f37";
        binarySha256 = "8ea490287ef796848b0d305cf2b26265e360d3f400efc016972844498fb87097";
      };
    };
  };
in
{
  stable = {
    source = "npm:gentle-pi@4.3.0";

    version = "4.3.0";
    rev = "d5d692a6888da9e9844e7e443ee30991fa4b9d14";
    archiveHash = "sha256-rmuIk4IudViiz4nDJ646lCOHLfHIAboKmH/RdIqkpf4=";
    pnpmDepsHash = "sha256-7/qFx9LTDo717xj+iojzyx2gXiUW20B8CmTGN9yO9NI=";
    gentleAi = gentleAi_4_2_0;
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
    archiveHash = "sha256-VEwmdk5o+YBhZIEe48+nKlsO2qAtkUvTurqHFneZVzw=";
    pnpmDepsHash = "sha256-7/qFx9LTDo717xj+iojzyx2gXiUW20B8CmTGN9yO9NI=";
    gentleAi = gentleAi_4_2_0;
  };
}
