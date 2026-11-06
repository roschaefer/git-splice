setup() {
  load 'helpers/fixtures'
  hermetic_git_config
  load '../09-scenarios/01-everyday-sync/02-up-to-date/setup'
  load '../09-scenarios/01-everyday-sync/02-up-to-date/01-pull-ahead/setup'
  load '../09-scenarios/02-starting-a-splice/04-init-new-upstream/setup'
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
}

# Pushes commits "change 1" to "change $2" to upstream $1's main, then a merge
# of a branch with one commit, "side work".
push_upstream_commits() {
  local repo="$1" count="$2" work="$BATS_TEST_TMPDIR/work" i
  git clone -q "$repo" "$work"
  git -C "$work" config user.name Test
  git -C "$work" config user.email test@example.com
  # A second apart, so that newest first is one order.
  export GIT_COMMITTER_DATE GIT_AUTHOR_DATE
  for i in $(seq 1 "$count"); do
    GIT_COMMITTER_DATE="@$((1700000000 + i)) +0000" GIT_AUTHOR_DATE="$GIT_COMMITTER_DATE"
    git -C "$work" commit -q --allow-empty -m "change $i"
  done
  GIT_COMMITTER_DATE="@$((1700000001 + count)) +0000" GIT_AUTHOR_DATE="$GIT_COMMITTER_DATE"
  git -C "$work" switch -q -c side
  git -C "$work" commit -q --allow-empty -m "side work"
  git -C "$work" switch -q main
  git -C "$work" merge -q --no-ff -m "Merge branch 'side'" side
  unset GIT_COMMITTER_DATE GIT_AUTHOR_DATE
  git -C "$work" push -q origin main
  rm -rf "$work"
}

@test "message template: pull fills in the command, path, upstream branch and both synced commits" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local old new
  old="$(splice_config vendor/a commit)"
  new="$(git rev-parse "$(upstream_refs "$upstream")main")"
  git config splice.messageTemplate 'chore(deps): {command} {path} from {upstream}, {old}..{new}

Upstream: {full-old}..{full-new}'
  run splice pull vendor/a
  [ "$status" -eq 0 ]
  [ "$(git log -1 --format=%B)" = "chore(deps): pull vendor/a from main, ${old:0:7}..${new:0:7}

Upstream: $old..$new" ]
}

@test "message template: {shortlog} lists the pulled commits like 'git merge --log', newest first, without merge commits, and {count} counts them" {
  scenario_up_to_date "$monorepo" "$upstream"
  push_upstream_commits "$upstream" 2
  cd "$monorepo"
  git config splice.messageTemplate '{command} {path} ({count} commits)

{shortlog}'
  splice pull vendor/a
  [ "$(git log -1 --format=%B)" = "pull vendor/a (3 commits)

  side work
  change 2
  change 1" ]
}

@test "message template: {shortlog} stops after 20 commits with '...', as 'git merge --log' does, while {count} counts them all" {
  scenario_up_to_date "$monorepo" "$upstream"
  push_upstream_commits "$upstream" 24
  cd "$monorepo"
  git config splice.messageTemplate '{count} commits

{shortlog}'
  splice pull vendor/a
  local message
  message="$(git log -1 --format=%B)"
  [ "$(head -1 <<<"$message")" = "25 commits" ]
  [ "$(sed -n 3p <<<"$message")" = "  side work" ]
  [ "$(sed -n 22p <<<"$message")" = "  change 6" ]
  [ "$(sed -n 23p <<<"$message")" = "  ..." ]
  [ "$(wc -l <<<"$message")" -eq 23 ]
}

@test "message template: -m wins over it" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  git config splice.messageTemplate '{command} {path}'
  run splice pull -m "take the upstream change" vendor/a
  [ "$status" -eq 0 ]
  [ "$(git log -1 --format=%B)" = "take the upstream change" ]
}

@test "message template: -m wins over a broken one, which isn't even read then" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  git config splice.messageTemplate '{nope}'
  run splice pull -m "take the upstream change" vendor/a
  [ "$status" -eq 0 ]
}

