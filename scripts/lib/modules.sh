# shellcheck shell=bash
# Module handling shared by init.sh and sync-template.sh. Source it; do not run it.

# Keeps or removes the parts of files marked for a module.
#   Block:  a line holding only a comment with ">>> name", up to one with "<<< name"
#           (# for YAML and env files, // for C#, <!-- --> for Markdown).
#   Inline: <!-- >>> name -->text<!-- <<< name --> within one Markdown line.
# Kept: only the markers go. Removed: markers and everything between them.
apply_module() { # name keep(true|false) files...
  local name=$1 keep=$2
  shift 2
  [ $# -gt 0 ] || return 0
  MODULE=$name KEEP=$keep perl -0777 -pi -e '
    my $n = quotemeta $ENV{MODULE};
    my $c = qr{(?:\#|//|<!--)};
    if ($ENV{KEEP} eq "true") {
      s/^[ \t]*$c[ \t]*(?:>>>|<<<) $n\b[^\n]*\n//gm;
      s/<!-- (?:>>>|<<<) $n -->//g;
    } else {
      s/<!-- >>> $n -->[^\n]*?<!-- <<< $n -->//g;
      s/^[ \t]*$c[ \t]*>>> $n\b[^\n]*\n.*?^[ \t]*$c[ \t]*<<< $n\b[^\n]*\n//gms;
    }
  ' "$@"
}

# Every module the template knows, in an order where nested blocks are handled safely.
ALL_MODULES="messaging event-sourcing cqrs dapr"

# Applies a module selection (space-separated names) to files: selected modules are
# kept, all others removed.
apply_modules() { # "selected modules" files...
  local selected=" $1 " module keep
  shift
  for module in $ALL_MODULES; do
    keep=false
    case $selected in *" $module "*) keep=true ;; esac
    apply_module "$module" "$keep" "$@"
  done
}

# Writes .template.json: where the project came from, so sync-template.sh can update it.
write_template_lock() { # file repository ref commit "modules"
  REPOSITORY=$2 REF=$3 COMMIT=$4 MODULES=$5 perl -MJSON::PP -e '
    my @modules = grep { length } split / /, $ENV{MODULES};
    print JSON::PP->new->pretty->canonical->indent_length(2)->encode({
      repository => $ENV{REPOSITORY},
      ref        => $ENV{REF},
      commit     => $ENV{COMMIT},
      modules    => \@modules,
    });
  ' > "$1"
}

# Prints all files outside scripts/ that still contain module markers. README.md is
# skipped: the template's README documents the markers.
marked_files() {
  grep -rlE '(>>>|<<<) [a-z]' . \
    --exclude-dir=.git --exclude-dir=scripts --exclude-dir=node_modules \
    --exclude-dir=bin --exclude-dir=obj --exclude=README.md || true
}

# Prints which of the given files still contain module markers.
marked_files_in() { # files...
  grep -lE '(>>>|<<<) [a-z]' "$@" 2>/dev/null || true
}
