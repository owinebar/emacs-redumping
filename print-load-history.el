
(let ((ls (reverse (mapcar #'car load-history))))
  (while ls
    (princ (car ls))
    (terpri)
    (setq ls (cdr ls))))

