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
          gentle-ai = pkgs.callPackage ./packages/gentle-ai.nix { };
          engram = pkgs.callPackage ./packages/engram.nix { };
        in
        {
          inherit gentle-ai engram;
          default = gentle-ai;

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
