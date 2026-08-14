{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "gentle-ai";
  version = "2.3.0";

  src = fetchFromGitHub {
    owner = "Gentleman-Programming";
    repo = "gentle-ai";
    rev = "v${version}";
    hash = "sha256-APKVSlsz8BOBDXQGNNOCdpgyFKSiZwku1Y1c3ZVzYv8=";
  };

  vendorHash = "sha256-qeeD+omJzlqolHGzGx2E60fEucjweb62UQY3N/0xxgs=";
  proxyVendor = true;

  subPackages = [ "cmd/gentle-ai" ];

  env.CGO_ENABLED = 0;

  ldflags = [
    "-s"
    "-w"
    "-X main.version=${version}"
  ];

  meta = {
    description = "Multi-client AI coding harness toolkit";
    homepage = "https://github.com/Gentleman-Programming/gentle-ai";
    license = lib.licenses.mit;
    mainProgram = "gentle-ai";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
