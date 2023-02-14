#!/bin/bash

EMACS_VERSION=${1}
EMACS=emacs
if [ "$EMACS_VERSION" ]; then
    EMACS+="-${EMACS_VERSION}"
else
    EMACS_VERSION=$(emacs -Q -batch --eval '(princ emacs-version)')
fi
#LOAD_LIBS_EL=load-core-history.el
PROVIDE_FEATURES_EL=provide-post-init-features-${EMACS_VERSION}.el
LOAD_LIBS_EL=redump-loadup-core-${EMACS_VERSION}.el
INSTALL_HOOKS_EL=install-init-hooks-${EMACS_VERSION}.el
DUMP_FILE=emacs-core-${EMACS_VERSION}.pdmp
touch dump.start
$EMACS -Q -batch \
       -l "$PROVIDE_FEATURES_EL" \
       -l "$LOAD_LIBS_EL" \
       -l "$INSTALL_HOOKS_EL" \
       --eval "(dump-emacs-portable \"${DUMP_FILE}\" nil)" \
    |& tee dump-emacs-core-${EMACS_VERSION}.log
touch dump.end
echo "Started: $(stat -c %y dump.start)"
echo "Ended: $(stat -c %y dump.end)"



       
