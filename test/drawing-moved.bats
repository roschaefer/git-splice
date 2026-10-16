# check_drawing after a `git mv` of the splice, against the
# moved-with-unpushed-commits drawing: U(x) of a commit from before the
# move is read from the folder the splice had then.

setup() {
  load 'helpers/fixtures'
  load '../check-drawing/check-drawing'
  hermetic_git_config
  load 'scenarios/up-to-date/push-ahead/moved-with-unpushed-commits/setup'
  PATH="$BATS_TEST_DIRNAME/..:$PATH"
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
  scenario_moved_with_unpushed_commits "$monorepo" "$upstream"
  cd "$monorepo"
  git mv vendor/a libs/a
  git commit -q -m "reorganize folders"
  drawing="$BATS_TEST_TMPDIR/moved-with-unpushed-commits.drawio"
  xmlstarlet sel -T -N s=http://www.w3.org/2000/svg -t -v '/s:svg/@content' \
    "$BATS_TEST_DIRNAME/scenarios/up-to-date/push-ahead/moved-with-unpushed-commits/moved-with-unpushed-commits.drawio.svg" >"$drawing" 2>/dev/null
  revs=(a=HEAD~2 b=HEAD~1 m=HEAD k=refs/splices/upstream/main)
}

edit_drawing() {
  xmlstarlet ed -L "$@" "$drawing"
}

@test "drawing moved: U(B) of a boundary from before the move is read under the old folder" {
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 0 ]
  [ "$output" = "ok   moved-with-unpushed-commits.drawio: 5 commits, 7 arrows, 4 boxes, 1 lanes" ]
}

@test "drawing moved: U(x) of a commit from before the move is read under the old folder" {
  edit_drawing -u '//mxCell[@id="box1"]/@value' -v 'T = U(a)'
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 0 ]
}
