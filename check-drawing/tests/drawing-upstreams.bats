# check_drawing with several upstreams, against the fork-default-branch
# drawing: a dashed line splits the splice's lane, a text on each side
# names the upstream whose commits it holds, and a commit both have is
# drawn on each side.

setup_file() {
  load '../../docs/tests/helpers/fixtures'
  hermetic_git_config
  load '../../docs/09-scenarios/04-upstreams/02-several-upstreams/setup'
  PATH="$(dirname "$ENTRYPOINT"):$PATH"
  scenario_several_upstreams "$BATS_FILE_TMPDIR/monorepo" "$BATS_FILE_TMPDIR/upstream.git"
  git -C "$BATS_FILE_TMPDIR/upstream-fork.git" branch -m main trunk
  cd "$BATS_FILE_TMPDIR/monorepo"
  git config --file vendor/a/.splice upstream.fork.url "$BATS_FILE_TMPDIR/upstream-fork.git"
  git config --file vendor/a/.splice upstream.fork.default-branch trunk
  git config --file vendor/a/.splice splice.default-upstream origin
  git commit -q -m "vendor/a: add the company fork" -- vendor/a/.splice
  splice fetch >/dev/null
}

setup() {
  load '../../docs/tests/helpers/fixtures'
  load '../check-drawing'
  hermetic_git_config
  load '../../docs/09-scenarios/04-upstreams/02-several-upstreams/setup'
  PATH="$(dirname "$ENTRYPOINT"):$PATH"
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
  fork="$BATS_TEST_TMPDIR/upstream-fork.git"
  copy_file_repositories
  cd "$monorepo"
  drawing="$BATS_TEST_TMPDIR/fork-default-branch.drawio"
  xmlstarlet sel -T -N s=http://www.w3.org/2000/svg -t -v '/s:svg/@content' \
    "$BATS_TEST_DIRNAME/../../docs/09-scenarios/04-upstreams/02-several-upstreams/fork-default-branch.drawio.svg" >"$drawing" 2>/dev/null
  revs=(a=HEAD~1 c=HEAD k="refs/splices/$(git splice key --upstream origin vendor/a)/heads/main"
    f="refs/splices/$(git splice key --upstream fork vendor/a)/heads/trunk")
}

edit_drawing() {
  xmlstarlet ed -L "$@" "$drawing"
}

@test "drawing upstreams: the committed one matches its scenario" {
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 0 ]
  [ "$output" = "ok   fork-default-branch.drawio: 5 commits, 5 arrows, 3 boxes, 1 lanes, 2 upstreams" ]
}

@test "drawing upstreams: a commit on the side of an upstream that lacks it" {
  edit_drawing -u '//mxCell[@id="side_o"]/@value' -v fork -u '//mxCell[@id="side_f"]/@value' -v origin
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   f is on the origin side, but no fetched branch of origin has it: draw it on the side of an upstream that has it"* ]]
}

@test "drawing upstreams: a side named after no upstream of the splice" {
  edit_drawing -u '//mxCell[@id="side_f"]/@value' -v mirror
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   vendor/a/ has no upstream named mirror: name a side after one of its upstreams, origin fork" ]
}

@test "drawing upstreams: a side of an upstream nobody fetched is no side of the default upstream" {
  git config --file vendor/a/.splice upstream.mirror.url "$BATS_TEST_TMPDIR/mirror.git"
  git commit -q -m "vendor/a: name a mirror" -- vendor/a/.splice
  edit_drawing -u '//mxCell[@id="side_f"]/@value' -v mirror
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   mirror of vendor/a/ was never fetched: fetch it before drawing its side" ]
}

@test "drawing upstreams: a parent arrow across the separator asks for the parent on both sides" {
  edit_drawing -u '//mxCell[@source="kf" and @target="f"]/@source' -v ko
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   k -> f crosses the separator: draw the parent on f's side too"* ]]
}

@test "drawing upstreams: a box on the other side than its commit" {
  edit_drawing -u '//mxCell[@id="tr"]/mxGeometry/@x' -v 700 -u '//mxCell[@id="tr"]/mxGeometry/@y' -v 155
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   trunk points at f, on the fork side: draw the box on that side"* ]]
}

@test "drawing upstreams: a branch box names the branch of its side's upstream" {
  edit_drawing -u '//mxCell[@id="tr"]/@value' -v main
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   main points at f, but there's no main"* ]]
}

@test "drawing upstreams: a separator is dashed" {
  edit_drawing -u '//mxCell[@id="sep"]/@style' -v 'line;direction=south;strokeWidth=1;'
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   a line in vendor/a/ is solid: dash it, a separator is dashed" ]
}

@test "drawing upstreams: a separator runs from top to bottom" {
  edit_drawing -u '//mxCell[@id="sep"]/@style' -v 'line;dashed=1;strokeWidth=1;'
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   a line in vendor/a/ isn't vertical: a separator runs from top to bottom, direction=south" ]
}

@test "drawing upstreams: one upstream names one side" {
  edit_drawing -u '//mxCell[@id="side_f"]/@value' -v origin
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   origin names two sides of vendor/a/: name each side after another upstream" ]
}

