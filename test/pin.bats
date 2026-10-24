setup() {
  load 'helpers/fixtures'
  load_lib
  hermetic_git_config
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

# Prints the ref fetch keeps upstream <url>'s tag <tag> in.
upstream_tag_ref() {
  local prefix
  prefix="$(upstream_refs "$1")"
  printf '%stags/%s\n' "${prefix%heads/}" "$2"
}

# Upstream: "v1" on main, tagged v1, then "v2", tagged v2. The monorepo
# cloned v1, and its default branch pins the tag v1 with default-pin.
pinned_to_v1() {
  make_bare_repo "$upstream" main
  seed_bare_repo "$upstream" "v1"
  git -C "$upstream" tag v1 main
  init_monorepo "$monorepo"
  cd "$monorepo"
  splice clone "$upstream" vendor/a >/dev/null 2>&1
  git config --file vendor/a/.splice upstream.origin.default-pin v1
  git commit -q -m "vendor/a: pin v1" -- vendor/a/.splice
  seed_bare_repo "$upstream" "v2"
  git -C "$upstream" tag v2 main
}

@test "pin: the default branch syncs with the tag default-pin names, not with upstream's branch" {
  pinned_to_v1
  run splice fetch
  [ "$status" -eq 0 ]
  [ "$output" = "ok   vendor/a fetched" ]
  [ "$(git rev-parse "$(upstream_refs "$upstream")main")" = "$(git -C "$upstream" rev-parse main)" ]
  [ "$(git rev-parse "$(upstream_tag_ref "$upstream" v1)")" = "$(git -C "$upstream" rev-parse v1)" ]
  run splice status
  [ "$output" = "$(printf 'On branch main\n\n  up to date  vendor/a -> tags/v1')" ]
  run splice pull vendor/a
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "ok   vendor/a: nothing to pull" ]
}

@test "pin: naming a newer tag and pulling upgrades the splice" {
  pinned_to_v1
  git config --file vendor/a/.splice upstream.origin.default-pin v2
  git commit -q -m "vendor/a: upgrade to v2" -- vendor/a/.splice
  run splice pull vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok   vendor/a: pulled $(git -C "$upstream" rev-parse --short v2)"* ]]
  [ "$(git log -1 --format=%s)" = "splice: pull vendor/a from tags/v2 at $(git -C "$upstream" rev-parse --short v2)" ]
  [ "$(cat vendor/a/file.txt)" = "$(printf 'v1\nv2')" ]
  run splice status
  [ "$output" = "$(printf 'On branch main\n\n  up to date  vendor/a -> tags/v2')" ]
}

