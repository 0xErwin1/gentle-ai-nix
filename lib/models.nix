# Constructors for the model assignments the module's options take.
#
# Nothing here knows a provider id. Pi resolves them at runtime from the
# packages installed beside it -- ~/.pi/agent/models-store.json is keyed by
# exactly those ids -- so a table of them in this flake would be one machine's
# answer frozen into everyone's. `on` takes the id, `for` names the ones you
# actually run.
{ lib }:
let
  inherit (builtins)
    isAttrs
    isList
    isString
    substring
    stringLength
    ;

  # One model, without an effort: the half that does not depend on which
  # profile is asking. The module's own assignment type fills the missing
  # effort with null, so this is a complete assignment, not half of one.
  on = provider: model: { inherit provider model; };

  # The other half, on its own. A profile's `defaultEffort` is where a level
  # usually comes from; this is for the assignments that default never
  # reaches -- roles.<id>.model, for one.
  withEffort = effort: assignment: assignment // { inherit effort; };

  # The reasoning levels gentle-pi names, as functions. They are plain strings
  # applied as written: which levels a client accepts is that client's answer,
  # not this flake's, so nothing here narrows the set.
  levels = [
    "off"
    "minimal"
    "low"
    "medium"
    "high"
    "xhigh"
    "max"
  ];
  effort = lib.genAttrs levels withEffort;

  # "openai-codex" -> "OpenaiCodex", so the constructor reads onOpenaiCodex.
  # Separators are what a provider id is allowed to carry; anything else is
  # left in place, because inventing a name for it would be worse than an
  # attribute name that says what the id says.
  capitalize = part: lib.toUpper (substring 0 1 part) + substring 1 (stringLength part) part;
  camelCase =
    name:
    lib.concatStrings (
      map capitalize (
        lib.filter (part: part != "") (
          lib.splitString "-" (lib.replaceStrings [ "_" "." "/" ] [ "-" "-" "-" ] name)
        )
      )
    );

  # `for` is where the on<Provider> names come from without a table behind
  # them: a list gives each id its own mechanical name, an attribute set gives
  # the name you chose. Either way the ids are the ones you declared.
  for =
    spec:
    if isList spec then
      lib.listToAttrs (map (id: lib.nameValuePair ("on" + camelCase id) (on id)) (map requireId spec))
    else if isAttrs spec then
      lib.mapAttrs' (alias: id: lib.nameValuePair ("on" + camelCase alias) (on (requireId id))) spec
    else
      throw "models.for expects a list of provider ids or an attribute set of alias to provider id";
  requireId =
    id:
    if isString id && id != "" then
      id
    else
      throw "models.for expects non-empty provider ids; got ${builtins.toJSON id}";
in
{
  inherit
    on
    withEffort
    effort
    for
    ;
}