@test "drawing upstreams: every side is named, even one with nothing on it" {
  local cell='//mxCell[@id="sep2"]'
  edit_drawing -s '/mxfile/diagram/mxGraphModel/root' -t elem -n mxCell -i '$prev' -t attr -n id -v sep2 \
    -s "$cell" -t attr -n parent -v 1 -s "$cell" -t attr -n vertex -v 1 \
    -s "$cell" -t attr -n style -v 'line;direction=south;dashed=1;' -s "$cell" -t elem -n mxGeometry \
    -s "$cell/mxGeometry" -t attr -n x -v 1370 -s "$cell/mxGeometry" -t attr -n y -v 60 \
    -s "$cell/mxGeometry" -t attr -n width -v 20 -s "$cell/mxGeometry" -t attr -n height -v 300
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "!!   side 3 of vendor/a/, from the left, names no upstream: label each side with its upstream's name" ]
}

@test "drawing upstreams: a commit is drawn once per side" {
  edit_drawing -u '//mxCell[@id="f"]/@value' -v k
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   k is drawn twice on the fork side of vendor/a/: draw it once per side"* ]]
}

@test "drawing upstreams: a text outside every split lane is still read as a box" {
  edit_drawing -u '//mxCell[@id="h"]/@style' -v 'text;fontSize=22;' -u '//mxCell[@source="h"]/@target' -v a
  run check_drawing "$drawing" "${revs[@]}"
  [ "$status" -eq 1 ]
  [ "$output" = "$(printf '%s\n' "!!   H points at a, the code says c" "!!   B points at a, the code says c")" ]
}

@test "drawing upstreams: one label on two sides names one commit, even where both upstreams have a commit with that subject" {
  seed_bare_repo "$upstream" "fork patch" main other.txt
  splice fetch >/dev/null
  edit_drawing -u '//mxCell[@id="ko"]/@value' -v 'fork patch' -u '//mxCell[@id="f"]/@value' -v 'fork patch'
  run check_drawing "$drawing" a=HEAD~1 c=HEAD
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   fork patch names one commit on the origin side and another on the fork side: label them apart"* ]]
}

# After a pull from the fork, R is the fork's f, which origin lacks: drawn
# on both sides, solid on the fork's, dashed on origin's, where the next
# push would bring it. $1 styles origin's f.
pulled_from_fork() {
  splice pull --upstream fork vendor/a >/dev/null
  cat >"$drawing" <<XML
<mxfile><diagram id="d"><mxGraphModel><root><mxCell id="0" /><mxCell id="1" parent="0" />
<mxCell id="lane" parent="1" vertex="1" style="rounded=1;fillColor=none;" value="vendor/a/"><mxGeometry x="422" y="30" width="990" height="354" as="geometry" /></mxCell>
<mxCell id="sep" parent="1" vertex="1" style="line;direction=south;dashed=1;" value=""><mxGeometry x="1060" y="60" width="20" height="304" as="geometry" /></mxCell>
<mxCell id="side_o" parent="1" vertex="1" style="text;" value="origin"><mxGeometry x="440" y="64" width="120" height="24" as="geometry" /></mxCell>
<mxCell id="side_f" parent="1" vertex="1" style="text;" value="fork"><mxGeometry x="1090" y="64" width="120" height="24" as="geometry" /></mxCell>
<mxCell id="p" parent="1" vertex="1" style="ellipse;" value="p"><mxGeometry x="229" y="40" width="70" height="70" as="geometry" /></mxCell>
<mxCell id="c" parent="1" vertex="1" style="ellipse;" value="c"><mxGeometry x="229" y="140" width="70" height="70" as="geometry" /></mxCell>
<mxCell id="ko" parent="1" vertex="1" style="ellipse;" value="k"><mxGeometry x="521" y="274" width="70" height="70" as="geometry" /></mxCell>
<mxCell id="fo" parent="1" vertex="1" style="$1" value="f"><mxGeometry x="521" y="140" width="70" height="70" as="geometry" /></mxCell>
<mxCell id="kf" parent="1" vertex="1" style="ellipse;" value="k"><mxGeometry x="1160" y="274" width="70" height="70" as="geometry" /></mxCell>
<mxCell id="f" parent="1" vertex="1" style="ellipse;" value="f"><mxGeometry x="1160" y="140" width="70" height="70" as="geometry" /></mxCell>
<mxCell id="eko" parent="1" edge="1" source="ko" target="fo" style="$2"><mxGeometry relative="1" as="geometry" /></mxCell>
<mxCell id="ekf" parent="1" edge="1" source="kf" target="f" style=""><mxGeometry relative="1" as="geometry" /></mxCell>
<mxCell id="ecp" parent="1" edge="1" source="c" target="p" style=""><mxGeometry relative="1" as="geometry" /></mxCell>
<mxCell id="tr" parent="1" vertex="1" style="rounded=1;" value="trunk"><mxGeometry x="1280" y="155" width="98" height="40" as="geometry" /></mxCell>
<mxCell id="etr" parent="1" edge="1" source="tr" target="f" style=""><mxGeometry relative="1" as="geometry" /></mxCell>
</root></mxGraphModel></diagram></mxfile>
XML
}

@test "drawing upstreams: R's commit an upstream lacks is drawn dashed on that upstream's side" {
  pulled_from_fork 'ellipse;dashed=1;' 'dashed=1;'
  run check_drawing "$drawing" c=HEAD~1 p=HEAD "${revs[2]}" "${revs[3]}"
  [ "$status" -eq 0 ]
}

@test "drawing upstreams: R's commit an upstream lacks is solid on no side of it" {
  pulled_from_fork 'ellipse;' ''
  run check_drawing "$drawing" c=HEAD~1 p=HEAD "${revs[2]}" "${revs[3]}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"!!   f is solid, but no branch of origin has it: dash it"* ]]
  [[ "$output" == *"!!   k -> f is solid, but no branch of origin has f: dash it"* ]]
}
