{
  lib,
  buildGoModule,
  fetchFromGitHub,
  git,
}:

buildGoModule rec {
  pname = "engram";
  version = "1.20.0";

  src = fetchFromGitHub {
    owner = "Gentleman-Programming";
    repo = "engram";
    rev = "v${version}";
    hash = "sha256-qdKAll7N0HtJRbZYilzatVCUz1Tr+pqM217Y8O+Csjs=";
  };

  vendorHash = "sha256-JBwLW62M6SFXqgYKeSdUI136B42f3h43V9ud1qUW484=";
  proxyVendor = true;

  subPackages = [ "cmd/engram" ];

  nativeCheckInputs = [ git ];

  env.CGO_ENABLED = 0;

  ldflags = [
    "-s"
    "-w"
    "-X main.version=${version}"
  ];

  meta = {
    description = "Persistent memory for AI coding agents";
    homepage = "https://github.com/Gentleman-Programming/engram";
    license = lib.licenses.mit;
    mainProgram = "engram";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
