{
  lib,
  buildGoModule,
}:

buildGoModule {
  pname = "gentle-nix";

  # gentle-nix is this repository's own source, not a channel fetched from
  # somewhere else, so there is no releases file to read a version out of;
  # bump this by hand alongside a behavior change worth naming.
  version = "0.1.0";

  # Only what the Go build actually reads: go.mod, cmd, and internal. A Nix
  # module edit elsewhere in the repository (modules/, checks/, docs/, ...)
  # would otherwise still change this derivation's input hash and force an
  # unrelated rebuild of the one thing here that is genuinely expensive to
  # rebuild.
  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../go.mod
      ../cmd
      ../internal
    ];
  };

  proxyVendor = true;

  # The Go standard library is the only thing gentle-nix links against --
  # see the phase report for why "merge" stayed a Python subcommand rather
  # than pulling in a TOML dependency -- so there is nothing for
  # buildGoModule to vendor.
  vendorHash = null;

  subPackages = [ "cmd/gentle-nix" ];

  env.CGO_ENABLED = 0;

  ldflags = [
    "-s"
    "-w"
    "-X main.version=0.1.0"
  ];

  # go test ./... runs inside the build sandbox, against the same vendored
  # (here: dependency-free) module graph the binary itself is built from,
  # so a behavior regression fails the build rather than only a separate,
  # skippable check. buildGoModule's own default checkPhase narrows to
  # subPackages once that is set (it reuses the exact directory list the
  # build phase used), which would silently skip every internal/* test;
  # spelling checkPhase out here is what keeps the whole module covered.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    export GOFLAGS=''${GOFLAGS//-trimpath/}
    go test ./...
    runHook postCheck
  '';

  meta = {
    description = "Package-provisioning, retirement, and asset-copy helpers for Gentle AI's home-manager module";
    license = lib.licenses.mit;
    mainProgram = "gentle-nix";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
