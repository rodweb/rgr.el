(require 'compile)
(require 'projectile)
(require 'tree-sitter)

(defun etest--npm-has-package (package)
  "Returns PACKAGE version if found, nil otherwise."
  (let* ((json-hash (with-temp-buffer
                      (insert-file-contents "package.json")
                      (json-parse-buffer)))
         (dependencies (gethash "dependencies" json-hash))
         (devDependencies (gethash "devDependencies" json-hash)))
    (or (and dependencies (gethash package dependencies))
        (and devDependencies (gethash package devDependencies)))))

(defun etest--guess-project-type ()
  (projectile-project-type))

(defun etest--mocha-check ()
  (let ((default-directory (projectile-project-root)))
    (etest--npm-has-package "mocha")))

(defun etest--jest-check ()
  (let ((default-directory (projectile-project-root)))
    (etest--npm-has-package "jest")))

(defvar etest--test-runners
  '((npm . (mocha jest)))
  "Test runners.")

(defun etest--guess-project-runner ()
  (let* ((project-type (projectile-project-type))
         (runners (alist-get project-type etest--test-runners)))
    (seq-find (lambda (runner)
                (etest--call-if-bound runner "check"))
              runners)))

(defun etest--call-if-bound (runner fn &optional args)
  (let ((fn (intern (concat "etest--" (symbol-name runner) "-" fn))))
    (if (fboundp fn)
        (apply fn args)
      (error "%s not supported for runner %s" fn runner))))

(defun etest--remove-nil (items)
  (seq-remove #'not items))

(defcustom etest-mocha-program "node_modules/.bin/mocha"
  "Mocha's program path.")

(defcustom etest-mocha-reporter nil
  "Mocha's reporter."
  :type 'string)

(defun etest--current-filename ()
  (buffer-file-name))

(defun etest--mocha-command-args (&rest args)
  (etest--remove-nil
   (list etest-mocha-program
         (and etest-mocha-reporter
              (format "--reporter=%s" etest-mocha-reporter))
         (and (or (plist-get args :file) (plist-get args :dwim))
              (etest--current-filename))
         (and (plist-get args :dwim)
              (if-let ((name (etest--mocha-get-test-name)))
                  (format "--fgrep='%s'" name))))))

(defcustom etest-mocha-identifiers '("describe" "it")
  "Mocha's test identifiers."
  :type '(repeat string))

(defun etest--mocha-walk-up (node)
  (if-let ((identifier (and node (tsc-get-nth-named-child node 0))))
      (if (and (eq (tsc-node-type identifier) 'identifier)
               (member (tsc-node-text identifier) etest-mocha-identifiers))
          (tsc-get-nth-named-child (tsc-get-nth-named-child node 1) 0)
        (etest--walk-up (tsc-get-parent node)))))

(defun etest--mocha-get-test-name ()
  (if-let* ((node (tree-sitter-node-at-pos 'call_expression))
         (node (etest--mocha-walk-up node)))
    (substring (tsc-node-text node) 1 -1)))

(defun etest--run (&rest args)
  (let* ((default-directory (projectile-project-root))
         (runner (etest--guess-project-runner))
         (command (etest--call-if-bound runner "command-args" args)))
    (compile (mapconcat #'identity command " "))))

(defun etest-project ()
  (interactive)
  (etest--run))

(defun etest-file ()
  (interactive)
  (etest--run :file t))

(defun etest-dwim ()
  (interactive)
  (etest--run :dwim t))

(provide 'etest)
