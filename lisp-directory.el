(if (boundp (quote lisp-directory))
    (princ (format "%s\n" lisp-directory))
  (let* ((base-dir (expand-file-name (file-name-concat data-directory "..")))
	 (lisp-dir (expand-file-name (file-name-concat base-dir "lisp"))))
    (princ (format "%s\n" lisp-dir))))

