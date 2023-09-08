#!/bin/bash

PKGS="${1}"
EXCLUDE="${2}"
if [ "${EXCLUDE}" ]; then
    function filter_exclude() {
	grep -Exvf "${EXCLUDE}"
    }
else
    function filter_exclude() {
	cat
    }
fi

cat <<EOF
(defvar require-verbose-n 0)
(defmacro require-verbose (lib)
  \`(progn
     (incf require-verbose-n)
     (princ \`(,',require-verbose-n (require ,',lib)))
     (terpri)
     (let ((debug-on-signal nil))
       (condition-case err
       	   (unless (featurep ,lib)
	     (load (symbol-name ,lib)))
	 ((debug error)
	  (princ \`(error ,err)))))))

EOF

find "${PKGS}" -maxdepth 2 -name '*.el' | grep -Eve '-(autoloads|pkg|theme)\.el$' |
    sed -E 's@^.*/([^/]+)\.el@\1@' |
    grep -Eve '^\.' |
    filter_exclude |
    sed -E 's@^(.*)$@(require-verbose '"'"'\1)@'
