# gentle-shell, the standalone launcher of the gentle-pi package, built from
# the same channel table `providers.pi.release` reads (packages/pi-versions.nix).
#
# This is not the Pi install source Pi provisions itself with: Pi installs
# gentle-pi into ~/.pi/agent from `release.source` (or the pinned git revision).
# This derivation builds the repository the same way a published npm package
# would carry it, so the `gentle-shell` binary can be put on PATH directly --
# Path A of the launcher's own documentation. It resolves `pi` from PATH at
# runtime, applies the version gate, and boots the session in its own home
# unless `--link` reuses ~/.pi/agent.
#
# The pnpm lockfile is the only lockfile the repository ships (there is no
# package-lock.json), so the build is pnpm's: fetchPnpmDeps vendors the store
# and pnpmConfigHook installs it offline with --ignore-scripts, which is what
# keeps the package's own `postinstall` (scripts/install-gentle-ai.mjs, which
# downloads the Gentle AI binary from a CDN) from running at build time. The
# launcher resolves and installs its own runtime the same way an npm-installed
# copy does.
#
# node_modules must travel with the result: the extensions this package loads
# import @earendil-works/pi-tui and @heyhuynhgiabuu/pi-pretty from the package
# root at runtime. The repository's pnpm-workspace.yaml already selects the
# hoisted linker, so they resolve from the installed tree without any symlink
# into the pnpm store.
{
  lib,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpm,
  pnpmConfigHook,
  nodejs,
  makeWrapper,
  stdenv,

  # Which channel to build from. The channels live in pi-versions.nix so that
  # adding one is a data entry rather than another copy of this expression.
  release ? (import ./pi-versions.nix).stable,
}:

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
    # `pi` on PATH to print --help, and it resolves `pi` from PATH itself at
    # boot, so PATH is only inherited, never extended here.
    mkdir -p $out/bin
    makeWrapper ${lib.getExe nodejs} $out/bin/gentle-shell \
      --add-flags "$out/lib/gentle-shell/bin/gentle-shell.mjs"

    runHook postInstall
  '';

  meta = {
    description = "Standalone gentle-shell launcher: resolves the Pi runtime and boots the Gentle AI session";
    license = lib.licenses.mit;
    mainProgram = "gentle-shell";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})
