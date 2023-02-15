#!/bin/bash

EMACS="${EMACS:-emacs}"
EMACS_VERSION="$($EMACS -Q -batch --eval '(princ emacs-version)')"
EMACS_MAJOR="$($EMACS -Q -batch --eval '(princ emacs-major-version)')"
REDUMP_EL="${REDUMP_EL:-redump-loadup-core-${EMACS_VERSION}.el}"
PROGNAME="$(realpath "$0")"
if [ -L "$PROGNAME" ]; then
    PROGNAME="$(realpath "$(readlink "$PROGNAME")")"
fi
SRC_DIR="$(dirname "$(realpath "$PROGNAME")")"
DATA_DIR="$SRC_DIR/data"
DELETE_TMP_DIR=1
#tmpdir="$(mktemp -d)"
#tmpdir="$(realpath tmp)"
#output_dir="$(pwd)"
cleanup() {
    if (( $DELETE_TMP_DIR )); then
	rm -Rf "$tmpdir"
    fi
}

on_error() {
    local i=0
    local estr="$(caller $i)"
    echo "Error"
    while [ "$estr" ]; do
	echo "$estr"
	(( ++i , 1 ))
	estr="$(caller $i)"
    done
}
trap cleanup EXIT
trap on_error ERR

startdir="$(pwd)"
vsn_dir="$(realpath "$DATA_DIR/$EMACS_MAJOR")"
platform_dir="$(realpath "$vsn_dir/$PLATFORM")"
load_at_init="$(realpath "$vsn_dir/load-at-init")"
dump_fails="$(realpath "$vsn_dir/dump-failure")"
incompatible="$(realpath "$platform_dir/incompatible-libs")"
exec_preload="$(realpath "$vsn_dir/exec_preload.el")"
exclusions=""
specified=""
user_load_at_init=""

