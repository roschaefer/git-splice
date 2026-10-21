# check_drawing with several upstreams, against the fork-default-branch
# drawing: a dashed line splits the splice's lane, a text on each side
# names the upstream whose commits it holds, and a commit both have is
# drawn on each side.

setup() {
  load 'helpers/fixtures'
  load '../check-drawing/check-drawing'
  hermetic_git_config
  load 'scenarios/04-upstreams/02-several-upstreams/setup'
  PATH="$BATS_TEST_DIRNAME/..:$PATH"
  monorepo="$BATS_TEST_TMPDIR/monorepo"
  upstream="$BATS_TEST_TMPDIR/upstream.git"
  fork="$BATS_TEST_TMPDIR/upstream-fork.git"
  scenario_several_upstreams "$monorepo" "$upstream"
  git -C "$fork" branch -m main trunk
  cd "$monorepo"
  git config --file vendor/a/.splice upstream.fork.url "$fork"
  git config --file vendor/a/.splice upstream.fork.default-branch trunk
  git config --file vendor/a/.splice splice.default-upstream origin
  git commit -q -m "vendor/a: add the company fork" -- vendor/a/.splice
  splice fetch >/dev/null
  drawing="$BATS_TEST_TMPDIR/fork-default-branch.drawio"
  xmlstarlet sel -T -N s=http://www.w3.org/2000/svg -t -v '/s:svg/@content' \
    "$BATS_TEST_DIRNAME/scenarios/04-upstreams/02-several-upstreams/fork-default-branch.drawio.svg" >"$drawing" 2>/dev/null
  revs=(a=HEAD~1 c=HEAD k="refs/splices/$(git splice key --upstream origin vendor/a)/main"
    f="refs/splices/$(git splice key --upstream fork vendor/a)/trunk")
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
