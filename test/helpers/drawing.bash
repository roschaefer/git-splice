# shellcheck shell=bash
# Checks a draw.io drawing of splices' commit graphs against the
# repositories a scenario built: what the drawing shows, not where. Run in
# the monorepo; see test/scenarios/sync-model/README.md.
#
# The drawing's vocabulary:
#
#   - A circle (ellipse) is a commit. Its label is the commit's subject,
#     looked up on the monorepo's first-parent history, then upstream. A
#     label with a trailing ' (b' for b) is the rebuild's copy of the
#     commit without it: the same message, author and dates, in R's
#     history.
#   - An arrow between two commits points from a parent to its child.
#   - A box points at the commit its label names: H, B, T or R
#     (test/concepts/sync-model/README.md), U(x), the commit x's
#     .splice records, where x is H, B or a drawn commit, or an upstream
#     branch by its name, e.g. "main", as fetched. Several names
#     are joined by " = ", e.g. "U(H) = U(B)": each must name that
#     commit.
#   - A lane, a shape labelled with a splice's folder, e.g. "vendor/a/",
#     holds that splice's upstream commits and boxes. A monorepo with
#     several splices needs one per splice it draws, and what a lane
#     shows stays in it: arrows between commits, and boxes, don't cross
#     into another lane. With one splice, lanes are optional, the
#     generic "path/" names it, and a box outside every lane, like B,
#     is that splice's. A nested
#     splice's lane is drawn inside the lane of the splice above it, and
#     a shape belongs to the innermost lane around it.
#   - A frame labelled "x:<path>/.splice", Git's name for that file in
#     commit x, holds commit x, and usually the box U(x). <path> is the
#     splice's folder in x's repository: in the monorepo, or in the
#     upstream of the lane x is in. The generic "path" stands for the
#     splice of the lane the frame is in.
#   - Dashed commits and arrows into them aren't in the upstream's history
#     yet: no upstream branch has them, like R's copies of monorepo
#     commits, or commits a rewrite of the upstream removed. A solid
#     commit that T lacks needs a box for an upstream branch that has it.
#
# Labels that aren't subjects, like the commit add_splice makes, are given
# as label=rev arguments, revs of the monorepo.

DRAWING_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../lib" && pwd)"

