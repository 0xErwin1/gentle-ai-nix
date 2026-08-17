{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

# This flake renders through `gentle-ai config render`, the declarative
# configuration contract from Gentle AI issue #3248. The contract is not in an
# upstream release yet, so the package is pinned to the branch chain that
# carries it. Move owner, rev and hash back to an upstream tag once it merges.
buildGoModule rec {
  pname = "gentle-ai";
  version = "2.3.0-unstable-declarative-config";

  src = fetchFromGitHub {
    owner = "0xErwin1";
    repo = "gentle-ai";
    rev = "24be993028316618460a9f2bf947ef95d790572b";
    hash = "sha256-lrlsm90xfHp6CyYYxb01/ub3N06ANIH/OE5U3T+IGKI=";
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
