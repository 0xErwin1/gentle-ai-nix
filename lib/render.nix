# Renders a Gentle AI desired-state document into the tree it describes.
#
# Nothing here knows what an agent, a skill or a command is. Gentle AI owns
# those semantics and this flake asks it for the result, so a change to how
# Gentle AI renders its own assets arrives with the package instead of needing a
# matching change here.
{
  lib,
  runCommandLocal,
  writeText,
}:

{
  # The desired-state document, as an attribute set. It is serialised verbatim,
  # so every field the contract accepts is expressible without this flake
  # knowing the field exists.
  document,

  # Where the rendered configuration will finally live. Rendered content records
  # absolute paths to its own files, so it has to be built for the directory it
  # is projected into rather than for the build sandbox.
  homeDirectory,

  gentle-ai,

  name ? "gentle-ai-config",
}:

let
  documentFile = writeText "gentle-ai-document.json" (builtins.toJSON document);
in
runCommandLocal name
  {
    inherit documentFile homeDirectory;
    passthru = { inherit document; };
    meta.description = "Gentle AI configuration rendered from a declarative document";
  }
  ''
    # `config render` writes only into the staging root, but the injectors it
    # runs still resolve a home directory. Pointing it at a private one keeps the
    # build from depending on whatever the sandbox happens to expose.
    export HOME="$PWD/render-home"
    mkdir -p "$HOME" "$out/tree"

    # Gentle AI reports a rejected document as diagnostics on stdout and fails.
    # The report is captured rather than streamed so a successful render leaves
    # it beside the tree, and a rejected one still reaches the build log instead
    # of disappearing into a file the failed build never produces.
    if ! ${lib.getExe gentle-ai} config render \
      --config "$documentFile" \
      --home "$HOME" \
      --destination "$homeDirectory" \
      --stage "$out/tree" \
      > report.json
    then
      echo "gentle-ai rejected the declarative document:" >&2
      cat report.json >&2
      exit 1
    fi

    cp report.json "$out/manifest.json"
  ''
