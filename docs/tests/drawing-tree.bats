# check-drawing tree, which writes the tree of splices from the repository,
# and check_drawing on a tree, which compares it with what the repository
# gives, against the three-levels scenario.

setup() {
  load 'helpers/fixtures'
  load '../../check-drawing/check-drawing'
  hermetic_git_config
  load '../09-scenarios/05-nested-splices/01-nested-splices/setup'
  load '../09-scenarios/05-nested-splices/01-nested-splices/02-three-levels/setup'
  PATH="$(dirname "$ENTRYPOINT"):$PATH"
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
  scenario_three_levels "$monorepo" "$upstream"
  cd "$monorepo"
  drawing="$BATS_TEST_TMPDIR/tree.drawio"
  xmlstarlet sel -T -N s=http://www.w3.org/2000/svg -t -v '/s:svg/@content' \
    "$BATS_TEST_DIRNAME/../09-scenarios/05-nested-splices/01-nested-splices/02-three-levels/tree.drawio.svg" >"$drawing" 2>/dev/null
  revs=(s=HEAD a1=refs/splices/upstream/heads/main b1=refs/splices/upstream-b/heads/main c1=refs/splices/upstream-c/heads/main)
  written="$BATS_TEST_TMPDIR/written.drawio"
}

# write_tree [--mark <mark>]... [<label>=<rev>...]: the tree, into $written.
write_tree() {
  "$CHECK_DRAWING_TOOL" tree "$@" >"$written"
}

# cell <id> <attribute>: the attribute of the written tree's cell <id>.
cell() {
  xmlstarlet sel -t -v "//mxCell[@id='$1']/@$2" "$written"
}

@test "drawing tree: the committed one matches its scenario" {
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 0 ]
  [ "$output" = "ok   tree.drawio: a tree of 4 rows" ]
}

@test "drawing tree: one that isn't what the repository gives names each cell that differs, and how to write it" {
  xmlstarlet ed -L -u '//mxCell[@value="c1"]/@value' -v x "$drawing"
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   tree.drawio isn't the tree the repository gives: write it with \`check-drawing tree a1=refs/splices/upstream/heads/main b1="* ]]
  [[ "$output" == *'!!   s3: drawn '*'value="x"'*', given '*'value="c1"'* ]]
}

@test "drawing tree: a line that's no longer an edge, though nothing else about it changed" {
  xmlstarlet ed -L -d '//mxCell[@id="c2"]/@edge' "$drawing"
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   c2: drawn "* ]]
}

@test "drawing tree: a row per splice, each hanging from the one around it" {
  write_tree "${revs[@]}"
  [ "$(cell f0 value)" = monorepo ]
  [ "$(cell f1 value)" = vendor/a/ ]
  [ "$(cell f2 value)" = b/ ]
  [ "$(cell f3 value)" = c/ ]
  [ "$(cell c3 source)" = s2 ]
  [ "$(cell c3 target)" = s3 ]
}

@test "drawing tree: without a label, a commit is named by its subject, up to a colon" {
  write_tree
  [ "$(cell s0 value)" = "$(git log -1 --format=%s | sed 's/: .*//')" ]
}

@test "drawing tree: R after the dots, dashed, named after the commit it copies, with a '" {
  commit_local "$monorepo" vendor/a/b/c "c local"
  write_tree m=HEAD
  [ "$(cell r3 value)" = "m'" ]
  [[ "$(cell r3 style)" == *"dashed=1;"* ]]
  [ "$(cell dots3 value)" = "…" ]
  [ "$(cell r1 value)" = "m'" ]
  [ "$(cell c3 source)" = r2 ]
}

@test "drawing tree: a synced commit a push made is named after the monorepo's commit it copies, with a '" {
  commit_local "$monorepo" vendor/a/b/c "c local"
  splice push vendor/a/b/c >/dev/null
  splice pull --bump vendor/a/b/c >/dev/null
  write_tree m=HEAD~1
  [ "$(cell s3 value)" = "m'" ]
  [[ "$(cell s3 style)" != *"dashed=1;"* ]]
}

@test "drawing tree: R is dashed while no upstream branch has it, and solid once pushed" {
  commit_local "$monorepo" vendor/a/b/c "c local"
  write_tree m=HEAD
  [[ "$(cell r3 style)" == *"dashed=1;"* ]]
  splice push vendor/a/b/c >/dev/null
  write_tree m=HEAD
  [[ "$(cell r3 style)" != *"dashed=1;"* ]]
  [ "$(cell r3 value)" = "m'" ]
  [ "$(cell dots3 value)" = "…" ]
}

