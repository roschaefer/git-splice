# check_drawing on a plain SVG drawing, against the sync-model scenario:
# the check reads what the picture shows, so each change to the picture
# is checked, and a shape it can't read fails it.

setup() {
  load 'helpers/fixtures'
  load '../check-drawing/check-drawing'
  hermetic_git_config
  load 'scenarios/01-everyday-sync/01-sync-model/setup'
  PATH="$BATS_TEST_DIRNAME/..:$PATH"
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
  scenario_sync_model "$monorepo" "$upstream"
  committed="$BATS_TEST_DIRNAME/scenarios/01-everyday-sync/01-sync-model/before-pull.svg"
  drawing="$BATS_TEST_TMPDIR/before-pull.svg"
  cp "$committed" "$drawing"
  cd "$monorepo"
}

# Applies xmlstarlet ed options to the drawing; s: is SVG's namespace.
edit_drawing() {
  xmlstarlet ed -L -N s=http://www.w3.org/2000/svg "$@" "$drawing"
}

# The circle or text at x, y.
circle_at() { echo "//s:circle[@cx=\"$1\" and @cy=\"$2\"]"; }
text_at() { echo "//s:text[@x=\"$1\" and @y=\"$2\"]"; }
# The arrow that starts at x, y.
arrow_from() { echo "//s:line[@x1=\"$1\" and @y1=\"$2\"]"; }

@test "drawing-svg: the committed one matches its scenario" {
  run check_drawing "$committed"
  [ "$status" -eq 0 ]
  [ "$output" = "ok   before-pull.svg: 10 commits, 13 arrows, 5 boxes, 1 lanes" ]
}

@test "drawing-svg: a solid rebuilt commit is to be dashed" {
  edit_drawing -d "$(circle_at 709 355)/@stroke-dasharray"
  run check_drawing "$drawing"
  [ "$status" -eq 1 ]
  [ "$output" = "!!   b' is solid, but no upstream branch has it: dash it" ]
}

@test "drawing-svg: a style's stroke-dasharray counts like the attribute, none too" {
  edit_drawing -d "$(circle_at 709 355)/@stroke-dasharray" -i "$(circle_at 709 355)" -t attr -n style -v 'stroke-dasharray:6, 4'
  run check_drawing "$drawing"
  [ "$status" -eq 0 ]
  edit_drawing -i "$(circle_at 709 75)" -t attr -n style -v 'fill:none;stroke-dasharray:none'
  run check_drawing "$drawing"
  [ "$status" -eq 1 ]
  [ "$output" = "!!   d' is solid, but no upstream branch has it: dash it" ]
}

@test "drawing-svg: a box's arrow moved to another commit names the right one" {
  edit_drawing -u "$(arrow_from 812 75)/@x2" -v 744 -u "$(arrow_from 812 75)/@y2" -v 355
  run check_drawing "$drawing"
  [ "$status" -eq 1 ]
  [ "$output" = "!!   R points at b', the code says d'" ]
}

@test "drawing-svg: a relabelled commit is looked up by its new label" {
  edit_drawing -u "$(text_at 534 216)" -v l -u "$(text_at 534 355)" -v m
  run check_drawing "$drawing"
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   m -> l: m isn't a parent of l"* ]]
}

@test "drawing-svg: an arrow that ends in empty space touches no commit" {
  edit_drawing -u "$(arrow_from 812 75)/@x2" -v 760
  run check_drawing "$drawing"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   the arrow from 812,75 to 760,75 doesn't touch a commit or box at its end: end it on the outline" ]
}

@test "drawing-svg: an arrow with a bend is a path of straight lines" {
  edit_drawing -d "$(arrow_from 812 75)" -s '/s:svg' -t elem -n path -v '' \
    -i '/s:svg/path[last()]' -t attr -n d -v 'M 860 95 V 140 H 790 V 103 L 734 100' \
    -i '/s:svg/path[last()]' -t attr -n marker-end -v 'url(#arrow)'
  run check_drawing "$drawing"
  [ "$status" -eq 0 ]
}

@test "drawing-svg: a circle without a label is named" {
  edit_drawing -d "$(text_at 213 495)"
  run check_drawing "$drawing"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   the circle at 213,495 has no label: write one into it" ]
}

@test "drawing-svg: a text in no shape is named" {
  edit_drawing -s '/s:svg' -t elem -n text -v 'before the pull' \
    -i '/s:svg/text[last()]' -t attr -n x -v 100 -i '/s:svg/text[last()]' -t attr -n y -v 300
  run check_drawing "$drawing"
  [ "$status" -eq 1 ]
  [ "$output" = "!!   the text before the pull is neither a label nor an upstream's name: put it in a circle or box, or leave it out" ]
}

@test "drawing-svg: a moved group is refused, not guessed" {
  edit_drawing -i "$(circle_at 213 495)" -t attr -n transform -v 'translate(5,0)'
  run check_drawing "$drawing"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = '!!   a <circle> is moved with transform="translate(5,0)": write the position into its coordinates instead' ]
}

@test "drawing-svg: a shape it can't read is named" {
  edit_drawing -s '/s:svg' -t elem -n polygon -v ''
  run check_drawing "$drawing"
  [ "$status" -eq 1 ]
  [ "$output" = "!!   a <polygon>: check-drawing reads circles, rects, lines, polylines, paths and texts only" ]
}

