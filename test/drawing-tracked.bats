# check_drawing with tracked branches, against the tracked-branch
# drawing: a box tracked(X) points at the upstream branch a splice tracks
# on monorepo branch X, as fetched.

setup() {
  load 'helpers/fixtures'
  load '../check-drawing/check-drawing'
  hermetic_git_config
  load 'scenarios/03-branches-and-teamwork/07-tracked-branch/setup'
  PATH="$BATS_TEST_DIRNAME/..:$PATH"
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  scenario_tracked_branch "$monorepo" "$BATS_TEST_TMPDIR/upstream.git"
  drawing="$BATS_TEST_TMPDIR/tracked-branch.drawio"
  xmlstarlet sel -T -N s=http://www.w3.org/2000/svg -t -v '/s:svg/@content' \
    "$BATS_TEST_DIRNAME/scenarios/03-branches-and-teamwork/07-tracked-branch/tracked-branch.drawio.svg" >"$drawing" 2>/dev/null
  cd "$monorepo"
  git splice fetch --branch development --track vendor/a >/dev/null 2>&1
  git splice fetch --branch review --track vendor/b >/dev/null 2>&1
}

edit_drawing() {
  xmlstarlet ed -L "$@" "$drawing"
}

@test "drawing tracked: the committed one matches its scenario" {
  run check_drawing "$drawing"
  [ "$status" -eq 0 ]
  [ "$output" = "ok   tracked-branch.drawio: 6 commits, 10 arrows, 7 boxes, 2 lanes" ]
}

@test "drawing tracked: without a tracked branch there's no tracked(X), and T is the branch named like X" {
  git splice fetch --no-track vendor/a >/dev/null 2>&1
  run check_drawing "$drawing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   tracked(feature) points at l, but there's no tracked(feature)"* ]]
  [[ "$output" == *"!!   T points at l, but there's no T"* ]]
}

@test "drawing tracked: tracked(X) reads the monorepo branch X, not the current one" {
  edit_drawing -u '//mxCell[@id="box_b_tracked"]/@value' -v "T = tracked(main)"
  run check_drawing "$drawing"
  [ "$status" -eq 1 ]
  [ "$output" = "!!   tracked(main) points at n, but there's no tracked(main)" ]
}

@test "drawing tracked: a key that starts another key's doesn't read that one's entry" {
  git config --add branch.feature.splice "a.de:review"
  run check_drawing "$drawing"
  [ "$status" -eq 0 ]
}
