# check-export, with draw.io: a drawing whose picture isn't its diagram's
# export fails, and --write exports it again. Needs draw.io, so it runs in
# `nix develop .#drawings`, as `just drawings-check` does.

setup() {
  command -v drawio >/dev/null || skip "needs draw.io: nix develop .#drawings --command bats test/drawing-export.bats"
  drawing="$BATS_TEST_TMPDIR/fork.drawio.svg"
  cp "$BATS_TEST_DIRNAME/walkthrough/fork.drawio.svg" "$drawing"
}

# Renames the box fix/parser in the diagram only, as an edit without
# exporting again leaves it.
rename_in_diagram() {
  sed -i 's/value=&quot;fix\/parser&quot;/value=\&quot;fix\/lexer\&quot;/' "$drawing"
}

@test "drawing-export: a drawing as draw.io exported it passes" {
  run "$BATS_TEST_DIRNAME/../check-drawing/check-export" "$drawing"
  [ "$status" -eq 0 ]
  [ "$output" = "ok   1 drawings show their diagrams" ]
}

@test "drawing-export: a diagram edited without exporting again fails" {
  rename_in_diagram
  run "$BATS_TEST_DIRNAME/../check-drawing/check-export" "$drawing"
  [ "$status" -eq 1 ]
  [ "$output" = "!!   $drawing: the picture isn't its diagram's export: run 'just drawings-check --write'" ]
}

@test "drawing-export: a picture edited by hand fails" {
  sed -i 's/>fix\/parser</>fix\/lexer</' "$drawing"
  run "$BATS_TEST_DIRNAME/../check-drawing/check-export" "$drawing"
  [ "$status" -eq 1 ]
}

@test "drawing-export: --write exports the diagram again, into the picture" {
  rename_in_diagram
  run "$BATS_TEST_DIRNAME/../check-drawing/check-export" --write "$drawing"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "wrote $drawing" ]
  grep -q '>fix/lexer<' "$drawing"
  run "$BATS_TEST_DIRNAME/../check-drawing/check-export" "$drawing"
  [ "$status" -eq 0 ]
}
