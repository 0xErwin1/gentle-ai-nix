{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,

  # Which release to install. The channels live in codegraph-versions.nix so
  # that adding one is a data entry rather than another copy of this expression.
  release ? (import ./codegraph-versions.nix).stable,
}:

# Upstream ships a bundled Node runtime plus native addons per platform, so this
# fetches the prebuilt release archive for the host instead of building from
# npm. The npm build pulls arch-selected native and optional dependencies that
# are not cacheable for aarch64, which keeps CodeGraph off those hosts entirely;
# the prebuilt path works on every platform upstream publishes.
let
  # The archive name and the directory it unpacks to are the same per-platform
  # token, so both are derived from one table rather than kept in step by hand.
  platformTokens = {
    "x86_64-linux" = "linux-x64";
    "aarch64-linux" = "linux-arm64";
    "x86_64-darwin" = "darwin-x64";
    "aarch64-darwin" = "darwin-arm64";
  };
in
stdenv.mkDerivation (finalAttrs: {
  pname = "codegraph";
  inherit (release) version;

  src =
    finalAttrs.passthru.sources.${stdenv.hostPlatform.system}
      or (throw "Unsupported system: ${stdenv.hostPlatform.system}");

  sourceRoot = "codegraph-${platformTokens.${stdenv.hostPlatform.system}}";

  strictDeps = true;

  # The ELF interpreter and the shared libraries the native addons want are a
  # Linux concern; on Darwin the hook has nothing to rewrite and the C++ runtime
  # is not a separate output.
  nativeBuildInputs = [
    makeWrapper
  ]
  ++ lib.optional stdenv.hostPlatform.isLinux autoPatchelfHook;

  buildInputs = lib.optional stdenv.hostPlatform.isLinux stdenv.cc.cc.lib;

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/codegraph
    cp -r lib $out/lib/codegraph/lib
    cp node $out/lib/codegraph/node

    install -Dm 755 bin/codegraph $out/lib/codegraph/bin/codegraph

    mkdir -p $out/bin
    makeWrapper $out/lib/codegraph/bin/codegraph $out/bin/codegraph

    runHook postInstall
  '';

  passthru.sources = lib.mapAttrs (
    system: token:
    fetchurl {
      url = "https://github.com/colbymchenry/codegraph/releases/download/v${finalAttrs.version}/codegraph-${token}.tar.gz";
      hash = release.hashes.${system};
    }
  ) platformTokens;

  meta = {
    description = "Code intelligence and knowledge graph for any codebase (CLI + MCP)";
    homepage = "https://github.com/colbymchenry/codegraph";
    license = lib.licenses.mit;
    mainProgram = "codegraph";
    platforms = lib.attrNames platformTokens;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
