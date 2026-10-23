# The Pi runtime the gentle-shell launcher runs, built by
# packages/pi-coding-agent.nix from the published npm tarball.
#
# The launcher would otherwise run the @earendil-works/pi-coding-agent peer
# its pnpm lockfile pins (1.2.0 at gentle-shell 4.3.0), which delivers
# `session_start` to extensions loaded after gentle-pi seconds late. This is
# the newer Pi it is pointed at instead, through GENTLE_SHELL_PI.
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
  version = "1.4.0";
  url = "https://registry.npmjs.org/@earendil-works/pi-coding-agent/-/pi-coding-agent-1.4.0.tgz";
  hash = "sha256-0VXBbvb6AJYPv1iykRU26AsF8zcA4LFPvQiWft4MdCg=";
  npmDepsHash = "sha256-npDQwvrXeoxvoK/ItLeB4q5UGEbslZ9onOlgclM8IcI=";
}
