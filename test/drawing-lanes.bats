# check_drawing with several splices, against the nested-splices drawing:
# each splice's upstream commits and boxes sit in a lane labelled with its
# folder.

setup() {
  load 'helpers/fixtures'
  load 'helpers/drawing'
  hermetic_git_config
  load 'scenarios/nested-splices/setup'
  PATH="$BATS_TEST_DIRNAME/..:$PATH"
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
  scenario_nested_splices "$monorepo" "$upstream"
  drawing="$BATS_TEST_TMPDIR/nested-splices.drawio"
  xmlstarlet sel -T -N s=http://www.w3.org/2000/svg -t -v '/s:svg/@content' \
    "$BATS_TEST_DIRNAME/scenarios/nested-splices/nested-splices.drawio.svg" >"$drawing" 2>/dev/null
  revs=(a=HEAD k=refs/splices/upstream/main~1 l=refs/splices/upstream/main m=refs/splices/upstream-b/main)
  cd "$monorepo"
}

edit_drawing() {
  xmlstarlet ed -L "$@" "$drawing"
}

@test "drawing lanes: the committed one matches its scenario" {
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 0 ]
  [ "$output" = "ok   nested-splices.drawio: 4 commits, 5 arrows, 4 boxes, 1 frames, 2 lanes" ]
}

@test "drawing lanes: several splices without lanes ask for them" {
  edit_drawing -d '//mxCell[@id="lane_a" or @id="lane_b"]'
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [ "$output" = "!!   the monorepo has 2 splices: draw a lane for each one the drawing shows, labelled with its folder, e.g. vendor/a/" ]
}

@test "drawing lanes: a lane that names no splice, and the boxes in it" {
  edit_drawing -u '//mxCell[@id="lane_b"]/@value' -v vendor/x/
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   the lane vendor/x/ isn't a splice of the monorepo" ]
  [[ "$output" == *"!!   T is in no lane: draw it in the lane of its splice"* ]]
}

@test "drawing lanes: a box in the wrong lane names the right commit" {
  edit_drawing -u '//mxCell[@id="lane_b"]/@value' -v vendor/a/ -u '//mxCell[@id="lane_a"]/@value' -v vendor/a/b/
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   T points at m, the code says l"* ]]
}

@test "drawing lanes: a frame's path is the splice's folder in the repository of the commit it holds" {
  edit_drawing -u '//mxCell[@id="frame_l"]/@value' -v 'l:vendor/a/b/.splice'
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = '!!   the frame "l:vendor/a/b/.splice" names no splice of the monorepo' ]
}