@test "pin: local changes on top of a tag show as ahead, and push refuses them on the default branch" {
  pinned_to_v1
  splice fetch >/dev/null
  commit_local "$monorepo" vendor/a "a local fix"
  run splice status
  [ "$output" = "$(printf 'On branch main\n\n  ahead 1  vendor/a -> tags/v1')" ]
  run splice push vendor/a
  [ "$status" -eq 1 ]
  [ "$output" = "$(printf "%s\n%s" "!!   vendor/a: pinned at the tag 'v1' -- a tag isn't pushed to: push from a feature branch, or follow a branch again: git config --file vendor/a/.splice --unset upstream.origin.default-pin" "!!   Failed: vendor/a")" ]
  [ "$(git -C "$upstream" rev-parse v1)" = "$(git rev-parse "$(upstream_tag_ref "$upstream" v1)")" ]
}

@test "pin: a feature branch of a pinned splice pushes as a new upstream branch, from the tag" {
  pinned_to_v1
  splice fetch >/dev/null
  git switch -q -c feature
  commit_local "$monorepo" vendor/a "a fix for v1"
  run splice push vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok   vendor/a: pushed "*" to feature"* ]]
  [ "$(git -C "$upstream" rev-parse feature~1)" = "$(git -C "$upstream" rev-parse v1)" ]
}

@test "pin: a commit id in default-pin pins that commit, fetched by id although no branch or tag has it" {
  make_bare_repo "$upstream" main
  seed_bare_repo "$upstream" "v1"
  seed_bare_repo "$upstream" "on a branch" topic
  local pinned
  pinned="$(git -C "$upstream" rev-parse topic)"
  init_monorepo "$monorepo"
  cd "$monorepo"
  splice clone "$upstream" vendor/a >/dev/null 2>&1
  git config --file vendor/a/.splice upstream.origin.default-pin "$pinned"
  git commit -q -m "vendor/a: pin a commit" -- vendor/a/.splice
  git -C "$upstream" branch -q -D topic
  git -C "$upstream" config uploadpack.allowAnySHA1InWant true
  run splice fetch
  [ "$status" -eq 0 ]
  run splice pull vendor/a
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok   vendor/a: pulled ${pinned:0:7}"* ]]
  [ "$(git log -1 --format=%s)" = "splice: pull vendor/a from ${pinned:0:7} at ${pinned:0:7}" ]
  run splice status
  [ "$output" = "$(printf 'On branch main\n\n  up to date  vendor/a -> %s' "${pinned:0:7}")" ]
  commit_local "$monorepo" vendor/a "a local fix"
  run splice push vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   vendor/a: pinned at the commit ${pinned:0:7} -- a commit isn't pushed to"* ]]
}

@test "pin: a name that is both a branch and a tag upstream pins the tag" {
  pinned_to_v1
  git -C "$upstream" branch v1 main
  splice fetch >/dev/null
  run splice status
  [ "$output" = "$(printf 'On branch main\n\n  up to date  vendor/a -> tags/v1')" ]
}

@test "pin: a branch in default-pin is refused, with the commands to follow it with default-branch" {
  pinned_to_v1
  git -C "$upstream" branch stable main
  git config --file vendor/a/.splice upstream.origin.default-pin stable
  git commit -q -m "vendor/a: pin a branch" -- vendor/a/.splice
  splice fetch >/dev/null
  run splice status
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   vendor/a: default-pin names 'stable', a branch upstream, not a tag -- to follow it: git config --file vendor/a/.splice upstream.origin.default-branch stable && git config --file vendor/a/.splice --unset upstream.origin.default-pin"* ]]
}

@test "pin: default-branch and default-pin for the same upstream are refused" {
  pinned_to_v1
  git config --file vendor/a/.splice upstream.origin.default-branch main
  git commit -q -m "vendor/a: follow and pin" -- vendor/a/.splice
  run splice status
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   vendor/a/.splice has both default-branch and default-pin for upstream.origin -- follow the branch or pin, not both: git config --file vendor/a/.splice --unset upstream.origin.default-pin"* ]]
}

@test "pin: a tag that moved upstream keeps its commit here, and fetch says how to take the new one" {
  pinned_to_v1
  splice fetch >/dev/null
  local old new
  old="$(git -C "$upstream" rev-parse v1)"
  git -C "$upstream" tag -f v1 main >/dev/null
  new="$(git -C "$upstream" rev-parse v1)"
  run splice fetch
  [ "$status" -eq 0 ]
  [[ "$output" == *"??   vendor/a: the tag 'v1' moved upstream, from ${old:0:7} to ${new:0:7} -- kept ${old:0:7}; to take the new one: git update-ref $(upstream_tag_ref "$upstream" v1) $new"* ]]
  [ "$(git rev-parse "$(upstream_tag_ref "$upstream" v1)")" = "$old" ]
}

@test "pin: a tag upstream lacks is reported, not taken for a missing branch" {
  pinned_to_v1
  git config --file vendor/a/.splice upstream.origin.default-pin v9
  git commit -q -m "vendor/a: a tag nobody made" -- vendor/a/.splice
  splice fetch >/dev/null
  run splice status
  [ "$output" = "$(printf "On branch main\n\n  !! the tag 'v9' isn't here  vendor/a -> tags/v9  run 'git splice fetch vendor/a', or check that upstream has it")" ]
  run splice pull vendor/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   vendor/a: the tag 'v9' isn't here -- run 'git splice fetch vendor/a', or check that upstream has it"* ]]
}

@test "pin: a feature branch fetches the tag too, so an unchanged splice in a fresh clone doesn't push as a new branch" {
  pinned_to_v1
  git for-each-ref --format='%(refname)' refs/splices/ | xargs -n1 git update-ref -d
  git switch -q -c feature
  splice fetch >/dev/null
  run splice status
  [ "$output" = "$(printf 'On branch feature\n\n  unchanged, no upstream branch  vendor/a')" ]
  run splice push vendor/a
  [ "$status" -eq 0 ]
  ! git -C "$upstream" show-ref --verify --quiet refs/heads/feature
}

@test "pin: a tag pulls from an upstream that has no branches left" {
  pinned_to_v1
  splice fetch >/dev/null
  git -C "$upstream" update-ref -d refs/heads/main
  git config --file vendor/a/.splice upstream.origin.default-pin v2
  git commit -q -m "vendor/a: pin v2" -- vendor/a/.splice
  splice fetch >/dev/null
  run splice pull vendor/a
  [ "$status" -eq 0 ]
  [ "$(cat vendor/a/file.txt)" = $'v1\nv2' ]
}
