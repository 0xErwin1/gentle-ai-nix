# Pi itself (@earendil-works/pi-coding-agent), built from the published npm
# tarball the release table in packages/pi-runtime-versions.nix pins.
#
# The tarball already carries the compiled `dist/`, so there is no build step:
# buildNpmPackage only installs the dependencies from the lockfile committed
# beside this file (the tarball ships none), offline and with --ignore-scripts.
# `bin/pi` runs `dist/bundle/cli.js` with this derivation's Node, which is
# what gentle-shell needs: extensions spawn helpers through process.execPath,
# and under Node that is Node rather than a standalone Pi binary.
{
  lib,
  buildNpmPackage,
  fetchurl,
  makeWrapper,
  nodejs,
  release ? import ./pi-runtime-versions.nix,
}:

buildNpmPackage {
  pname = "pi-coding-agent";
  inherit (release) version npmDepsHash;
  inherit nodejs;

  src = fetchurl {
    inherit (release) url hash;
  };
  sourceRoot = "package";

  postPatch = ''
    cp ${./pi-coding-agent/package-lock.json} package-lock.json
  '';

  nativeBuildInputs = [ makeWrapper ];

  npmFlags = [ "--ignore-scripts" ];
  dontNpmBuild = true;

  # npmInstallHook links the package's own `bin` entries; they are replaced by
  # an explicit wrapper so the Node that runs Pi is this derivation's, not
  # whichever `node` a shebang finds on PATH.
  postInstall = ''
    rm -rf $out/bin
    makeWrapper ${lib.getExe nodejs} $out/bin/pi \
      --add-flags "$out/lib/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js"
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    [ "$(HOME="$(mktemp -d)" $out/bin/pi --version)" = ${lib.escapeShellArg release.version} ]
    runHook postInstallCheck
  '';

  meta = {
    description = "Pi coding agent, run under Node";
    homepage = "https://www.npmjs.com/package/@earendil-works/pi-coding-agent";
    license = lib.licenses.mit;
    mainProgram = "pi";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