@test "drawing tree: the commit a conflicted pull merges in, outlined red, and the row says so" {
  commit_local "$monorepo" vendor/a/b "b local"
  seed_bare_repo "$BATS_TEST_TMPDIR/upstream-b.git" "b2: b upstream"
  run splice pull vendor/a/b
  [ "$status" -ne 0 ]
  write_tree
  [ "$(cell t2 value)" = b2 ]
  [[ "$(cell t2 style)" == *"strokeColor=#D00000;"* ]]
  [ "$(cell f2 value)" = "b/   conflict" ]
  [ "$(cell lt0 value)" = "merged in, conflicts" ]
}

@test "drawing tree: with --mark pulled, a pull and what it brought in are outlined blue" {
  seed_bare_repo "$BATS_TEST_TMPDIR/upstream-c.git" "c2: c upstream"
  splice pull vendor/a/b/c >/dev/null
  write_tree --mark pulled
  [[ "$(cell s0 style)" == *"strokeColor=#0070E0;"* ]]
  [[ "$(cell s3 style)" == *"strokeColor=#0070E0;"* ]]
  [[ "$(cell s1 style)" != *"strokeColor="* ]]
  [ "$(cell lt0 value)" = pulled ]
}

@test "drawing tree: with --mark carried, what the next rebuild copies is outlined orange" {
  commit_local "$monorepo" vendor/a/b/c "c local"
  write_tree --mark carried
  [[ "$(cell s0 style)" == *"strokeColor=#E07000;"* ]]
  [[ "$(cell r3 style)" == *"strokeColor=#E07000;"* ]]
  [[ "$(cell s3 style)" != *"strokeColor="* ]]
  [ "$(cell lt0 value)" = "carried over" ]
}

@test "drawing tree: one commit can't be both pulled and carried over" {
  seed_bare_repo "$BATS_TEST_TMPDIR/upstream-c.git" "c2: c upstream"
  splice pull vendor/a/b/c >/dev/null
  run "$CHECK_DRAWING_TOOL" tree --mark pulled --mark carried p=HEAD
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   p is both pulled and carried over, and one outline can't show both: leave out --mark pulled or --mark carried"* ]]
}

@test "drawing tree: the marks it's checked with are the ones its legend has" {
  commit_local "$monorepo" vendor/a/b/c "c local"
  write_tree --mark carried m=HEAD
  run check_drawing "$written" m=HEAD
  [ "$status" -eq 0 ]
  sed -i 's/#E07000/#0070E0/g' "$written"
  run check_drawing "$written" m=HEAD
  [ "$status" -eq 1 ]
  [[ "$output" == *"write it with \`check-drawing tree --mark pulled m=HEAD\`"* ]]
}

@test "drawing tree: a splice after an init has no synced commit, only R, without the dots" {
  load '../09-scenarios/02-starting-a-splice/04-init-new-upstream/setup'
  local other="$BATS_TEST_TMPDIR/other" other_upstream="$BATS_TEST_TMPDIR/other.git"
  scenario_init_new_upstream "$other" "$other_upstream"
  cd "$other"
  splice init lib/a "$other_upstream" >/dev/null
  write_tree s=HEAD
  [ "$(cell r1 value)" = "s'" ]
  [ -z "$(cell s1 value)" ]
  [ -z "$(cell dots1 value)" ]
  [ "$(cell c1 target)" = r1 ]
}

@test "drawing tree: a label given as an annotated tag names the commit it tags" {
  git tag -a -m "the start" v1
  run check_drawing "$drawing" "${revs[@]/#s=HEAD/s=v1}"
  [ "$status" -eq 0 ]
}

@test "drawing tree: a commit the monorepo doesn't have is labelled by its hash" {
  local c2
  seed_bare_repo "$BATS_TEST_TMPDIR/upstream-c.git" "c2: c upstream"
  c2="$(git -C "$BATS_TEST_TMPDIR/upstream-c.git" rev-parse main)"
  git config --file vendor/a/b/c/.splice splice.commit "$c2"
  git commit -q -am "c at c2, not fetched"
  write_tree
  [ "$(cell s3 value)" = "${c2:0:7}" ]
}

@test "drawing tree: a commit the monorepo doesn't have takes a label given by its full hash" {
  local c2
  seed_bare_repo "$BATS_TEST_TMPDIR/upstream-c.git" "c2: c upstream"
  c2="$(git -C "$BATS_TEST_TMPDIR/upstream-c.git" rev-parse main)"
  git config --file vendor/a/b/c/.splice splice.commit "$c2"
  git commit -q -am "c at c2, not fetched"
  write_tree "c2=$c2"
  [ "$(cell s3 value)" = c2 ]
}
