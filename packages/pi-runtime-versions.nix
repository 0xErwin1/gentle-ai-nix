# The Pi runtime the gentle-shell launcher runs, built by
# packages/pi-coding-agent.nix from the published npm tarball.
#
# The launcher would otherwise run the @earendil-works/pi-coding-agent peer
# its pnpm lockfile pins. Up to gentle-shell 4.4.0 that was 1.2.0, which
# delivers `session_start` to extensions loaded after gentle-pi seconds late,
# so the launcher is pointed at this Pi instead, through GENTLE_SHELL_PI. From
# gentle-shell's main lockfile pins 1.5.2, the same version as here, while the
# v4.7.0 tag still pins 1.4.0: the launcher carries this one so a main-channel
# build runs the Pi its own lockfile expects.
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
  version = "1.5.2";
  url = "https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-1.5.2.tgz";
  hash = "sha256-aRveGGJztFfZ0cQdD9R7V4U7XoXe0a3Rofa3jmbCYfQ=";
  npmDepsHash = "sha256-FG7/Bga+d+pO3AkowtcYMFJlHFPq2tVLt+WzHRLYl5o=";
}
