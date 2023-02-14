
;; Tramp autoloads require these definitions in 28.x
(eval-and-compile ;; So it's also available in tramp-loaddefs.el!
  (defvar tramp--startup-hook nil
    "Forms to be executed at the end of tramp.el.")
  (put 'tramp--startup-hook 'tramp-suppress-trace t)

  (defmacro tramp--with-startup (&rest body)
    "Schedule BODY to be executed at the end of tramp.el."
    `(add-hook 'tramp--startup-hook (lambda () ,@body))))
