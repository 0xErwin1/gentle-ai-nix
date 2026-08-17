# Renders the module's own option declarations into reference documentation.
#
# The reference is generated rather than written so it cannot describe an option
# the module does not have, or miss one it does. A check compares the committed
# copy against this output, which is what keeps the two from drifting.
{ pkgs, module }:

let
  inherit (pkgs) lib;

  # The module is evaluated on its own rather than through Home Manager: the
  # reference documents what this flake declares, and pulling in Home Manager's
  # entire option set would bury it.
  evaluated = lib.evalModules {
    modules = [
      module
      {
        options._module.args = lib.mkOption {
          type = lib.types.attrsOf lib.types.raw;
          internal = true;
        };
      }
      {
        config._module.args = { inherit pkgs; };
        config._module.check = false;
      }
    ];
  };
in
(pkgs.nixosOptionsDoc {
  options = removeAttrs evaluated.options [ "_module" ];
  warningsAreErrors = false;
}).optionsCommonMark
