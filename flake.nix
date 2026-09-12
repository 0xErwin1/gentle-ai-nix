{
  description = "Declarative Gentle AI integration for OpenCode and Home Manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      home-manager,
    }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          releases = import ./packages/versions.nix;
          engramReleases = import ./packages/engram-versions.nix;
          codegraphReleases = import ./packages/codegraph-versions.nix;
          gentleAiFor = release: pkgs.callPackage ./packages/gentle-ai.nix { inherit release; };
          engramFor = release: pkgs.callPackage ./packages/engram.nix { inherit release; };

          gentle-ai = gentleAiFor releases.contract;
          engram = engramFor engramReleases.stable;
          codegraph = pkgs.callPackage ./packages/codegraph.nix { release = codegraphReleases.stable; };
          gentle-nix = pkgs.callPackage ./packages/gentle-nix.nix { };
        in
        {
          inherit
            gentle-ai
            engram
            codegraph
            gentle-nix
            ;
          default = gentle-ai;

          # One package per release channel, so `programs.gentle-ai.package` can
          # take any of them and `nix run` can reach them by name.
          gentle-ai-stable = gentleAiFor releases.stable;
          gentle-ai-beta = gentleAiFor releases.beta;

          # Engram's candidate, selectable and never the default: its own
          # release notes ask that a stable installation stay available rather
          # than be replaced by it.
          engram-rc = engramFor engramReleases.rc;

          # Engram's Pi plugin, built from the same rc revision as engram-rc,
          # for Pi to install by local path when `engramRelease` moves off
          # stable.
          gentle-engram-pi = pkgs.callPackage ./packages/gentle-engram-pi.nix {
            release = engramReleases.rc;
          };

          # Reference documentation for every option this module declares.
          # Regenerate the committed copy with:
          #   nix build .#options-doc && cp result docs/options.md
          options-doc = import ./docs/options.nix {
            inherit pkgs;
            module = self.homeManagerModules.default;
          };
        }
      );

      homeManagerModules.default = import ./modules/home-manager.nix;

      checks = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        import ./checks {
          inherit
            home-manager
            pkgs
            self
            system
            ;
        }
      );

      # Generated documentation is excluded: it is rendered by nixosOptionsDoc,
      # so reformatting it only makes the committed copy differ from a fresh
      # render, which is exactly what the options-doc check exists to catch.
      formatter = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        pkgs.writeShellApplication {
          name = "gentle-ai-nix-fmt";
          text = ''exec ${nixpkgs.lib.getExe pkgs.nixfmt-tree} --excludes docs/options.md "$@"'';
        }
      );
    };
}
