# gentle-shell, the standalone launcher of the gentle-pi package, built from
# the same channel table `providers.pi.release` reads (packages/pi-versions.nix).
#
# This is not the Pi install source Pi provisions itself with: Pi installs
# gentle-pi into ~/.pi/agent from `release.source` (or the pinned git revision).
# This derivation builds the repository the same way a published npm package
# would carry it, so the `gentle-shell` binary can be put on PATH directly --
# Path A of the launcher's own documentation. It applies the version gate and
# boots the session in its own home unless `--link` reuses ~/.pi/agent.
#
# The Pi it runs is resolved GENTLE_SHELL_PI first, then the adjacent peer,
# then PATH. pnpm installs the package's devDependencies, so
# @earendil-works/pi-coding-agent (an optional peer, at the version the
# lockfile pins) lands next to gentle-pi and is the fallback. When `pi` is
# given (the flake passes packages/pi-coding-agent.nix), the wrapper sets
# GENTLE_SHELL_PI to it by default instead, so a newer Pi than the lockfile's
# runs; a GENTLE_SHELL_PI already in the environment still wins. Either way
# Pi runs under Node, which is what makes the extensions' child processes
# work: gentle-pi spawns helpers such as its native audio worker through
# process.execPath, which under a standalone Pi binary is Pi itself rather
# than Node.
#
# The pnpm lockfile is the only lockfile the repository ships (there is no
# package-lock.json), so the build is pnpm's: fetchPnpmDeps vendors the store
# and pnpmConfigHook installs it offline with --ignore-scripts, which is what
# keeps the package's own `postinstall` (scripts/install-gentle-ai.mjs, which
# downloads the Gentle AI binary from a CDN) from running at build time.
# What that script would have installed is placed here instead: the official
# release archive for this system, fetched with its pinned digest, unpacked to
# `.gentle-ai/v<version>/gentle-ai` beside the canonical `integrity.json` the
# runtime resolver verifies. A store path is read-only, so a launcher that
# found no runtime could never install one at boot; carrying it is what makes
# `resolveGentleAiBinary()` succeed from the store.
#
# node_modules must travel with the result: the extensions this package loads
# import @earendil-works/pi-tui and @heyhuynhgiabuu/pi-pretty from the package
# root at runtime. The repository's pnpm-workspace.yaml already selects the
# hoisted linker, so they resolve from the installed tree without any symlink
# into the pnpm store.
{
  lib,
  fetchFromGitHub,
  fetchurl,
  fetchPnpmDeps,
  pnpm,
  pnpmConfigHook,
  nodejs,
  makeWrapper,
  stdenv,

  # Which channel to build from. The channels live in pi-versions.nix so that
  # adding one is a data entry rather than another copy of this expression.
  release ? (import ./pi-versions.nix).stable,

  # The Pi to run instead of the lockfile's peer: a package with `bin/pi`,
  # exported to the launcher as GENTLE_SHELL_PI. Null keeps the peer.
  pi ? null,
}:

