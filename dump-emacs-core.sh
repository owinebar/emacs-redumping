#!/bin/bash

EMACS_VERSION=${1}
EMACS=emacs
if [ "$EMACS_VERSION" ]; then
    EMACS+="-${EMACS_VERSION}"
else
    EMACS_VERSION=$(emacs -Q -batch --eval '(princ emacs-version)')
fi
LOAD_LIBS_EL=redump-loadup-core-${EMACS_VERSION}.el
DUMP_FILE=emacs-core-${EMACS_VERSION}.pdmp
touch dump.start
$EMACS -Q -batch \
       -l "$LOAD_LIBS_EL" \
       --eval "(dump-emacs-portable \"${DUMP_FILE}\" nil)" \
    |& tee dump-emacs-core-${EMACS_VERSION}.log
touch dump.end
echo "Started: $(stat -c %y dump.start)"
echo "Ended: $(stat -c %y dump.end)"



       