# check_drawing <drawing> [<label>=<rev>...]
# Prints "ok" and what it checked, or each difference, and fails.
check_drawing() {
  local drawing="$1" xml default=""
  shift
  local -A rev_of=() commit_of=() label_of=() kind=() value=() style=() source=() target=() parent=()
  local -A gx=() gy=() gw=() gh=() truth=() splice_of=() lane_of=() is_splice=() lane_splice=()
  local -a errors=() commits=() edges=() boxes=() frames=() lanes=() splices=()
  local -A id_of_label=() label_count=()
  local arg id k cells term named sp p
  local name='([HBTR]|U\([^()]+\)|[^ =]+)'
  local box_label="^$name( = $name)*\$"

  for arg in "$@"; do
    rev_of[${arg%%=*}]="${arg#*=}"
  done

  if [[ "$drawing" == *.svg ]]; then
    xml="$(xmlstarlet sel -T -N s=http://www.w3.org/2000/svg -t -v '/s:svg/@content' "$drawing" 2>/dev/null)"
  else
    xml="$(cat "$drawing")"
  fi
  if [[ "$(xmlstarlet sel -T -t -v 'count(//mxGraphModel)' <<<"$xml" 2>/dev/null)" != 1 ]]; then
    printf '!!   %s: no diagram inside, or a compressed one: save it with File > Properties > Compressed off\n' "${drawing##*/}"
    return 1
  fi

  # One line per cell, fields separated by \x1f: read collapses repeated
  # tabs, and so would shift the fields after an empty one. Labels are
  # plain text: no html=1.
  cells="$(xmlstarlet sel -T -t -m '//mxCell[@id!="0" and @id!="1"]' \
    -v '@id' -o $'\x1f' -v 'concat("v",@vertex,"e",@edge)' -o $'\x1f' -v '@value' -o $'\x1f' -v '@style' -o $'\x1f' \
    -v '@source' -o $'\x1f' -v '@target' -o $'\x1f' -v '@parent' -o $'\x1f' \
    -v 'mxGeometry/@x' -o $'\x1f' -v 'mxGeometry/@y' -o $'\x1f' -v 'mxGeometry/@width' -o $'\x1f' -v 'mxGeometry/@height' -n <<<"$xml")"
  local c_id c_kind c_value c_style c_source c_target c_parent c_x c_y c_w c_h
  while IFS=$'\x1f' read -r c_id c_kind c_value c_style c_source c_target c_parent c_x c_y c_w c_h; do
    [[ -n "$c_id" ]] || continue
    value[$c_id]="$c_value" style[$c_id]="$c_style" source[$c_id]="$c_source" target[$c_id]="$c_target"
    parent[$c_id]="$c_parent" gx[$c_id]="${c_x:-0}" gy[$c_id]="${c_y:-0}" gw[$c_id]="${c_w:-0}" gh[$c_id]="${c_h:-0}"
    if [[ "$c_kind" == *e1 ]]; then
      kind[$c_id]=edge
      edges+=("$c_id")
    elif [[ "$c_value" =~ ^[^\ :]+:.*/\.splice$ ]]; then
      kind[$c_id]=frame
      frames+=("$c_id")
    elif [[ "$c_style" == ellipse* || "$c_style" == *";ellipse"* ]]; then
      kind[$c_id]=commit
      commits+=("$c_id")
    elif [[ "$c_value" =~ ^[^\ ]+/$ ]]; then
      kind[$c_id]=lane
      lanes+=("$c_id")
    elif [[ "$c_value" =~ $box_label ]]; then
      kind[$c_id]=box
      boxes+=("$c_id")
    fi
  done <<<"$cells"
  if [[ ${#commits[@]} -eq 0 ]]; then
    printf '!!   %s: no commits drawn\n' "${drawing##*/}"
    return 1
  fi

  # Where a shape is: its absolute position, and whether its center is
  # inside another shape.
  absolute() {
    local cell="$1" x=0 y=0
    while [[ -n "$cell" && "$cell" != 1 && -n "${gx[$cell]+set}" ]]; do
      x=$(awk -v a="$x" -v b="${gx[$cell]}" 'BEGIN { print a + b }')
      y=$(awk -v a="$y" -v b="${gy[$cell]}" 'BEGIN { print a + b }')
      cell="${parent[$cell]}"
    done
    printf '%s %s\n' "$x" "$y"
  }
  inside() {
    local cx cy ox oy
    read -r cx cy < <(absolute "$1")
    read -r ox oy < <(absolute "$2")
    awk -v cx="$cx" -v cy="$cy" -v w="${gw[$1]}" -v h="${gh[$1]}" -v fx="$ox" -v fy="$oy" -v fw="${gw[$2]}" -v fh="${gh[$2]}" \
      'BEGIN { x = cx + w / 2; y = cy + h / 2; exit !(x >= fx && x <= fx + fw && y >= fy && y <= fy + fh) }'
  }

  # The splices, and the lanes that name them.
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    splices+=("$p")
    is_splice[$p]=1
  done < <(git ls-tree -r --name-only HEAD | sed -n 's#/\.splice$##p')
  local l
  for l in "${lanes[@]}"; do
    if [[ -n "${is_splice[${value[$l]%/}]:-}" ]]; then
      lane_splice[$l]="${value[$l]%/}"
    elif [[ "${value[$l]}" == path/ && ${#splices[@]} -eq 1 ]]; then
      lane_splice[$l]="${splices[0]}"
    else
      errors+=("the lane ${value[$l]} isn't a splice of the monorepo")
    fi
  done
  if [[ ${#splices[@]} -eq 1 ]]; then
    default="${splices[0]}"
  elif [[ ${#lanes[@]} -eq 0 ]]; then
    printf '!!   the monorepo has %d splices: draw a lane for each one the drawing shows, labelled with its folder, e.g. %s/\n' \
      "${#splices[@]}" "${splices[0]:-vendor/a}"
    return 1
  fi
  # A shape is in the innermost lane around it. Lanes nest as their
  # folders do.
  local o area smallest
  for l in "${lanes[@]}"; do
    for o in "${lanes[@]}"; do
      [[ "$o" != "$l" ]] && inside "$l" "$o" && [[ "${value[$l]}" != "${value[$o]}"?* ]] &&
        errors+=("the lane ${value[$l]} is drawn inside ${value[$o]}, but its folder isn't inside that one")
      [[ "$o" != "$l" && "${value[$l]}" == "${value[$o]}"?* ]] && ! inside "$l" "$o" &&
        errors+=("the lane ${value[$l]} is a folder inside ${value[$o]}: draw it inside that lane")
    done
  done
  for id in "${commits[@]}" "${boxes[@]}" "${frames[@]}"; do
    lane_of[$id]="" smallest=""
    for l in "${lanes[@]}"; do
      [[ -n "${lane_splice[$l]:-}" ]] && inside "$id" "$l" || continue
      area=$(awk -v w="${gw[$l]}" -v h="${gh[$l]}" 'BEGIN { print w * h }')
      if [[ -z "$smallest" ]] || awk -v a="$area" -v b="$smallest" 'BEGIN { exit !(a < b) }'; then
        lane_of[$id]="${lane_splice[$l]}" smallest="$area"
      fi
    done
  done

  # What H names, and B, T, R, U(H) and U(B) of each splice the drawing
  # uses; T through the upstream branch the monorepo's branch maps to.
  truth[H]="$(git rev-parse HEAD)"
  load_truth() {
    local p="$1" c
    [[ -z "${truth[$p|loaded]:-}" ]] || return 0
    truth[$p|loaded]=1
    truth[$p|B]="$(git splice boundary "$p")"
    truth[$p|U]="$(git config --blob "HEAD:$p/.splice" splice.commit)"
    truth[$p|S]="$(git config --blob "${truth[$p|B]}:$p/.splice" splice.commit)"
    truth[$p|T]="$(git rev-parse --verify --quiet "$(
      # shellcheck source=../../lib/common.sh
      source "$DRAWING_LIB/common.sh"
      require_splice_upstream "$p"
      splice_ref "$p" "$(upstream_branch_for "$p" "$(git branch --show-current)")"
    )")"
    truth[$p|R]="$(git splice rebuild "$p")"
    truth[$p|key]="$(git splice key "$p")"
    truth[$p|synced]=""
    for c in $(git log --first-parent --format=%H HEAD -- "$p/.splice"); do
      truth[$p|synced]+=" $(git config --blob "$c:$p/.splice" splice.commit 2>/dev/null)"
    done
  }
  for id in "${commits[@]}" "${boxes[@]}"; do
    sp="${lane_of[$id]:-$default}"
    splice_of[$id]="$sp"
    [[ -z "$sp" ]] || load_truth "$sp"
  done

  # Commits, by label.
  local label base subject hash upstream_tips
  for id in "${commits[@]}"; do
    label="${value[$id]}"
    base="${label%\'}"
    sp="${splice_of[$id]}"
    hash=""
    if [[ -n "${rev_of[$base]:-}" ]]; then
      hash="$(git rev-parse --verify --quiet "${rev_of[$base]}^{commit}")"
    else
      hash="$(git log --first-parent --format='%H%x09%s' HEAD | awk -F'\t' -v s="$base" '$2 == s { print $1; exit }')"
      upstream_tips=()
      if [[ -n "$sp" ]]; then
        for k in T R U S; do
          [[ -n "${truth[$sp|$k]}" ]] && upstream_tips+=("${truth[$sp|$k]}")
        done
      fi
      [[ -n "$hash" || "$label" == *\' || ${#upstream_tips[@]} -eq 0 ]] ||
        hash="$(git log --format='%H%x09%s' "${upstream_tips[@]}" | awk -F'\t' -v s="$base" '$2 == s { print $1; exit }')"
    fi
    if [[ -n "$hash" && "$label" == *\' ]]; then
      if [[ -z "$sp" ]]; then
        errors+=("$label is in no lane: draw it in the lane of the splice it's rebuilt for")
        continue
      fi
      subject="$(git log -1 --format='%B%x1f%an%x1f%aD' "$hash")"
      hash="$(git log --format='%H' "${truth[$sp|R]}" | while read -r k; do
        [[ "$k" != "$hash" && "$(git log -1 --format='%B%x1f%an%x1f%aD' "$k")" == "$subject" ]] && { echo "$k"; break; }
      done)"
    fi
    if [[ -z "$hash" ]]; then
      errors+=("$label: no such commit")
      continue
    fi
    commit_of[$id]="$hash"
    label_of[$hash]="$label"
    id_of_label[$label]="$id"
    label_count[$label]=$((${label_count[$label]:-0} + 1))
  done

  # A commit in a lane is in that splice's upstream history: on R, on a
  # fetched upstream branch, or in a recorded commit's history.
  of_splice() {
    local s
    git merge-base --is-ancestor "$1" "${truth[$2|R]}" && return 0
    [[ -n "$(git for-each-ref --count=1 --contains "$1" "refs/splices/${truth[$2|key]}/")" ]] && return 0
    for s in ${truth[$2|synced]}; do
      git merge-base --is-ancestor "$1" "$s" 2>/dev/null && return 0
    done
    return 1
  }
  for id in "${commits[@]}"; do
    [[ -n "${commit_of[$id]:-}" ]] || continue
    if [[ ${#lanes[@]} -gt 0 && -z "${lane_of[$id]}" ]]; then
      git merge-base --is-ancestor "${commit_of[$id]}" HEAD ||
        errors+=("${value[$id]} isn't a monorepo commit, but it's outside every lane: draw it in its splice's lane")
      continue
    fi
    [[ -n "${lane_of[$id]}" ]] || continue
    of_splice "${commit_of[$id]}" "${lane_of[$id]}" ||
      errors+=("${value[$id]} is in the lane ${lane_of[$id]}/, but isn't in that splice's upstream history or R")
  done

  # A commit of splice $2 is dashed if it isn't in the upstream's history
  # yet: no fetched upstream branch has it.
  not_upstream() {
    [[ -n "$2" ]] || return 1
    ! git merge-base --is-ancestor "$1" HEAD 2>/dev/null || return 1
    [[ -z "$(git for-each-ref --count=1 --contains "$1" "refs/splices/${truth[$2|key]}/")" ]]
  }
  dashed() { [[ ";${style[$1]};" == *";dashed=1;"* ]]; }

  for id in "${commits[@]}"; do
    [[ -n "${commit_of[$id]:-}" ]] || continue
    if not_upstream "${commit_of[$id]}" "${splice_of[$id]}"; then
      dashed "$id" || errors+=("${value[$id]} is solid, but no upstream branch has it: dash it")
    else
      dashed "$id" && errors+=("${value[$id]} is dashed, but an upstream branch has it: draw it solid")
    fi
  done

  # Frames: "x:<path>/.splice" holds commit x, and its boxes are of the
  # splice at <path> in x's repository.
  local f
  local -A frame_splice=()
  for f in "${frames[@]}"; do
    k="${value[$f]%%:*}"
    p="${value[$f]#*:}" p="${p%/.splice}"
    local held=()
    for id in "${commits[@]}"; do
      inside "$id" "$f" && held+=("$id")
    done
    if [[ ${#held[@]} -ne 1 ]]; then
      errors+=("the frame \"${value[$f]}\" holds ${#held[@]} commits, not one")
      continue
    fi
    id="${held[0]}"
    if [[ "${value[$id]}" != "$k" ]]; then
      errors+=("the frame \"${value[$f]}\" holds ${value[$id]}, not $k")
      continue
    fi
    if [[ "$p" == path ]]; then
      sp="${lane_of[$f]:-$default}"
    elif [[ -n "${lane_of[$id]}" ]]; then
      sp="${lane_of[$id]}/$p"
    else
      sp="$p"
    fi
    if [[ -z "${is_splice[$sp]:-}" ]]; then
      errors+=("the frame \"${value[$f]}\" names no splice of the monorepo")
      continue
    fi
    frame_splice[$f]="$sp"
    load_truth "$sp"
  done
  for id in "${boxes[@]}"; do
    for f in "${frames[@]}"; do
      [[ -n "${frame_splice[$f]:-}" ]] && inside "$id" "$f" && splice_of[$id]="${frame_splice[$f]}"
    done
  done

  # What box term $1 of splice $2 names, or nothing.
  resolve_term() {
    local term="$1" sp="$2" k c rel
    if [[ "$term" == H ]]; then
      printf '%s\n' "${truth[H]}"
    elif [[ "$term" == [BTR] ]]; then
      printf '%s\n' "${truth[$sp|$term]}"
    elif [[ "$term" != U\(*\) ]]; then
      git rev-parse --verify --quiet "refs/splices/${truth[$sp|key]}/$term^{commit}"
    else
      k="${term#U(}" k="${k%)}"
      case "$k" in
        H) printf '%s\n' "${truth[$sp|U]}" ;;
        B) printf '%s\n' "${truth[$sp|S]}" ;;
        *)
          c="${id_of_label[$k]}"
          rel="$sp"
          [[ -z "${lane_of[$c]}" ]] || rel="${sp#"${lane_of[$c]}/"}"
          git config --blob "${commit_of[$c]}:$rel/.splice" splice.commit 2>/dev/null
          ;;
      esac
    fi
  }

  # Arrows: between commits, parent to child; from a box, to its commit.
  local s t drawn_edges=" "
  local -A box_arrows=() branch_tips=()
  for id in "${edges[@]}"; do
    s="${source[$id]}" t="${target[$id]}"
    [[ -z "$s" || "${kind[$s]:-}" != box ]] || box_arrows[$s]=$((${box_arrows[$s]:-0} + 1))
    if [[ -z "$s" || -z "$t" ]]; then
      errors+=("an arrow (${id}) isn't attached at both ends: drag its ends onto shapes")
      continue
    fi
    if [[ "${kind[$s]:-}" == box ]]; then
      if [[ "${kind[$t]:-}" != commit ]]; then
        errors+=("${value[$s]} points at something other than a commit")
        continue
      fi
      sp="${splice_of[$s]}"
      while IFS= read -r term; do
        if [[ "$term" != H && -z "$sp" ]]; then
          errors+=("$term is in no lane: draw it in the lane of its splice")
          continue
        fi
        if [[ "$term" == U\(*\) ]]; then
          k="${term#U(}" k="${k%)}"
          if [[ "$k" != [HB] && -z "${commit_of[${id_of_label[$k]:-none}]:-}" ]]; then
            errors+=("$term points at ${value[$t]}, but no commit $k is drawn")
            continue
          fi
          if [[ "${label_count[$k]:-0}" -gt 1 ]]; then
            errors+=("$term points at ${value[$t]}, but ${label_count[$k]} commits are labelled $k: label them apart")
            continue
          fi
        fi
        if [[ "$term" != H && -n "${lane_of[$t]}" && "${lane_of[$t]}" != "$sp" ]]; then
          errors+=("$term of $sp/ points at ${value[$t]}, a commit in the lane ${lane_of[$t]}/")
          continue
        fi
        named="$(resolve_term "$term" "$sp")"
        [[ "$term" == H || "$term" == [BTR] || "$term" == U\(*\) || -z "$named" ]] ||
          branch_tips[$sp]+=" $named"
        if [[ -z "$named" ]]; then
          errors+=("$term points at ${value[$t]}, but there's no $term")
        elif [[ "${commit_of[$t]:-}" != "$named" ]]; then
          label="${label_of[$named]:-}"
          [[ -n "$label" ]] || label="${named:0:7}, which isn't drawn"
          errors+=("$term points at ${value[$t]}, the code says $label")
        fi
      done < <(sed 's/ = /\n/g' <<<"${value[$s]}")
      continue
    fi
    if [[ "${kind[$t]:-}" == box ]]; then
      errors+=("an arrow from ${value[$s]} points at the box ${value[$t]}: draw it from the box to its commit")
      continue
    fi
    [[ "${kind[$s]:-}" == commit && "${kind[$t]:-}" == commit ]] || continue
    if [[ "${lane_of[$s]}" != "${lane_of[$t]}" ]]; then
      errors+=("${value[$s]} -> ${value[$t]} crosses lanes: draw a parent and its child in one lane")
      continue
    fi
    [[ -n "${commit_of[$s]:-}" && -n "${commit_of[$t]:-}" ]] || continue
    drawn_edges+="$s>$t "
    if ! git rev-parse "${commit_of[$t]}^@" | grep -qx "${commit_of[$s]}"; then
      errors+=("${value[$s]} -> ${value[$t]}: ${value[$s]} isn't a parent of ${value[$t]}")
    elif not_upstream "${commit_of[$t]}" "${splice_of[$t]}"; then
      dashed "$id" || errors+=("${value[$s]} -> ${value[$t]} is solid, but no upstream branch has ${value[$t]}: dash it")
    else
      dashed "$id" && errors+=("${value[$s]} -> ${value[$t]} is dashed, but an upstream branch has ${value[$t]}: draw it solid")
    fi
  done
  # A solid commit T lacks is on another upstream branch: its box shows
  # which.
  local b found
  for id in "${commits[@]}"; do
    sp="${splice_of[$id]}"
    [[ -n "${commit_of[$id]:-}" && -n "$sp" ]] || continue
    ! git merge-base --is-ancestor "${commit_of[$id]}" HEAD 2>/dev/null || continue
    not_upstream "${commit_of[$id]}" "$sp" && continue
    [[ -n "${truth[$sp|T]}" ]] && git merge-base --is-ancestor "${commit_of[$id]}" "${truth[$sp|T]}" && continue
    found=""
    for b in ${branch_tips[$sp]:-}; do
      git merge-base --is-ancestor "${commit_of[$id]}" "$b" && found=1
    done
    [[ -n "$found" ]] || errors+=("${value[$id]} is on an upstream branch, but not T's: draw a box for the branch, e.g. $(
      git for-each-ref --count=1 --format='%(refname:lstrip=3)' --contains "${commit_of[$id]}" "refs/splices/${truth[$sp|key]}/"
    )")
  done
  # Every box points at one commit.
  for id in "${boxes[@]}"; do
    [[ "${box_arrows[$id]:-0}" -eq 1 ]] ||
      errors+=("${value[$id]} has ${box_arrows[$id]:-0} arrows, not one: draw one from the box to its commit")
  done
  # Every parent link between two drawn commits of one lane is drawn.
  for t in "${commits[@]}"; do
    [[ -n "${commit_of[$t]:-}" ]] || continue
    for p in $(git rev-parse "${commit_of[$t]}^@"); do
      for s in "${commits[@]}"; do
        [[ "${commit_of[$s]:-}" == "$p" && "${lane_of[$s]}" == "${lane_of[$t]}" && "$drawn_edges" != *" $s>$t "* ]] &&
          errors+=("no arrow ${value[$s]} -> ${value[$t]}, though ${value[$s]} is a parent of ${value[$t]}")
      done
    done
  done

  if [[ ${#errors[@]} -gt 0 ]]; then
    printf '!!   %s\n' "${errors[@]}"
    return 1
  fi
  printf 'ok   %s: %d commits, %d arrows, %d boxes, %d frames%s\n' \
    "${drawing##*/}" "${#commits[@]}" "${#edges[@]}" "${#boxes[@]}" "${#frames[@]}" \
    "$([[ ${#lanes[@]} -eq 0 ]] || printf ', %d lanes' "${#lanes[@]}")"
}