let
  # The runtime this revision's installer pins, for the system being built.
  # pi-versions.nix records it per channel because the installer version is
  # a property of the gentle-shell revision, not of this flake.
  gentleAi = release.gentleAi;
  gentleAiAsset =
    gentleAi.assets.${stdenv.hostPlatform.system}
      or (throw "gentle-shell: no pinned Gentle AI ${gentleAi.version} asset for ${stdenv.hostPlatform.system}");
  gentleAiArchive = fetchurl {
    url = "https://github.com/Gentleman-Programming/gentle-ai/releases/download/v${gentleAi.version}/${gentleAiAsset.asset}";
    sha256 = gentleAiAsset.assetSha256;
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "gentle-shell";
  inherit (release) version;

  src = fetchFromGitHub {
    owner = "Gentleman-Programming";
    repo = "gentle-shell";
    inherit (release) rev;
    hash = release.archiveHash;
  };

  nativeBuildInputs = [
    nodejs
    pnpmConfigHook
    pnpm
    makeWrapper
  ];

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    # pnpm 11 (the version this nixpkgs pin provides) requires fetcherVersion
    # 4, which dumps the store's SQLite index as SQL for reproducibility.
    fetcherVersion = 4;
    hash = release.pnpmDepsHash;
  };

  # The repository ships its generated runtime modules (runtime/*.mjs) already
  # built from lib/*.ts, and `pnpm run build:runtime-modules` only rewrites
  # them in place, so there is no compile step: the tree is the artifact.
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    # The whole tree, node_modules included: the launcher computes the package
    # root from its own location (bin/../) and loads extensions, themes,
    # prompts and skills relative to it, so the layout inside the store must
    # stay the one package.json describes.
    mkdir -p $out/lib
    cp -r . $out/lib/gentle-shell

    # The entry point carries a `#!/usr/bin/env node` shebang but resolves its
    # imports relative to its own path, so it cannot be copied to bin/ and
    # wrapped there: the wrapper has to execute it where it lives. It needs no
    # `pi` on PATH: it runs GENTLE_SHELL_PI when `pi` is given, the adjacent
    # Pi peer otherwise, so PATH is only inherited, never extended here.
    mkdir -p $out/bin
    makeWrapper ${lib.getExe nodejs} $out/bin/gentle-shell \
      --add-flags "$out/lib/gentle-shell/bin/gentle-shell.mjs" ${
        lib.optionalString (pi != null) "--set-default GENTLE_SHELL_PI ${lib.getExe' pi "pi"}"
      }

    runHook postInstall
  '';

  # The runtime goes in after fixup, not during install: strip and patchelf
  # would rewrite the binary, and the resolver refuses any binary whose
  # digest differs from `binarySha256`. The release binary is static, so it
  # needs neither.
  postFixup = ''
    runtime="$out/lib/gentle-shell/.gentle-ai/v${gentleAi.version}"
    mkdir -p "$runtime" unpacked-gentle-ai
    tar -xzf ${gentleAiArchive} -C unpacked-gentle-ai gentle-ai
    install -m 0755 unpacked-gentle-ai/gentle-ai "$runtime/gentle-ai"

    actual="$(sha256sum "$runtime/gentle-ai" | cut -d' ' -f1)"
    if [ "$actual" != ${lib.escapeShellArg gentleAiAsset.binarySha256} ]; then
      echo "gentle-ai binary digest $actual does not match the pinned binarySha256" >&2
      exit 1
    fi

    # Written by JSON.stringify over the fields in the order the installer's
    # signedReleaseManifest builds them, the same call it makes, so the bytes
    # cannot drift from the canonical form the resolver compares against.
    GENTLE_AI_VERSION=${lib.escapeShellArg gentleAi.version} \
    GENTLE_AI_ASSET=${lib.escapeShellArg gentleAiAsset.asset} \
    GENTLE_AI_ASSET_SHA256=${lib.escapeShellArg gentleAiAsset.assetSha256} \
    GENTLE_AI_BINARY_SHA256=${lib.escapeShellArg gentleAiAsset.binarySha256} \
      node -e 'process.stdout.write(JSON.stringify({
        version: process.env.GENTLE_AI_VERSION,
        asset: process.env.GENTLE_AI_ASSET,
        assetSha256: process.env.GENTLE_AI_ASSET_SHA256,
        binarySha256: process.env.GENTLE_AI_BINARY_SHA256,
      }) + "\n")' > "$runtime/integrity.json"
  '';

  # Proves the carried runtime is the one the package itself accepts: the
  # resolver throws unless the layout, modes, manifest and digests all match.
  # HOME points at an empty directory so no developer binary override from
  # the builder's environment can stand in for the pinned one.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    HOME="$(mktemp -d)" node --input-type=module -e '
      const { resolveGentleAiBinary } = await import(process.argv[1]);
      const path = resolveGentleAiBinary();
      if (path !== process.argv[2]) throw new Error(`resolved ''${path}, expected ''${process.argv[2]}`);
    ' "$out/lib/gentle-shell/runtime/gentle-ai-binary.mjs" \
      "$out/lib/gentle-shell/.gentle-ai/v${gentleAi.version}/gentle-ai"

    runHook postInstallCheck
  '';

  meta = {
    description = "Standalone gentle-shell launcher: resolves the Pi runtime and boots the Gentle AI session";
    license = lib.licenses.mit;
    mainProgram = "gentle-shell";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})