@test "drawing-svg: a label in a tspan, as Inkscape writes it, is read where the tspan puts it" {
  edit_drawing -d "$(text_at 213 495)/text()" -s "$(text_at 213 495)" -t elem -n tspan -v a \
    -i "$(text_at 213 495)/tspan" -t attr -n x -v 213 -i "$(text_at 213 495)/tspan" -t attr -n y -v 495
  run check_drawing "$drawing"
  [ "$status" -eq 0 ]
  edit_drawing -u "$(text_at 213 495)/s:tspan/@x" -v 600 -u "$(text_at 213 495)/s:tspan/@y" -v 300
  run check_drawing "$drawing"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   the circle at 213,495 has no label: write one into it" ]
}

@test "drawing-svg: a label shifted by dx is refused, not guessed" {
  edit_drawing -i "$(text_at 213 495)" -t attr -n dx -v 400
  run check_drawing "$drawing"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   the text a is shifted with dx, dy or rotate: write its position into x and y" ]
}

@test "drawing-svg: the stylesheet may not dash, hide or give arrowheads" {
  sed -i 's|</style>|circle { stroke-dasharray: none; } line { marker-end: none; }</style>|' "$drawing"
  run check_drawing "$drawing"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   the <style> sets stroke-dasharray: set it on each shape it applies to, where the check reads it" ]
  [ "${lines[1]}" = "!!   the <style> sets marker-end: set it on each shape it applies to, where the check reads it" ]
}

@test "drawing-svg: an arrowhead no marker draws is named" {
  sed -i 's|marker-end="url(#arrow)"|marker-end="url(#nonexistent)"|' "$drawing"
  run check_drawing "$drawing"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   the arrow from 106,75 has the arrowhead url(#nonexistent), which no <marker> draws: point it at one in <defs>" ]
  cp "$committed" "$drawing"
  edit_drawing -d '//s:marker'
  run check_drawing "$drawing"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   the arrow from 106,75 has the arrowhead url(#arrow), which no <marker> draws: point it at one in <defs>" ]
}

@test "drawing-svg: an arrow in two pieces is refused, though its ends touch" {
  edit_drawing -u "$(arrow_from 812 75)/@x2" -v 800 -s '/s:svg' -t elem -n path -v '' \
    -i '/s:svg/path[last()]' -t attr -n d -v 'M 812 75 L 800 75 M 755 75 L 744 75' \
    -i '/s:svg/path[last()]' -t attr -n marker-end -v 'url(#arrow)' -d "$(arrow_from 812 75)"
  run check_drawing "$drawing"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   the path M 812 75 L 800 75 M 755 75 L 744 75 has several pieces: draw each arrow as one piece, with one M" ]
}

@test "drawing-svg: a hidden shape is refused, not read" {
  edit_drawing -i "$(circle_at 709 75)" -t attr -n style -v 'display:none'
  run check_drawing "$drawing"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   a <circle> is hidden: delete it, or show it" ]
}

@test "drawing-svg: marker draws an arrowhead at both ends, so an arrow uses marker-end" {
  edit_drawing -r "$(arrow_from 812 75)/@marker-end" -v marker
  run check_drawing "$drawing"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   a <line> has marker or marker-mid: give an arrow one arrowhead, with marker-end" ]
}

@test "drawing-svg: a group may not dash what's in it" {
  sed -i 's|<circle cx="534" cy="75" r="35"/>|<g stroke-dasharray="6 4"><circle cx="534" cy="75" r="35"/></g>|' "$drawing"
  run check_drawing "$drawing"
  [ "$status" -eq 1 ]
  [ "$output" = "!!   a <g> sets stroke-dasharray, which check-drawing doesn't read on a <g>: set it on each shape it applies to" ]
}

@test "drawing-svg: path numbers without a space between them are read apart" {
  sed -i 's|<line x1="812" y1="75" x2="744" y2="75" marker-end="url(#arrow)"/>|<path d="M812 75l-68-280" marker-end="url(#arrow)"/>|' "$drawing"
  run check_drawing "$drawing"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   the arrow from 812,75 to 744,-205 doesn't touch a commit or box at its end: end it on the outline" ]
  sed -i 's|M812 75l-68-280|M812 75l-68|' "$drawing"
  run check_drawing "$drawing"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   the path M812 75l-68 isn't one the check reads: draw arrows with M, L, H and V and their numbers only" ]
}

@test "drawing-svg: a shape sets only what the check reads and colors, strokes and fonts" {
  # attribute on the circle a, its value, and the check's first line.
  local attr value expected failed=""
  while IFS='|' read -r attr value expected; do
    cp "$committed" "$drawing"
    edit_drawing -d "(//s:circle)[1]/@$attr" -i "(//s:circle)[1]" -t attr -n "$attr" -v "$value"
    run check_drawing "$drawing"
    [[ "${lines[0]}" == "$expected" ]] || failed+=$'\n'"$attr=$value: ${lines[0]}"
  done <<'EOF'
style|transform:translate(400px, 0px)|!!   a <circle> is moved with transform="translate(400px, 0px)": write the position into its coordinates instead
style|cx: 600|!!   a <circle> sets cx, which check-drawing doesn't read: remove it
style|visibility:hidden|!!   a <circle> is hidden: delete it, or show it
filter|url(#blur)|!!   a <circle> sets filter, which check-drawing doesn't read: remove it
cx|50%|!!   a <circle> has cx="50%", which isn't a plain number: write it in user units, without a unit or %
marker-end|url(#arrow)|!!   a <circle> sets marker-end, which check-drawing doesn't read on a <circle>: set it on each shape it applies to
style|fill:#eee;stroke:#333;stroke-width:3;opacity:1;display:inline|ok   before-pull.svg: 10 commits, 13 arrows, 5 boxes, 1 lanes
EOF
  [ -z "$failed" ] || {
    echo "$failed"
    false
  }
}
