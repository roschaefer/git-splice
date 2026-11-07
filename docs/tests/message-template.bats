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

@test "message template: pull --all fills in the command, path, upstream branch and both synced commits" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local old new
  old="$(splice_config vendor/a commit)"
  new="$(git rev-parse "$(upstream_refs "$upstream")main")"
  run splice pull --all --message-template 'chore(deps): {command} {path} from {upstream}, {old}..{new}

Upstream: {full-old}..{full-new}'
  [ "$status" -eq 0 ]
  [ "$(git log -1 --format=%B)" = "chore(deps): pull vendor/a from main, ${old:0:7}..${new:0:7}

Upstream: $old..$new" ]
}

@test "message template: {shortlog} lists the pulled commits like 'git merge --log', newest first, without merge commits, and {count} counts them" {
  scenario_up_to_date "$monorepo" "$upstream"
  push_upstream_commits "$upstream" 2
  cd "$monorepo"
  splice pull --message-template '{command} {path} ({count} commits)

{shortlog}' vendor/a
  [ "$(git log -1 --format=%B)" = "pull vendor/a (3 commits)

  side work
  change 2
  change 1" ]
}

@test "message template: log.showSignature doesn't put signature checks into {shortlog}" {
  command -v ssh-keygen >/dev/null || skip "no ssh-keygen to sign a commit with"
  scenario_up_to_date "$monorepo" "$upstream"
  local work="$BATS_TEST_TMPDIR/work"
  ssh-keygen -q -t ed25519 -N "" -f "$BATS_TEST_TMPDIR/key"
  git clone -q "$upstream" "$work"
  echo signed >"$work/signed.txt"
  git -C "$work" add signed.txt
  git -C "$work" -c user.name=Test -c user.email=test@example.com -c gpg.format=ssh \
    -c user.signingKey="$BATS_TEST_TMPDIR/key.pub" commit -q -S -m "a signed change"
  git -C "$work" push -q origin main
  cd "$monorepo"
  git config log.showSignature true
  splice pull --message-template '{shortlog}' vendor/a
  [ "$(git log -1 --no-show-signature --format=%B)" = "  a signed change" ]
}

@test "message template: {shortlog} stops after 20 commits with '...', as 'git merge --log' does, while {count} counts them all" {
  scenario_up_to_date "$monorepo" "$upstream"
  push_upstream_commits "$upstream" 24
  cd "$monorepo"
  splice pull --message-template='{count} commits

{shortlog}' vendor/a
  local message
  message="$(git log -1 --format=%B)"
  [ "$(head -1 <<<"$message")" = "25 commits" ]
  [ "$(sed -n 3p <<<"$message")" = "  side work" ]
  [ "$(sed -n 22p <<<"$message")" = "  change 6" ]
  [ "$(sed -n 23p <<<"$message")" = "  ..." ]
  [ "$(wc -l <<<"$message")" -eq 23 ]
}

@test "message template: refuses -m with it, as both give the message" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local before
  before="$(git rev-parse HEAD)"
  run splice pull -m "take the upstream change" --message-template '{command} {path}' vendor/a
  [ "$status" -eq 1 ]
  [ "$output" = "!!   -m and --message-template both give the message -- give one" ]
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "message template: refuses an unknown placeholder, e.g. a typo, before pulling anything, and lists the known ones" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local before
  before="$(git rev-parse HEAD)"
  run splice pull --all --message-template '{comand} {path}'
  [ "$status" -eq 1 ]
  [ "$output" = "!!   --message-template: unknown placeholder {comand} -- the placeholders are {command} {path} {upstream} {old} {new} {full-old} {full-new} {count} {shortlog}" ]
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "message template: refuses an unclosed or unopened brace, and {{ and }} write literal braces" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  run splice pull --message-template 'pull {path' vendor/a
  [ "$status" -eq 1 ]
  [ "$output" = "!!   --message-template: '{path' has no closing '}' -- write '{{' for a literal '{'" ]
  run splice pull --message-template 'pull } {path}' vendor/a
  [ "$status" -eq 1 ]
  [ "$output" = "!!   --message-template: '}' has no opening '{' -- write '}}' for a literal '}'" ]
  splice pull --message-template '{{{path}}}' vendor/a
  [ "$(git log -1 --format=%B)" = "{vendor/a}" ]
}

@test "message template: refuses an empty one" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  run splice pull --message-template '' vendor/a
  [ "$status" -eq 1 ]
  [ "$output" = "!!   --message-template needs a template" ]
  run splice pull --message-template '  ' vendor/a
  [ "$status" -eq 1 ]
  [ "$output" = "!!   --message-template: it's empty" ]
}

@test "message template: pull --bump's commit names the command bump" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  commit_local "$monorepo" vendor/a "local change"
  splice push vendor/a
  run splice pull --bump --message-template '{command} {path} to {new}' vendor/a
  [ "$status" -eq 0 ]
  [ "$(git log -1 --format=%B)" = "bump vendor/a to $(git -C "$upstream" rev-parse --short=7 main)" ]
}

@test "message template: merge --rebase's commit, the one the rebased ones go on top of, gets it too" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  commit_local "$monorepo" vendor/a "local change" local.txt
  run splice merge --rebase --message-template '{command} {path} to {new}' vendor/a
  [ "$status" -eq 0 ]
  [ "$(git log -1 --format=%s HEAD^)" = "merge vendor/a to $(git -C "$upstream" rev-parse --short=7 main)" ]
  [ "$(git log -1 --format=%s)" = "local change" ]
}

