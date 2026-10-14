# check_drawing, against the after-pull drawing and its scenario: the
# drawing as committed passes, and each kind of drift fails with a message
# that says what to change.

setup() {
  load 'helpers/fixtures'
  load 'helpers/drawing'
  hermetic_git_config
  load 'scenarios/sync-model/after-pull/setup'
  PATH="$BATS_TEST_DIRNAME/..:$PATH"
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
  scenario_after_pull "$monorepo" "$upstream"
  drawing="$BATS_TEST_TMPDIR/after-pull.drawio"
  xmlstarlet sel -T -N s=http://www.w3.org/2000/svg -t -v '/s:svg/@content' \
    "$BATS_TEST_DIRNAME/scenarios/sync-model/after-pull/after-pull.drawio.svg" >"$drawing" 2>/dev/null
  cd "$monorepo"
}

# Applies xmlstarlet ed options to the drawing.
edit_drawing() {
  xmlstarlet ed -L "$@" "$drawing"
}

@test "drawing: the committed one matches its scenario" {
  run check_drawing "$BATS_TEST_DIRNAME/scenarios/sync-model/after-pull/after-pull.drawio.svg" a=HEAD~4 e=HEAD
  [ "$status" -eq 0 ]
  [ "$output" = "ok   after-pull.drawio.svg: 12 commits, 17 arrows, 6 boxes, 2 frames" ]
}

@test "drawing: a box pointing at the wrong commit names the right one" {
  edit_drawing -u '//mxCell[@source="refR"]/@target' -v d_
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "!!   R points at d', the code says e'" ]
}

@test "drawing: a solid arrow into a rebuilt commit is to be dashed" {
  edit_drawing -u '//mxCell[@source="n" and @target="e_"]/@style' -v 'endArrow=block;endFill=1;'
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "!!   n -> e' is solid, but e' exists only as the rebuild: dash it" ]
}

@test "drawing: a solid rebuilt commit is to be dashed" {
  edit_drawing -u '//mxCell[@id="b_"]/@style' -v 'ellipse;aspect=fixed;'
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "!!   b' is solid, but only the rebuild has it: dash it" ]
}

@test "drawing: a missing parent arrow is named" {
  edit_drawing -d '//mxCell[@source="d_" and @target="e_"]'
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "!!   no arrow d' -> e', though d' is a parent of e'" ]
}

@test "drawing: an arrow from a commit that isn't the parent" {
  edit_drawing -u '//mxCell[@source="c" and @target="d"]/@source' -v b
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   b -> d: b isn't a parent of d" ]
  [ "${lines[1]}" = "!!   no arrow c -> d, though c is a parent of d" ]
}

@test "drawing: a frame named after another commit than the one it holds" {
  edit_drawing -u '//mxCell[@id="fu"]/@value' -v 'd:path/.splice'
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "$output" = '!!   the frame "d:path/.splice" holds e, not d' ]
}

@test "drawing: a box U(X) on a commit X's .splice doesn't record" {
  edit_drawing -u '//mxCell[@id="refU"]/@value' -v 'U = U(a)'
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "!!   U(a) points at n, the code says k" ]
}

@test "drawing: a box U(X) for a commit that isn't drawn" {
  edit_drawing -u '//mxCell[@id="refU"]/@value' -v 'U = U(z)'
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "!!   U(z) points at n, but no commit z is drawn" ]
}

@test "drawing: an arrow from a commit into a box is to be reversed" {
  edit_drawing -u '//mxCell[@source="refR"]/@source' -v e_ -u '//mxCell[@source="e_" and @target="e_"]/@target' -v refR
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "$output" = "!!   an arrow from e' points at the box R: draw it from the box to its commit" ]
}

@test "drawing: U is what HEAD records, whatever the working tree's .splice says" {
  git config --file vendor/a/.splice splice.commit "$(git rev-parse HEAD)"
  run check_drawing "$BATS_TEST_DIRNAME/scenarios/sync-model/after-pull/after-pull.drawio.svg" a=HEAD~4 e=HEAD
  [ "$status" -eq 0 ]
}

@test "drawing: an arrow not attached to a shape" {
  edit_drawing -d '//mxCell[@source="refT"]/@target'
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [[ "$output" == "!!   an arrow (e7) isn't attached at both ends: drag its ends onto shapes" ]]
}

@test "drawing: a label that's no commit's subject" {
  edit_drawing -u '//mxCell[@id="c"]/@value' -v x
  run check_drawing "$drawing" a=HEAD~4 e=HEAD
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   x: no such commit" ]
}

@test "drawing: a compressed diagram asks to be saved uncompressed" {
  printf '<mxfile><diagram id="x">7VhNb5tAEP01HC0Z</diagram></mxfile>\n' >"$drawing"
  run check_drawing "$drawing"
  [ "$status" -eq 1 ]
  [ "$output" = "!!   after-pull.drawio: no diagram inside, or a compressed one: save it with File > Properties > Compressed off" ]
}
