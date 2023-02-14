#!/bin/bash

EMACS="${EMACS:-emacs}"
LISP_DIR="$($EMACS -Q -batch -l lisp-directory.el)"
LISP_DIR="${LISP_DIR%/}"
PLATFORM="$(EMACS -Q -batch -l platform.el)"
EMACS_VERSION="$($EMACS -Q --eval '(princ emacs-version)')"
EMACS_MAJOR="$($EMACS -Q --eval '(princ emacs-major-version)')"
REDUMP_EL="${REDUMP_EL:-redump-loadup-core-${EMACS_VERSION}.el}"

tmpdir="$(mktemp -d)"
cleanup () {
    rm -Rf "$tmpdir"
}
trap cleanup EXIT

startdir="$(pwd)"
data_dir="$(realpath "data/$EMACS_MAJOR")"
platform_dir="$(realpath "$data_dir/$PLATFORM")"
baseline_libs="$(realpath "$data_dir/baseline-libs")"
load_at_init="$(realpath "$data_dir/load-at-init")"
dump_fails="$(realpath "$data_dir/dump-failure")"
incompatible="$(realpath "$platform_dir/incompatible-libs")"
exec_preload="$(realpath "$data_dir/exec_preload.el")"
exclusions=""
specified=""
user_load_at_init=""

while (( $# > 0 )); do
    case "${1}" in
	-x | --exclude)
	    if (( $# < 2 )); then
		echo "Option ${1} requires filename argument" >&2
		exit 1
	    fi
	    exclusions="${2}"
	    if [ \! -e "$exclusions" ]; then
		echo "Argument $exclusions must be a file containing the list of emacs libraries to exclude from the dump"
	    fi
	    shift 2
	    ;;
	-l | --load-at-init)
	    if (( $# < 2 )); then
		echo "Option ${1} requires filename argument" >&2
		exit 1
	    fi
	    user_load_at_init="${2}"
	    if [ \! -e "$user_load_at_init" ]; then
		echo "Argument $user_load_at_init must be a file containing the list of emacs libraries to exclude from the dump but load at initialization"
	    fi
	    shift 2
	    ;;
	*)
	    break
	    ;;
    esac
done

if (( $# > 0 )); then
    specified="${1}"
    if [ \! -e "$specified" ]; then
	echo "Argument $specified must be a file containing the list of emacs libraries used to generate the redump"
    fi
fi


if [ \! -d "$data_dir" ]; then
    echo "Error - major version $EMACS_MAJOR not supported" >&2
    exit 1  
fi
if [ \! -d "$platform_dir" ]; then
    echo "Warning - no platform-specific files for $PLATFORM" >&2
    incompatible="$tmpdir/incompatible-libs"
    : >"$incompatible"
fi

if [ -z "$exclusions" ] ; then
    exclusions="$tmpdir/exclusions"
    : >"$exclusions"
fi
${EMACS} -batch -Q -l print-load-history.el |
    sed -E -e "s#^${LISP_DIR}/(.*)\\.elc?\$#\\1#" \
	>"$baseline_libs"

provide_features="$(mktemp -p "$tmpdir")"

sed -E -e "s/^(.*)\$/(provide '\\1)/" \
    <"$load_at_init" \
    >"$provide_features"

if [ \! -e "$dump_fails" ]; then
    dump_fails="$tmpdir/dump-failures"
    : >"$dump_fails"
fi
all_load_at_init="$load_at_init"
nodelay_load_at_init="$tmpdir/no-delay-load-at-init"
delay_load_at_init="$tmpdir/delay-load-at-init"
: >"$nodelay_load_at_init"
: >"$delay_load_at_init"
if [ -e "$dump_fails" ]; then
    cat "$dump_fails" | while read lib; do
	grep -qF "$lib" "$load_at_init" "$exclusions" && continue
	echo "$lib" >>"$nodelay_load_at_init"
    done
fi
if [ -z "$user_load_at_init" ]; then
    user_load_at_init="$tmpdir/user-load-at-init"
    : >"$user_load_at_init"
fi
sed -E -e "s/^(.*)\$/(provide '\\1)/" \
    <"$user_load_at_init" \
    >>"$provide_features"
all_load_at_init="$(mktemp -p "$tmpdir")"
cat "$load_at_init" "$user_load_at_init" "dump_fails" | sort -u >"$all_load_at_init"
cat "$user_load_at_init" | while read lib; do
    grep -qF "$lib" "$load_at_init" "$exclusions" && continue
    echo "$lib" >>"$nodelay_load_at_init"
done
cat "$load_at_init" | while read lib; do
    [ "$lib" = "dbus" ] && continue
    echo "$lib" >>"$delay_load_at_init"
done

elc_sed='t clear; : clear; s#^.*/cedet/(.*)\.elc$#\1# t; s#^.*/([^/]+)\.elc$#\1#'
is_undumpable() {
    # These are undumpable regardless of major version or platform
    grep -Eq '(^\./(term|obsolete))|(viper)' <<<"$1"
}

is_excluded() {
    grep -qF "$y" \
	 "$baseline_libs" \
	 "$incompatible" \
	 "$all_load_at_init" \
	 "$exclusions"
}

if [ -z "$specified" ]; then
    specified="$tmpdir/dumpable-core-libs"
    (
	cd "$LISP_DIR"
	find -name '*.elc' |
	    ( while read fn; do
		  y="$(echo $fn | sed -E -e "$elc_sed")";
		  if ! ( is_excluded "$y" ||
			     is_undumpable "$fn"
		       ); then
		      echo "$fn" | sed -E -e 's#^\./##'
		  fi
	      done
	    )  >"$specified"
    )
fi
load_specified="$tmpdir/load-specified.el"
sed -E -e 's/^(.*)$/(load "\1")/' >"$load_specified"

clean_load_history="$tmpdir/clean-load-history.sed"
cat >"$clean_load_history" <<EOF
s#^${LISP_DIR}/(.*)\\.elc?\$#\\1#
/${load_specified}/ d
EOF

: >"${REDUMP_EL}"
if [ -e "$exec_preload" ]; then
    cat "$exec_preload" >>"${REDUMP_EL}"
    echo "" >"${REDUMP_EL}"
fi    
cat "$provide_features" >>"${REDUMP_EL}"
echo "" >"${REDUMP_EL}"
${EMACS} -batch -Q \
	   -l "$load_specified" \
	   -l print-load-history.el |
    sed -E -f "$clean_load_history" |
    (while read lib; do
	 if ! is_excluded "$lib"; then
	     echo "$lib";
	 fi;
     done) |
    sed -E -e 's/^(.*)$/(load "\1")/' >>"${REDUMP_EL}"

## Shell script mode does not deal well with lisp quotes even embedded in strings
clean_feature_text() {
    cat "$1" | while read lib; do
	echo "${2}(setq features (delete (quote $lib) features))"
    done
}
require_feature_text() {
    cat "$1" | while read lib; do
	echo "${2}(require (quote $lib))"
    done
}
cat >>"${REDUMP_EL}" <<EOF
(add-hook
 (quote before-init-hook)
 (lambda ()
   (tool-bar-mode)
   (menu-bar-mode)
   (global-font-lock-mode)
   (setq features (delete (quote dbus) features))
$(clean_feature_text "$nodelay_load_at_init" "    ")
   (require (quote dbus))))

(add-hook
 (quote after-init-hook)
 (lambda ()
$(clean_feature_text "$delay_load_at_init" "    ")
$(require_feature_text "$delay_load_at_init" "    ")
$(require_feature_text "$nodelay_load_at_init" "    ")
   ))

EOF

