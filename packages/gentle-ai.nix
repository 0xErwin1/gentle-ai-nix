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
    rev = "bf32f10e460388d79eb25e70b67d30e3a3d2e05c";
    hash = "sha256-D7Ql34R5sFA8/eCVcIoanmZgAhtizc7Fo4n2zasdihU=";
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
