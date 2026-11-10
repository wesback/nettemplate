#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Updates this project from the template it was created from.
#
# Usage: scripts/sync-template.sh [--modules "a b"] [ref]
#   ref        branch, tag or commit of the template (default: the ref in .template.json)
#   --modules  only for projects without .template.json: the modules init.sh was run
#              with, space-separated (dapr messaging cqrs event-sourcing), "" for none
#
# What it does:
#   - replaces the template-owned files listed in template-files.txt, with this
#     project's modules applied, keeping the project-specific rules in AGENTS.md
#   - deletes owned files the template no longer has
#   - writes the template's changes to project-owned (seeded) files to
#     .git/template-upstream.patch for you to review; it never edits them
#   - records the template commit in .template.json
# It never commits. Review with git diff, run the checks, then commit on a branch.
#
# Needs: bash, git, perl.

set -euo pipefail

die()  { printf '\nerror: %s\n' "$*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }

# This script is template-owned, so a sync may replace it while it runs. Run from a copy.
if [ -z "${SYNC_TEMPLATE_COPY:-}" ]; then
  root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
  copy=$(mktemp)
  cp "${BASH_SOURCE[0]}" "$copy"
  SYNC_TEMPLATE_COPY=$copy SYNC_TEMPLATE_ROOT=$root exec bash "$copy" "$@"
fi
root=$SYNC_TEMPLATE_ROOT
work=$(mktemp -d)
trap 'rm -rf "$work" "$SYNC_TEMPLATE_COPY"' EXIT

usage() {
  awk 'NR > 1 && /^# shellcheck/ { next } NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$SYNC_TEMPLATE_COPY"
  exit 2
}

modules_arg=""
modules_given=false
ref_arg=""
while [ $# -gt 0 ]; do
  case $1 in
    --modules) [ $# -ge 2 ] || die "--modules needs a value"; modules_arg=$2; modules_given=true; shift ;;
    -h|--help) usage ;;
    -*) die "unknown option: $1" ;;
    *) [ -z "$ref_arg" ] || die "only one ref allowed"; ref_arg=$1 ;;
  esac
  shift
done

cd "$root"
lock=.template.json
marker='<!-- project-rules: keep below -->'

# ---------------------------------------------------------------- preflight
[ ! -f scripts/init.sh ] || die "this is the template or an uninitialised copy; run scripts/init.sh first"
git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository"
if ! git diff --quiet || ! git diff --cached --quiet; then
  die "commit or stash your changes first, so the sync shows up as its own diff"
fi

lock_value() { # key -> value (arrays joined by spaces)
  perl -MJSON::PP -e '
    local $/; my $j = decode_json(<STDIN>); my $v = $j->{$ARGV[0]};
    print ref $v eq "ARRAY" ? join(" ", @$v) : ($v // "");
  ' "$1" < "$lock"
}

if [ -f "$lock" ]; then
  $modules_given && die "--modules is only for projects without $lock; edit $lock instead"
  repository=$(lock_value repository)
  ref=${ref_arg:-$(lock_value ref)}
  old_commit=$(lock_value commit)
  modules=$(lock_value modules)
else
  $modules_given || die "$lock is missing; pass --modules with the modules init.sh used (\"\" for none)"
  repository=${TEMPLATE_REPOSITORY:-wesback/nettemplate}
  ref=${ref_arg:-main}
  old_commit=""
  modules=$modules_arg
fi
repository=${repository:-wesback/nettemplate}
ref=${ref:-main}
known_modules="messaging event-sourcing cqrs dapr"
for module in $modules; do
  case " $known_modules " in
    *" $module "*) ;;
    *) die "unknown module in $lock: $module" ;;
  esac
done

case $repository in
  *://*|/*|./*|../*) url=$repository ;;   # URL or local path (template-ci uses a path)
  *) url=https://github.com/$repository.git ;;
esac

# ---------------------------------------------------------------- fetch
step "Fetching $repository at $ref"
git -C "$work" init -q
git -C "$work" fetch -q --depth 1 "$url" "$ref" || die "cannot fetch '$ref' from $url"
new_commit=$(git -C "$work" rev-parse FETCH_HEAD)
git -C "$work" checkout -q "$new_commit"
echo "Template commit: ${old_commit:-unknown} -> $new_commit"
echo "Modules: ${modules:-none}"

