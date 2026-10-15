# check_drawing with several splices, against the nested-splices drawing:
# each splice's upstream commits and boxes sit in a lane labelled with its
# folder.

setup() {
  load 'helpers/fixtures'
  load '../check-drawing/check-drawing'
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
  [ "$output" = "ok   nested-splices.drawio: 4 commits, 5 arrows, 4 boxes, 2 lanes" ]
}

@test "drawing lanes: several splices without lanes ask for them" {
  edit_drawing -d '//mxCell[@id="lane_a" or @id="lane_b"]'
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [ "$output" = "!!   the monorepo has 2 splices: draw a lane for each one the drawing shows, labelled with its folder, e.g. vendor/a/" ]
}

@test "drawing lanes: the generic path/ stands for a splice only when there's one" {
  edit_drawing -u '//mxCell[@id="lane_b"]/@value' -v path/
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   the lane path/ isn't a splice of the monorepo" ]
}

@test "drawing lanes: a lane that names no splice" {
  edit_drawing -u '//mxCell[@id="lane_b"]/@value' -v vendor/x/
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   the lane vendor/x/ isn't a splice of the monorepo" ]
}

@test "drawing lanes: a lane inside another is a folder inside that one" {
  edit_drawing -u '//mxCell[@id="lane_b"]/@value' -v vendor/a/ -u '//mxCell[@id="lane_a"]/@value' -v vendor/a/b/
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   the lane vendor/a/ is drawn inside vendor/a/b/, but its folder isn't inside that one"* ]]
  [[ "$output" == *"!!   T points at m, the code says l"* ]]
}

@test "drawing lanes: a commit in another splice's lane" {
  edit_drawing -u '//mxCell[@id="m"]/mxGeometry/@x' -v 500
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   m is in the lane vendor/a/, but isn't in that splice's upstream history or R" ]
}

@test "drawing lanes: U(x) of a label two commits share is ambiguous" {
  edit_drawing -u '//mxCell[@id="k"]/@value' -v l
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   U(l) points at m, but 2 commits are labelled l: label them apart"* ]]
}

@test "drawing lanes: U(H) is no label, however many commits are labelled H" {
  edit_drawing -u '//mxCell[@id="k"]/@value' -v H -u '//mxCell[@id="m"]/@value' -v H
  run check_drawing "$drawing" "${revs[@]}" H=refs/splices/upstream/main~1
  [[ "$output" != *"commits are labelled H"* ]]
}

@test "drawing lanes: an upstream commit outside every lane" {
  edit_drawing -u '//mxCell[@id="m"]/mxGeometry/@x' -v 1000
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   m isn't a monorepo commit, but it's outside every lane: draw it in its splice's lane" ]
}

@test "drawing lanes: a commit that juts out of its lane is outside it" {
  edit_drawing -u '//mxCell[@id="m"]/mxGeometry/@x' -v 860
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   m isn't a monorepo commit, but it's outside every lane: draw it in its splice's lane" ]
}

@test "drawing lanes: a box pointing into another splice's lane" {
  edit_drawing -u '//mxCell[@target="l" and @source!="k"]/@target' -v m
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   T = R = U(H) points at m, in the lane vendor/a/b/: draw the box in that lane" ]
}

@test "drawing lanes: an arrow between commits of two lanes" {
  edit_drawing -u '//mxCell[@source="k" and @target="l"]/@target' -v m
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   k -> m crosses lanes: draw a parent and its child in one lane" ]
}

@test "drawing lanes: a nested splice's lane is drawn inside its parent's" {
  edit_drawing -u '//mxCell[@id="lane_b"]/mxGeometry/@x' -v 1000 -u '//mxCell[@id="m"]/mxGeometry/@x' -v 1050
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   the lane vendor/a/b/ is a folder inside vendor/a/: draw it inside that lane" ]
}

@test "drawing lanes: a nested splice's lane lies wholly inside its parent's" {
  edit_drawing -u '//mxCell[@id="lane_b"]/mxGeometry/@width' -v 400
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   the lane vendor/a/b/ is a folder inside vendor/a/: draw it inside that lane" ]
}

@test "drawing lanes: with several splices, B outside every lane says why it can't be checked" {
  edit_drawing -u '//mxCell[@value="H"]/@value' -v B
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   B outside every lane doesn't say which splice's boundary it is: with several splices, leave B out" ]
}