@test "message template: clone fills in the upstream branch and the new synced commit" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  cd "$monorepo"
  run splice clone --message-template '{command} {path} from {upstream} at {new}' "$upstream" vendor/a
  [ "$status" -eq 0 ]
  [ "$(git log -1 --format=%B)" = "clone vendor/a from main at $(git -C "$upstream" rev-parse --short=7 main)" ]
}

@test "message template: clone has no old synced commit, so a template with one is refused before anything is fetched, and -m gives that commit its message" {
  make_bare_repo "$upstream"
  seed_bare_repo "$upstream" "seed"
  init_monorepo "$monorepo"
  cd "$monorepo"
  run splice clone --message-template '{command} {path}: {shortlog}' "$upstream" vendor/a
  [ "$status" -eq 1 ]
  [ "$output" = "!!   --message-template: clone has no value for {shortlog} -- give the commit a message with -m" ]
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
  run splice init --message-template '{command} {path} at {new}' lib/a "$upstream"
  [ "$status" -eq 1 ]
  [ "$output" = "!!   --message-template: init has no value for {new} -- give the commit a message with -m" ]
  [ "$(git rev-parse HEAD)" = "$before" ]
  splice init --message-template 'chore: {command} {path}' lib/a "$upstream"
  [ "$(git log -1 --format=%B)" = "chore: init lib/a" ]
}

@test "message template: a splice with no synced commit yet, in a clone from before init's push, fails on {old} when its commit is due, as other refused splices do" {
  scenario_init_new_upstream "$monorepo" "$upstream"
  cd "$monorepo"
  splice init lib/a "$upstream"
  local clone="$BATS_TEST_TMPDIR/clone" before
  git clone -q "$monorepo" "$clone"
  splice push lib/a
  local work="$BATS_TEST_TMPDIR/work"
  git clone -q "$upstream" "$work"
  git -C "$work" -c user.name=Test -c user.email=test@example.com commit -q --allow-empty -m "upstream's change"
  git -C "$work" push -q origin main
  cd "$clone"
  [ -z "$(splice_config lib/a commit)" ]
  before="$(git rev-parse HEAD)"
  run splice pull --message-template '{command} {path} from {old}' lib/a
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   lib/a: no value for {old} in --message-template -- give the commit a message with -m"* ]]
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "message template: merge --rebuilt-commit refuses it, as the commit keeps the message of the one it merges, the way push keeps the messages of the commits it copies" {
  scenario_up_to_date "$monorepo" "$upstream"
  cd "$monorepo"
  local rebuilt work="$BATS_TEST_TMPDIR/work"
  rebuilt="$(splice rebuild vendor/a)"
  git worktree add -q --detach "$work" "$rebuilt"
  echo fix >"$work/fix.txt"
  git -C "$work" add fix.txt
  git -C "$work" commit -q -m "fix: the parser"
  run splice merge --message-template '{command} {path}' --rebuilt-commit "$(git -C "$work" rev-parse HEAD)" vendor/a
  [ "$status" -eq 1 ]
  [ "$output" = "!!   --rebuilt-commit keeps the message of the commit it merges -- -m replaces it, --message-template doesn't go with it" ]
  run splice merge --rebuilt-commit "$(git -C "$work" rev-parse HEAD)" vendor/a
  [ "$status" -eq 0 ]
  [ "$(git log -1 --format=%B)" = "fix: the parser" ]
}

@test "message template: splice.messageTemplate, also set with --global, gives every commit its message without the flag" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig"
  git config --global splice.messageTemplate 'chore(deps): {command} {path} to {new}'
  run splice pull --all
  [ "$status" -eq 0 ]
  [ "$(git log -1 --format=%B)" = "chore(deps): pull vendor/a to $(git -C "$upstream" rev-parse --short=7 main)" ]
}

@test "message template: --message-template and -m win over splice.messageTemplate, which -m doesn't even read" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  git config splice.messageTemplate '{command} {path}'
  splice pull --message-template 'given {path}' vendor/a
  [ "$(git log -1 --format=%B)" = "given vendor/a" ]
  git reset -q --hard HEAD~1
  git config splice.messageTemplate '{nope}'
  run splice pull -m "take the upstream change" vendor/a
  [ "$status" -eq 0 ]
  [ "$(git log -1 --format=%B)" = "take the upstream change" ]
}

@test "message template: refuses a broken or empty splice.messageTemplate before pulling anything, naming the key" {
  scenario_pull_ahead "$monorepo" "$upstream"
  cd "$monorepo"
  local before
  before="$(git rev-parse HEAD)"
  git config splice.messageTemplate '{comand} {path}'
  run splice pull --all
  [ "$status" -eq 1 ]
  [ "$output" = "!!   splice.messageTemplate: unknown placeholder {comand} -- the placeholders are {command} {path} {upstream} {old} {new} {full-old} {full-new} {count} {shortlog}" ]
  git config splice.messageTemplate ''
  run splice pull vendor/a
  [ "$status" -eq 1 ]
  [ "$output" = "!!   splice.messageTemplate: it's empty -- unset it for the default messages" ]
  git config splice.messageTemplate '{command} {path}: {shortlog}'
  run splice init lib/b "$upstream"
  [ "$status" -eq 1 ]
  [ "$output" = "!!   splice.messageTemplate: init has no value for {shortlog} -- give the commit a message with -m" ]
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "message template: merge --rebuilt-commit ignores splice.messageTemplate and keeps the message of the commit it merges" {
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