@test "message template: refuses an unknown placeholder, e.g. a typo, before pulling anything, and lists the known ones" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local before
  before="$(git rev-parse HEAD)"
  git config splice.messageTemplate '{comand} {path}'
  run splice pull --all
  [ "$status" -eq 1 ]
  [ "$output" = "!!   splice.messageTemplate: unknown placeholder {comand} -- the placeholders are {command} {path} {upstream} {old} {new} {full-old} {full-new} {count} {shortlog}" ]
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "message template: refuses an unclosed or unopened brace, and {{ and }} write literal braces" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  git config splice.messageTemplate 'pull {path'
  run splice pull vendor/a
  [ "$status" -eq 1 ]
  [ "$output" = "!!   splice.messageTemplate: '{path' has no closing '}' -- write '{{' for a literal '{'" ]
  git config splice.messageTemplate 'pull } {path}'
  run splice pull vendor/a
  [ "$status" -eq 1 ]
  [ "$output" = "!!   splice.messageTemplate: '}' has no opening '{' -- write '}}' for a literal '}'" ]
  git config splice.messageTemplate '{{{path}}}'
  splice pull vendor/a
  [ "$(git log -1 --format=%B)" = "{vendor/a}" ]
}

@test "message template: refuses an empty one" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  git config splice.messageTemplate ''
  run splice pull vendor/a
  [ "$status" -eq 1 ]
  [ "$output" = "!!   splice.messageTemplate: it's empty -- unset it for the default messages" ]
}

@test "message template: pull --bump's commit names the command bump" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  commit_local "$monorepo" vendor/a "local change"
  splice push vendor/a
  git config splice.messageTemplate '{command} {path} to {new}'
  run splice pull --bump vendor/a
  [ "$status" -eq 0 ]
  [ "$(git log -1 --format=%B)" = "bump vendor/a to $(git -C "$upstream" rev-parse --short=7 main)" ]
}

@test "message template: merge --rebase's commit, the one the rebased ones go on top of, gets it too" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  commit_local "$monorepo" vendor/a "local change" local.txt
  git config splice.messageTemplate '{command} {path} to {new}'
  run splice merge --rebase vendor/a
  [ "$status" -eq 0 ]
  [ "$(git log -1 --format=%s HEAD^)" = "merge vendor/a to $(git -C "$upstream" rev-parse --short=7 main)" ]
  [ "$(git log -1 --format=%s)" = "local change" ]
}

@test "message template: clone fills in the upstream branch and the new synced commit" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  cd "$monorepo"
  git config splice.messageTemplate '{command} {path} from {upstream} at {new}'
  run splice clone "$upstream" vendor/a
  [ "$status" -eq 0 ]
  [ "$(git log -1 --format=%B)" = "clone vendor/a from main at $(git -C "$upstream" rev-parse --short=7 main)" ]
}

@test "message template: clone has no old synced commit, so a template with one is refused before anything is fetched, and -m gives that commit its message" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  cd "$monorepo"
  git config splice.messageTemplate '{command} {path}: {shortlog}'
  run splice clone "$upstream" vendor/a
  [ "$status" -eq 1 ]
  [ "$output" = "!!   splice.messageTemplate: clone has no value for {shortlog} -- give the commit a message with -m" ]
  [ -z "$(git for-each-ref refs/splices/)" ]
  [ -z "$(git config --get-regexp '^splice\..*\.url$')" ]
  run splice clone -m "add vendor/a" "$upstream" vendor/a
  [ "$status" -eq 0 ]
}

@test "message template: init has only the command and path" {
  scenario_init_new_upstream "$monorepo" "$upstream"
  cd "$monorepo"
  local before
  before="$(git rev-parse HEAD)"
  git config splice.messageTemplate '{command} {path} at {new}'
  run splice init lib/a "$upstream"
  [ "$status" -eq 1 ]
  [ "$output" = "!!   splice.messageTemplate: init has no value for {new} -- give the commit a message with -m" ]
  [ "$(git rev-parse HEAD)" = "$before" ]
  git config splice.messageTemplate 'chore: {command} {path}'
  splice init lib/a "$upstream"
  [ "$(git log -1 --format=%B)" = "chore: init lib/a" ]
}

@test "message template: merge --rebuilt-commit keeps its own message, as push keeps the messages of the commits it copies" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  local rebuilt work="$BATS_TEST_TMPDIR/work"
  rebuilt="$(splice rebuild vendor/a)"
  git worktree add -q --detach "$work" "$rebuilt"
  echo fix >"$work/fix.txt"
  git -C "$work" add fix.txt
  git -C "$work" commit -q -m "fix: the parser"
  git config splice.messageTemplate '{command} {path}'
  run splice merge --rebuilt-commit "$(git -C "$work" rev-parse HEAD)" vendor/a
  [ "$status" -eq 0 ]
  [ "$(git log -1 --format=%B)" = "fix: the parser" ]
}
