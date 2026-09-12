{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchurl,
  makeWrapper,
  nodejs,

  # Which Engram release to take the Pi plugin from. The channels live in
  # engram-versions.nix, the same table engram.nix reads: the binary and this
  # plugin are built from the same revision, because a store with one
  # Engram's wire format and another's Pi plugin is not a configuration
  # anyone chose on purpose.
  release ? (import ./engram-versions.nix).rc,
}:

# Engram's Pi plugin lives at plugin/pi inside the same repository the Go
# binary is built from. Pi installs a plugin by registering its directory in
# place rather than running `npm install`, so what has to exist here is the
# plugin's own tree plus its one dependency vendored under node_modules --
# not a build, just the files Pi already knows how to read.
let
  src = import ./engram-src.nix { inherit fetchFromGitHub; } release;

  # typebox is the plugin's only dependency (`typebox ^1.1.38` in its
  # package.json) and has none of its own, so fetching and unpacking the npm
  # tarball is the whole of "installing" it -- no lockfile, no resolver, no
  # network beyond this one fixed-output fetch.
  typebox = fetchurl {
    url = "https://registry.npmjs.org/typebox/-/typebox-1.3.30.tgz";
    hash = "sha512-vRmBLzlaq9O9dvfGmI5CssLGvDC/R594kH6N/Q1uUU5VPO3PTgQMlWe/UVNdNVTr2EET+FX8BWZkFdYgxTglbQ==";
  };
in
stdenv.mkDerivation {
  pname = "gentle-engram-pi";
  inherit (release) version;

  inherit src;

  nativeBuildInputs = [ makeWrapper ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out"
    cp -r plugin/pi/. "$out/"

    mkdir -p "$out/node_modules/typebox"
    tar -xzf ${typebox} -C "$out/node_modules/typebox" --strip-components=1

    # gentle-engram's own init step is normally reached through
    # `npm exec ... pi-engram init`, but npm exec always tries to chmod the
    # spec it links into ~/.npm/_npx before running it, and a spec that is a
    # store path resolves that chmod into the read-only store -- an EROFS a
    # local install can never get past. Shipping this wrapper is what lets a
    # local source run `<path>/bin/pi-engram init` directly instead, the same
    # entry point cli.js already gives npm exec.
    test -f "$out/cli.js" || { echo "gentle-engram's cli.js moved; the wrapper would point at nothing" >&2; exit 1; }
    mkdir -p "$out/bin"
    makeWrapper ${lib.getExe' nodejs "node"} "$out/bin/pi-engram" --add-flags "$out/cli.js"

    runHook postInstall
  '';

  meta = {
    description = "Engram's Pi plugin, packaged for Pi to install by local path instead of npm";
    homepage = "https://github.com/Gentleman-Programming/engram";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