have_old=false
if [ -n "$old_commit" ] && [ "$old_commit" != "$new_commit" ]; then
  if git -C "$work" fetch -q --depth 1 "$url" "$old_commit" 2>/dev/null; then
    have_old=true
  else
    echo "Previous template commit $old_commit is not available; skipping the seeded-files patch."
  fi
fi

[ -f "$work/template-files.txt" ] || die "the template at $ref has no template-files.txt"
# shellcheck source=lib/modules.sh
. "$work/scripts/lib/modules.sh"

manifest_section() { # file section
  awk -v s="[$2]" '/^\[/ { on = ($0 == s); next } on && NF && $1 !~ /^#/ { print $1 }' "$1"
}
new_owned=$(manifest_section "$work/template-files.txt" owned)
old_owned=""
[ -f template-files.txt ] && old_owned=$(manifest_section template-files.txt owned)

# ---------------------------------------------------------------- owned files
step "Updating template-owned files"
# Modules apply to owned files outside scripts/, as in init.sh: the scripts describe
# the marker syntax in their comments and must not be rewritten.
owned_paths=()
for file in $new_owned; do
  [ -f "$work/$file" ] || die "the template lists $file as owned but does not contain it"
  case $file in scripts/*) ;; *) owned_paths+=("$work/$file") ;; esac
done
apply_modules "$modules" "${owned_paths[@]}"
leftover=$(marked_files_in "${owned_paths[@]}")
[ -z "$leftover" ] || die "module markers left after applying modules: $leftover"

for file in $new_owned; do
  mkdir -p "$(dirname "$file")"
  if [ "$file" = AGENTS.md ]; then
    grep -qF -- "$marker" "$work/AGENTS.md" || die "the template's AGENTS.md has no project-rules marker"
    [ -f AGENTS.md ] || die "AGENTS.md is missing"
    grep -qF -- "$marker" AGENTS.md \
      || die "AGENTS.md has no '$marker' line. Add it above your project-specific rules (or at the end), commit, and run again."
    {
      awk -v m="$marker" '{ print } index($0, m) { exit }' "$work/AGENTS.md"
      awk -v m="$marker" 'found { print } index($0, m) { found = 1 }' AGENTS.md
    } > "$work/AGENTS.merged"
    cat "$work/AGENTS.merged" > AGENTS.md
  else
    cp "$work/$file" "$file"
  fi
  if [ -x "$work/$file" ]; then chmod +x "$file"; fi
done

for file in $old_owned; do
  case " $(echo "$new_owned" | tr '\n' ' ') " in
    *" $file "*) ;;
    *) if [ -f "$file" ]; then rm -f "$file"; echo "Removed $file (no longer in the template)"; fi ;;
  esac
done

# ---------------------------------------------------------------- seeded files
patch="$(git rev-parse --absolute-git-dir)/template-upstream.patch"
rm -f "$patch"
if $have_old; then
  seeded=$(manifest_section "$work/template-files.txt" seeded)
  # shellcheck disable=SC2086
  git -C "$work" diff "$old_commit" "$new_commit" -- $seeded > "$patch"
  if [ -s "$patch" ]; then
    seeded_note="The template changed project-owned files. Review $patch and carry over what you want by hand.
  It shows the template's versions: module markers (>>> / <<<) and placeholders (MyService) are still in it,
  and scripts/templates/* map to src/<Name>.Api/ and web/ in this project."
  else
    rm -f "$patch"
    seeded_note="No changes to project-owned files in the template."
  fi
elif [ -z "$old_commit" ]; then
  seeded_note="No previous template commit was recorded, so changes to project-owned files are not listed."
else
  seeded_note="No changes to project-owned files in the template."
fi

# ---------------------------------------------------------------- lock
write_template_lock "$lock" "$repository" "$ref" "$new_commit" "$modules"

step "Done"
git status --short
cat <<EOF

$seeded_note

Next: review with 'git diff', run the checks in AGENTS.md (Commands), then commit on a branch:
  git switch -c chore/template-sync && git commit -am "chore: sync template to ${new_commit:0:7}"
EOF