while (( $# > 0 )); do
    case "${1}" in
	-i | --intermediate-storage)
	    if (( $# < 2 )); then
		echo "Option ${1} requires directory name argument" >&2
		exit 1
	    fi
	    DELETE_TMP_DIR=0
	    tmpdir="${2}"
	    if [ \! -d "$tmpdir" ]; then
		mkdir -p "$tmpdir"
	    fi
	    if [ \! -d "$tmpdir" ]; then
		echo "Directory $tmpdir for intermediate files does not exist and cannot be created" >&2
		exit 1
	    fi
	    tmpdir="$(realpath $tmpdir)"
	    shift 2
	    ;;
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
	-o | --output-file)
	    if (( $# < 2 )); then
		echo "Option ${1} requires filename argument" >&2
		exit 1
	    fi
	    REDUMP_EL="${2}"
	    if [ \! -e "$user_load_at_init" ]; then
		echo "Argument $user_load_at_init must be a file containing the list of emacs libraries to exclude from the dump but load at initialization"
	    fi
	    shift 2
	    ;;
	-p | --output-path)
	    if (( $# < 2 )); then
		echo "Option ${1} requires directory name argument" >&2
		exit 1
	    fi
	    output_dir="${2}"
	    if [ \! -d "$output_dir" ]; then
		mkdir -p "$output_dir"
	    fi
	    if [ \! -d "$output_dir" ]; then
		echo "Directory $output_dir for output file does not exist and cannot be created" >&2
		exit 1
	    fi
	    output_dir="$(realpath $output_dir)"
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

if (( $DELETE_TMP_DIR )); then
    tmpdir="$(mktemp -d)"
fi

# This seems like the most reliable way to ensure
# execution of this script is not required to happen in
# the source directory
lisp_dir_el="$(realpath "$tmpdir/lisp-directory.el")"
platform_el="$(realpath "$tmpdir/platform.el")"
print_lh_el="$(realpath "$tmpdir/print-load-history.el")"
cat >"$lisp_dir_el" <<EOF
(if (boundp (quote lisp-directory))
    (princ (format "%s\n" lisp-directory))
  (let* ((base-dir (expand-file-name (file-name-concat data-directory "..")))
	 (lisp-dir (expand-file-name (file-name-concat base-dir "lisp"))))
    (princ (format "%s\n" lisp-dir))))
EOF
cat >"$platform_el" <<EOF
;; Reflects the extent of the author's knowledge
(if (string= system-type "gnu/linux")
    (princ "linux")
  (princ "unknown"))

EOF
cat >"$print_lh_el" <<EOF
(let ((ls (reverse (mapcar #'car load-history))))
  (while ls
    (princ (car ls))
    (terpri)
    (setq ls (cdr ls))))
EOF
LISP_DIR="$($EMACS -Q -batch -l "$lisp_dir_el")"
PLATFORM="$($EMACS -Q -batch -l "$platform_el")"
LISP_DIR="${LISP_DIR%/}"

if [ \! -d "$vsn_dir" ]; then
    echo "Error - major version $EMACS_MAJOR not supported" >&2
    exit 1  
fi
if [ \! -d "$platform_dir" ]; then
    echo "Warning - no platform-specific files for $PLATFORM" >&2
fi
if [ \! -e "$incompatible" ]; then
    incompatible="$tmpdir/incompatible-libs"
    : >"$incompatible"
fi

if [ -z "$exclusions" ] ; then
    exclusions="$tmpdir/exclusions"
    : >"$exclusions"
fi
baseline_libs="$tmpdir/baseline-libs"

${EMACS} -batch -Q -l "$print_lh_el" |
    sed -E -e "s#^${LISP_DIR}/(.*)\\.elc?\$#\\1#" \
	>"$baseline_libs"

provide_features="$tmpdir/provide-features.el"

sed -E -e "s/^(.*)\$/(provide '\\1)/" \
    <"$load_at_init" \
    >"$provide_features"

if [ \! -e "$dump_fails" ]; then
    dump_fails="$tmpdir/dump-failures"
    : >"$dump_fails"
fi
##all_load_at_init="$load_at_init"
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
all_load_at_init="$tmpdir/all-load-at-init"
cat "$load_at_init" "$user_load_at_init" "$dump_fails" | sort -u >"$all_load_at_init"
cat "$user_load_at_init" | while read lib; do
    grep -qF "$lib" "$load_at_init" "$exclusions" && continue
    echo "$lib" >>"$nodelay_load_at_init"
done
cat "$load_at_init" | while read lib; do
    [ "$lib" = "dbus" ] && continue
    echo "$lib" >>"$delay_load_at_init"
done

elc_sed='t clear; : clear; s#^.*/cedet/(.*)\.elc$#\1#; t; s#^.*/([^/]+)\.elc$#\1#'
lib_sed='t clear; : clear; s#^.*/cedet/(.*)$#\1#; t; s#^.*/([^/]+)$#\1#'
is_undumpable() {
    # These are undumpable regardless of major version or platform
    grep -Eq '(^\./(term|obsolete|leim|international))|(viper)' <<<"$1"
}

is_excluded() {
    grep -qF "$1" \
	 "$baseline_libs" \
	 "$incompatible" \
	 "$all_load_at_init" \
	 "$exclusions"
}
is_loaded_at_init() {
    grep -qF "$1" \
	 "$baseline_libs" \
	 "$all_load_at_init" 
}

if [ -z "$specified" ]; then
    specified="$(realpath $tmpdir/dumpable-core-libs)"
    (
	cd "$LISP_DIR"
	(( N = $(find -name '*.elc' | wc -l) ))
	(( i = 0 ))
	printf "\nIdentifying dumpable core libs [%6d/%6d]" $i $N >&2
	find -name '*.elc' |
	    ( while read fn; do
		  (( ++i , 1 ))
		  printf "\rIdentifying dumpable core libs [%6d/%6d]" $i $N >&2
		  y="$(echo $fn | sed -E -e "$elc_sed")";
		  if ! ( is_excluded "$y" ||
			     is_undumpable "$fn"
		       ); then
		      echo "$fn" | sed -E -e 's#^\./##'
		  fi
	      done
	    )  >"$specified"
	printf "\n" >&2
    )
fi
load_specified="$tmpdir/load-specified.el"
rewrite_load_sed="$tmpdir/rewrite-library-loads.el"
cat >"$rewrite_load_sed" <<EOF
s@^(.*)\$@(load "\\1" nil t) (setq i (+ i 1)) (princ (format "\\rLoading %5d/%5d" i N) #'external-debugging-output)@
EOF
N=$(wc -l <"$specified")
N=${N:-0}
echo "(setq N $N) (setq i 0)" >"$load_specified"
echo '(princ (format "\rLoading %5d/%5d" i N) (function external-debugging-output))' >>"$load_specified"
sed -E -f "$rewrite_load_sed" <"$specified" >>"$load_specified"
printf "\n" >&2

clean_load_history="$tmpdir/clean-load-history.sed"
cat >"$clean_load_history" <<EOF
s#^${LISP_DIR}/(.*)\\.elc?\$#\\1#
\@${load_specified}@ d
EOF
cleaned_load_history="$tmpdir/cleaned-load-history"
load_files_el="$tmpdir/ordered_loads.el"
echo "Loading specified file set to obtain load order of all required files"
${EMACS} -batch -Q \
	   -l "$load_specified" \
	   -l "$print_lh_el" |
    sed -E -f "$clean_load_history"  >"$cleaned_load_history"

(( N = $(wc -l <"$cleaned_load_history"),
   i = 0 ,
   1
 ))
printf "\nProcessing load history [%6d/%6d]" $i $N >&2
: >"${load_files_el}"

cat "$cleaned_load_history" | 
    (while read lib; do
	 (( ++i , 1 ))
	 printf "\rProcessing load history [%6d/%6d]" $i $N >&2
	 y="$(echo $lib | sed -E -e "$lib_sed")";
	 # echo "$lib => $y" >&2
	 if ! is_loaded_at_init "$y"; then
	     echo "$lib"
	 fi
     done) | \
    sed -E -e 's@^(.*)$@(load "\1" nil t)@' >>"${load_files_el}"
printf "\n" >&2


if [ "$output_dir" ] ; then
    if [ "$(basename "$REDUMP_EL")" != "$REDUMP_EL" ]; then
	echo "Warning - overriding path in specified output file with specified output path: $output_dir/$(basename "$REDUMP_EL")" >&2
    fi
    REDUMP_EL="$(realpath "$output_dir")/$(basename "$REDUMP_EL")"
fi

: >"${REDUMP_EL}"
if [ -e "$exec_preload" ]; then
    cat "$exec_preload" >>"${REDUMP_EL}"
    echo "" >>"${REDUMP_EL}"
fi    
cat "$provide_features" >>"${REDUMP_EL}"
echo "" >>"${REDUMP_EL}"
cat "$load_files_el" >>"$REDUMP_EL"

## Shell script mode does not deal well with lisp quotes even embedded in strings
clean_feature_text() {
    cat "$1" | while read lib; do
	printf "%s(setq features (delete (quote %s) features))\n" "${2}" "$lib"
    done
}

require_feature_text() {
    cat "$1" | while read lib; do
	printf "%s(require (quote %s))\n" "${2}" "$lib"
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
$(clean_feature_text "$nodelay_load_at_init" "   ")
   (require (quote dbus))))

(add-hook
 (quote after-init-hook)
 (lambda ()
$(clean_feature_text "$delay_load_at_init" "   ")
$(require_feature_text "$delay_load_at_init" "   ")
$(require_feature_text "$nodelay_load_at_init" "   ")
   ))

EOF

