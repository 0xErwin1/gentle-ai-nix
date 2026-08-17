{
  lib,
  buildGoModule,
  fetchFromGitHub,

  # Which release to build. The channels live in versions.nix so that adding one
  # is a data entry rather than another copy of this expression.
  release ? (import ./versions.nix).contract,
}:

buildGoModule {
  pname = "gentle-ai";
  inherit (release) version vendorHash;

  src = fetchFromGitHub {
    inherit (release) owner rev hash;
    repo = "gentle-ai";
  };

  proxyVendor = true;

  subPackages = [ "cmd/gentle-ai" ];

  env.CGO_ENABLED = 0;

  ldflags = [
    "-s"
    "-w"
    "-X main.version=${release.version}"
  ];

  meta = {
    description = "Multi-client AI coding harness toolkit";
    homepage = "https://github.com/Gentleman-Programming/gentle-ai";
    license = lib.licenses.mit;
    mainProgram = "gentle-ai";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
