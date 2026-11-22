# The Pi runtime the gentle-shell launcher runs, built by
# packages/pi-coding-agent.nix from the published npm tarball.
#
# The launcher would otherwise run the @earendil-works/pi-coding-agent peer
# its pnpm lockfile pins. Up to gentle-shell 4.4.0 that was 1.2.0, which
# delivers `session_start` to extensions loaded after gentle-pi seconds late,
# so the launcher is pointed at this Pi instead, through GENTLE_SHELL_PI. From
# gentle-shell v5.0.0 pins 1.6.0; the channel this flake still ships (v4.9.0's
# main) pins 1.5.2, so the launcher deliberately runs the newer runtime until
# the gentle-shell v5.0.0 package lands -- the launcher check proves it resolves
# and reports the version we pin.
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
  version = "1.6.0";
  url = "https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-1.6.0.tgz";
  hash = "sha256-hdXeQE4BnoUMkO6axtxsFiQNoSL9zgMUiVYIFkAwM2s=";
  npmDepsHash = "sha256-T85ibShm4aHfcM4Xg8VlEoqFqZuou4m13tqFd141Usw=";
}
