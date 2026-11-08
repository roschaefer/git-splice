scenario_vcs_compatibility() {
  local monorepo="$1" upstream_repo="$2"
  VCS_ROOT="$(dirname "$monorepo")"
  export VCS_ROOT
  export GIT_CONFIG_COUNT=4
  export GIT_CONFIG_KEY_0=user.name GIT_CONFIG_VALUE_0=Test
  export GIT_CONFIG_KEY_1=user.email GIT_CONFIG_VALUE_1=test@example.com
  export GIT_CONFIG_KEY_2="url.$upstream_repo.insteadOf" GIT_CONFIG_VALUE_2=https://git.example.com/lib.git
  export GIT_CONFIG_KEY_3=protocol.file.allow GIT_CONFIG_VALUE_3=always
  make_bare_repo "$upstream_repo" || return
  seed_bare_repo "$upstream_repo" "library seed" main src/parse.txt || return
  init_monorepo "$monorepo" || return
  (
    cd "$monorepo" || exit
    mkdir app
    echo "app" >app/main.txt
    git add app
    git commit -q -m "app seed"
    git config "url.$upstream_repo.insteadOf" https://git.example.com/lib.git
  ) || return
  git clone -q --no-local "$monorepo" "$VCS_ROOT/splice-monorepo"
  git -C "$VCS_ROOT/splice-monorepo" config "url.$upstream_repo.insteadOf" https://git.example.com/lib.git
  git -C "$VCS_ROOT/splice-monorepo" config user.name Test
  git -C "$VCS_ROOT/splice-monorepo" config user.email test@example.com
  add_splice "$VCS_ROOT/splice-monorepo" https://git.example.com/lib.git vendor/lib
  export XDG_CONFIG_HOME="$VCS_ROOT/config" JJ_CONFIG="$VCS_ROOT/jj.toml"
  export JJ_TIMESTAMP=2026-01-01T00:00:00Z JJ_RANDOMNESS_SEED=1 TZ=UTC
  mkdir -p "$XDG_CONFIG_HOME/sapling"
  cat >"$XDG_CONFIG_HOME/sapling/sapling.conf" <<CONFIG
[ui]
username = Test <test@example.com>
[devel]
default-date = 1767225600 0
[remotefilelog]
cachepath = $VCS_ROOT/sapling-cache
CONFIG
  cat >"$JJ_CONFIG" <<'CONFIG'
[user]
name = "Test"
email = "test@example.com"
[ui]
color = "never"
paginate = "never"
CONFIG
}

sl() {
  command sl "$@" 2>&1 | sed -E "s#$UPSTREAM#\$UPSTREAM#g; s#$VCS_ROOT#\$VCS_ROOT#g"
  return "${PIPESTATUS[0]}"
}

jj() {
  command jj "$@" 2>&1 | sed -E "s#$UPSTREAM#\$UPSTREAM#g; s#$VCS_ROOT#\$VCS_ROOT#g"
  return "${PIPESTATUS[0]}"
}
