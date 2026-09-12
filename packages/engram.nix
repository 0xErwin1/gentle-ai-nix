{
  lib,
  buildGoModule,
  fetchFromGitHub,
  git,

  # Which release to build. The channels live in engram-versions.nix so that
  # adding one is a data entry rather than another copy of this expression.
  release ? (import ./engram-versions.nix).stable,
}:

buildGoModule {
  pname = "engram";
  inherit (release) version vendorHash;

  src = import ./engram-src.nix { inherit fetchFromGitHub; } release;

  proxyVendor = true;

  subPackages = [ "cmd/engram" ];

  nativeCheckInputs = [ git ];

  env.CGO_ENABLED = 0;

  ldflags = [
    "-s"
    "-w"
    "-X main.version=${release.version}"
  ];

  meta = {
    description = "Persistent memory for AI coding agents";
    homepage = "https://github.com/Gentleman-Programming/engram";
    license = lib.licenses.mit;
    mainProgram = "engram";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
