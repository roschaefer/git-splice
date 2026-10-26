# check_drawing on a plain SVG drawing, against the sync-model scenario:
# the check reads what the picture shows, so each change to the picture
# is checked, and what isn't in the drawing format fails it.

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
# R's arrow, from its box to d'.
r_arrow='<line x1="812" y1="75" x2="744" y2="75" marker-end="url(#arrow)"/>'

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

@test "drawing-svg: an arrow with a bend is a polyline" {
  sed -i "s|$r_arrow|<polyline points=\"860,95 860,140 790,140 790,103 734,100\" marker-end=\"url(#arrow)\"/>|" "$drawing"
  run check_drawing "$drawing"
  [ "$status" -eq 0 ]
  sed -i 's| marker-end="url(#arrow)"/></svg>|/></svg>|; s|\(<polyline [^>]*\) marker-end="url(#arrow)"|\1|' "$drawing"
  run check_drawing "$drawing"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   the polyline from 860,95 has no arrowhead: give it marker-end, or draw a separator as a line" ]
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

@test "drawing-svg: a shape outside the format is named" {
  # what replaces R's arrow, and the check's first line.
  local shape expected failed=""
  while IFS='|' read -r shape expected; do
    content="$(cat "$committed")"
    printf '%s\n' "${content/"$r_arrow"/"$shape"}" >"$drawing"
    run check_drawing "$drawing"
    [[ "${lines[0]}" == "$expected" ]] || failed+=$'\n'"$shape: ${lines[0]}"
  done <<'EOF'
<path d="M 812 75 L 744 75" marker-end="url(#arrow)"/>|!!   a <path>: check-drawing reads circles, rects, lines, polylines and texts only
<g><line x1="812" y1="75" x2="744" y2="75" marker-end="url(#arrow)"/></g>|!!   a <g>: check-drawing reads circles, rects, lines, polylines and texts only
<svg viewBox="0 0 1896 1140"><line x1="812" y1="75" x2="744" y2="75" marker-end="url(#arrow)"/></svg>|!!   an <svg> is inside the <svg>: put each shape directly into the outer one
<line x1="812" y1="75" x2="744" y2="75" marker-end="url(#other)"/>|!!   a <line> has marker-end="url(#other)": an arrowhead is url(#arrow)
<line x1="812" y1="75" x2="744" y2="75" stroke-dasharray="0 0" marker-end="url(#arrow)"/>|!!   a <line> has stroke-dasharray="0 0": give it dash lengths, like "6 4"
<line x1="812" y1="75" x2="744" y2="75" stroke-dasharray="none" marker-end="url(#arrow)"/>|!!   a <line> has stroke-dasharray="none": give it dash lengths, like "6 4"
<polyline points="812,75 800" marker-end="url(#arrow)"/>|!!   the polyline 812,75 800 isn't two or more points
EOF
  [ -z "$failed" ] || {
    echo "$failed"
    false
  }
}

@test "drawing-svg: a shape has only the format's attributes, in plain numbers" {
  # attribute on the circle a, its value, and the check's first line.
  local attr value expected failed=""
  while IFS='|' read -r attr value expected; do
    cp "$committed" "$drawing"
    edit_drawing -d "(//s:circle)[1]/@$attr" -i "(//s:circle)[1]" -t attr -n "$attr" -v "$value"
    run check_drawing "$drawing"
    [[ "${lines[0]}" == "$expected" ]] || failed+=$'\n'"$attr=$value: ${lines[0]}"
  done <<'EOF'
transform|translate(5,0)|!!   a <circle> has transform: check-drawing reads only cx, cy, r, stroke-dasharray, class on a <circle>, so remove it
style|stroke-dasharray:none|!!   a <circle> has style: check-drawing reads only cx, cy, r, stroke-dasharray, class on a <circle>, so remove it
marker-end|url(#arrow)|!!   a <circle> has marker-end: check-drawing reads only cx, cy, r, stroke-dasharray, class on a <circle>, so remove it
cx|50%|!!   a <circle> has cx="50%", which isn't a plain number
class|commit|ok   before-pull.svg: 10 commits, 13 arrows, 5 boxes, 1 lanes
EOF
  [ -z "$failed" ] || {
    echo "$failed"
    false
  }
}

@test "drawing-svg: a label is plain text, without a tspan" {
  edit_drawing -d "$(text_at 213 495)/text()" -s "$(text_at 213 495)" -t elem -n tspan -v a
  run check_drawing "$drawing"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   the text a holds other elements, e.g. a <tspan>: write the label as plain text" ]
}

@test "drawing-svg: the stylesheet sets only colors, strokes and fonts" {
  sed -i 's|</style>|circle { stroke-dasharray: none; } line { marker-end: none; }</style>|' "$drawing"
  run check_drawing "$drawing"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   the <style> sets stroke-dasharray: it may set only fill, stroke, stroke-width, background-color, font-family, font-size, font-weight, text-anchor, dominant-baseline" ]
  [ "${lines[1]}" = "!!   the <style> sets marker-end: it may set only fill, stroke, stroke-width, background-color, font-family, font-size, font-weight, text-anchor, dominant-baseline" ]
}

@test "drawing-svg: an arrowhead needs its marker" {
  edit_drawing -d '//s:marker'
  run check_drawing "$drawing"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = '!!   the arrowhead url(#arrow) is drawn by no <marker id="arrow"> in <defs>: add one' ]
}
