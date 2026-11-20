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
# `stable` is npm's `gentle-pi@4.9.0`, which needs Node >= 22.19 and Pi >= 1.2.0.
# Pinning the npm source makes a switch
# converge on the release this flake tested, rather than whatever `latest`
# resolves to when Pi runs its installer. `rev` is the commit the `v4.9.0`
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

  gentleAi_4_6_0 = {
    version = "4.6.0";
    assets = {
      x86_64-linux = {
        asset = "gentle-ai_4.6.0_linux_amd64.tar.gz";
        assetSha256 = "c645e8551f6e3f79831b142a6b087795dc3217e02e9dafb5b701dc4373b33e7d";
        binarySha256 = "dc649e16c395390d42735fb0230b1a5df4269298fe8f3f14cdb3166ba1af1308";
      };
      aarch64-linux = {
        asset = "gentle-ai_4.6.0_linux_arm64.tar.gz";
        assetSha256 = "ab5a2f55ff41281bc41baea2ec730dcb05e8f55f3a9eea201c001693be490d32";
        binarySha256 = "d02602ce98759cc3a0f7896557a729b3bf1a60c458e757ff09d8de34d4b93589";
      };
      x86_64-darwin = {
        asset = "gentle-ai_4.6.0_darwin_amd64.tar.gz";
        assetSha256 = "57cbb8e91fe80268b64eeeba9d1f3b8645d3a36db262cbf3220143a594bf214b";
        binarySha256 = "be1cb74d7e0b647d2e175c1aca71d5feb792130e4dabca465f37dabb13c3324e";
      };
      aarch64-darwin = {
        asset = "gentle-ai_4.6.0_darwin_arm64.tar.gz";
        assetSha256 = "7e939ef7593b84e52ea8c563064c0ed0fdb228fc1b6378fa0c09676695c72aac";
        binarySha256 = "3c60ec6acd063245b85a9778ad670782c0dc65eae374f671bf160092cbb78e64";
      };
    };
  };
in
{
  stable = {
    source = "npm:gentle-pi@4.9.0";

    version = "4.9.0";
    rev = "ce64a9a708e50c0ca899c8023140e63f29f293e1";
    archiveHash = "sha256-8YVz9EjofyyJ7p+qnDhLXharStN7nrX1BW+rrdCc7n0=";
    pnpmDepsHash = "sha256-WwHXiOokzoneIUqkjzSV8E9TP7+wL8B3xLr9wu70gJE=";
    gentleAi = gentleAi_4_6_0;
  };

  # Tracks gentle-shell's main the same way versions.nix's beta channel tracks
  # Gentle AI's own: a pin is how a flake expresses a branch, and refreshing
  # it is what letting Pi install the tip of main again would have done.
  #
  # This revision is the tip of gentle-shell's `main`, three commits past the
  # commit the `v4.9.0` tag peels to; `package.json` there reads `4.9.0`,
  # the release `stable` above names on npm. The `-main.` prerelease label keeps a build
  # from here from being mistaken for that published release.
  #
  # The plugin installs Gentle AI v4.6.0 through `INSTALLER_VERSION` in
  # `scripts/gentle-ai-installer.mjs`. That matches this flake's stable channel;
  # selecting the separately pinned beta channel does not change the plugin's
  # installer target.
  main = {
    version = "4.9.0-main.21c73c13";
    rev = "21c73c1349905610646dac03564e474493c37255";
    archiveHash = "sha256-ueS5iCpaZINepvh0YIRLr8Cj8l1VcbkBQbfXicm7HxA=";
    pnpmDepsHash = "sha256-WwHXiOokzoneIUqkjzSV8E9TP7+wL8B3xLr9wu70gJE=";
    gentleAi = gentleAi_4_6_0;
  };
}
