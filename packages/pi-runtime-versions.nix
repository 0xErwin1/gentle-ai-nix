# The Pi runtime the gentle-shell launcher runs, built by
# packages/pi-coding-agent.nix from the published npm tarball.
#
# The launcher would otherwise run the @earendil-works/pi-coding-agent peer
# its pnpm lockfile pins. Up to gentle-shell 4.4.0 that was 1.2.0, which
# delivers `session_start` to extensions loaded after gentle-pi seconds late,
# so the launcher is pointed at this Pi instead, through GENTLE_SHELL_PI. From
# gentle-shell's own lockfile pins 1.6.0; the launcher runs 1.7.0 deliberately,
# ahead of it, because the runtime is resolved by the launcher rather than by the
# package's peer -- the launcher check proves it resolves and reports this exact
# version.
#
# The tarball ships no lockfile, so one is generated and committed beside the
# derivation (packages/pi-coding-agent/package-lock.json). Refresh with:
#   curl -sSfLO https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-<version>.tgz
#   nix hash file --sri pi-coding-agent-<version>.tgz                       # hash
#   tar -xzf pi-coding-agent-<version>.tgz && cd package
#   npm install --package-lock-only --ignore-scripts                        # with Node >= 22.19
#   cp package-lock.json <repo>/packages/pi-coding-agent/package-lock.json
# then build `.#pi-coding-agent` with `npmDepsHash = lib.fakeHash` and take
# the hash the mismatch reports.
{
  version = "1.7.0";
  url = "https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-1.7.0.tgz";
  hash = "sha256-ywMf85t10EJ5fXSAM5h92cDlZzczlxcsC07WYdC/SCQ=";
  npmDepsHash = "sha256-r/4jcF6JGX9+iBtsQEZFc8h11gqgDTFiqeuWyJ8tNco=";
}
