;;; separedit-test-helper.el --- Helpers of testing -*- lexical-binding: t; -*-

;; Copyright (C) 2019 Gong Qijian <gongqijian@gmail.com>

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Code:

(defvar test-expr nil
  "Holds a test expression to evaluate with `test-eval'.")

(defvar test-result nil
  "Holds the eval result of `test-expr' by `test-eval'.")

(defun test-eval ()
  "Evaluate `test-expr'."
  (interactive)
  (setq test-result (eval test-expr)))

(global-set-key (kbd "C-c C-c e") 'test-eval)

(defun test-with (expr keys)
  "Evaluate EXPR followed by KEYS."
  (let ((test-expr expr))
    (execute-kbd-macro
     (vconcat (kbd (if expr "C-c C-c e" ""))
              (kbd keys)))
    test-result))

;;; polyfil

(unless (fboundp 'indent-region-line-by-line)
  (defun indent-region-line-by-line (beg end)
    (save-excursion
      (goto-char beg)
      (catch 'break
        (while t
          (sh-indent-line)
          (when (< 0 (forward-line 1))
            (throw 'break nil)))))))

(unless (fboundp 'font-lock-ensure)
  (defun font-lock-ensure (&optional beg end)
    (font-lock-set-defaults)
    (funcall 'jit-lock-fontify-now
             (or beg (point-min)) (or end (point-max)))))

(defconst python-rx-constituents@26.1
  (list
   `(block-start          . ,(rx symbol-start
                                 (or "def" "class" "if" "elif" "else" "try"
                                     "except" "finally" "for" "while" "with")
                                 symbol-end))
   `(decorator            . ,(rx line-start (* space) ?@ (any letter ?_)
                                 (* (any word ?_))))
   `(defun                . ,(rx symbol-start (or "def" "class") symbol-end))
   `(symbol-name          . ,(rx (any letter ?_) (* (any word ?_))))
   `(open-paren           . ,(rx (or "{" "[" "(")))
   `(close-paren          . ,(rx (or "}" "]" ")")))
   `(simple-operator      . ,(rx (any ?+ ?- ?/ ?& ?^ ?~ ?| ?* ?< ?> ?= ?%)))
   `(not-simple-operator  . ,(rx
                              (not
                               (any ?+ ?- ?/ ?& ?^ ?~ ?| ?* ?< ?> ?= ?%))))
   `(operator             . ,(rx (or "+" "-" "/" "&" "^" "~" "|" "*" "<" ">"
                                     "=" "%" "**" "//" "<<" ">>" "<=" "!="
                                     "==" ">=" "is" "not")))
   `(assignment-operator  . ,(rx (or "=" "+=" "-=" "*=" "/=" "//=" "%=" "**="
                                     ">>=" "<<=" "&=" "^=" "|="))))
  "Additional Python specific sexps for `python-rx'")

(defun python-info-docstring-p@26.1 (&optional syntax-ppss)
  "Return non-nil if point is in a docstring.
When optional argument SYNTAX-PPSS is given, use that instead of
point's current `syntax-ppss'."
  ;;; https://www.python.org/dev/peps/pep-0257/#what-is-a-docstring
  (save-excursion
    (when (and syntax-ppss (python-syntax-context 'string syntax-ppss))
      (goto-char (nth 8 syntax-ppss)))
    (python-nav-beginning-of-statement)
    (let ((counter 1)
          (indentation (current-indentation))
          (backward-sexp-point)
          (re (concat "[uU]?[rR]?"
                      (python-rx string-delimiter))))
      (when (and
             (not (python-info-assignment-statement-p))
             (looking-at-p re)
             ;; Allow up to two consecutive docstrings only.
             (>=
                 2
               (let (last-backward-sexp-point)
                 (while (save-excursion
                          (python-nav-backward-sexp)
                          (setq backward-sexp-point (point))
                          (and (= indentation (current-indentation))
                               ;; Make sure we're always moving point.
                               ;; If we get stuck in the same position
                               ;; on consecutive loop iterations,
                               ;; bail out.
                               (prog1 (not (eql last-backward-sexp-point
                                                backward-sexp-point))
                                 (setq last-backward-sexp-point
                                       backward-sexp-point))
                               (looking-at-p
                                (concat "[uU]?[rR]?"
                                        (python-rx string-delimiter)))))
                   ;; Previous sexp was a string, restore point.
                   (goto-char backward-sexp-point)
                   (cl-incf counter))
                 counter)))
        (python-util-forward-comment -1)
        (python-nav-beginning-of-statement)
        (cond ((bobp))
              ((python-info-assignment-statement-p) t)
              ((python-info-looking-at-beginning-of-defun))
              (t nil))))))

;; Font-lock-ensure in python-mode makes Emacs 25.1 frozen:
;;
;; ┌───sh
;; │ emacs-25.1 --batch --eval "(with-temp-buffer
;; │                              (python-mode)
;; │                              (insert \"    '''dosctring'''\")
;; │                              (font-lock-mode 1)
;; │                              (font-lock-ensure))"
;; └───
;;
;; @ref https://emacs-china.org/t/face-text-property-batch/9006/6
(when (= 25.1 (string-to-number emacs-version))
  (setq python-rx-constituents python-rx-constituents@26.1)
  (advice-add 'python-info-docstring-p :override 'python-info-docstring-p@26.1))

;;;

(setq python-indent-guess-indent-offset nil)

(defun separedit-test--region-between-regexps (begin-regexp end-regexp)
  "Return region between BEGIN-REGEXP and END-REGEXP."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward begin-regexp)
      (let ((begin (point)))
        (when (re-search-forward end-regexp nil t)
          (goto-char (match-beginning 0))
          (list :beginning begin :end (point)))))))

(defun --join\n (&rest strings)
  (mapconcat #'identity
             strings
             "\n"))

(defun --bufs= (string)
  "Verify whether buffer string equals STRING."
  (should (string= string
                   (buffer-substring-no-properties (point-min)
                                                   (point-max)))))

(defun --mode= (mode)
  "Verify whether major mode equals MODE."
  (should (eq mode major-mode)))

(defun --key= (&rest args)
  "Verify keybindings.

ARGS is a list in the form of `KEY-STR CMD-SYM ...'."
  (->> (-partition 2 args)
       (--map (string= (car it) (substitute-command-keys (format "\\[%s]" (cadr it)))))
       (-none? 'null)))

(defun --with-callback (init-mode init-data key-sequnce callback &optional region-regexps)
  "Execute CALLBACK after the KEY-SEQUNCE pressed in edit buffer.

INIT-MODE       major-mode of source buffer
INIT-DATA       initial data of source buffer
REGION-REGEXPS  regexp for detection block in source buffer"
  (let ((buf (generate-new-buffer "*init*")))
    (switch-to-buffer buf)
    (insert init-data)
    (funcall init-mode)
    ;; Force enable face / text property / syntax highlighting
    (let ((noninteractive nil))
      (font-lock-mode 1))
    (font-lock-ensure)
    (goto-char (point-min))
    (re-search-forward "<|>")
    (separedit (when region-regexps
                 (apply #'separedit-test--region-between-regexps region-regexps)))
    (test-with nil key-sequnce)
    (funcall callback)))

(defun --assert-help-value (help-content expected)
  "Verify EXPECTED is included in HELP-CONTENT.

HELP-CONTENT is a copy of *Help* buffer string with point holder ‘<|>’ added in value form.
EXPECTED is of the form (symbol value type local-buffer)"
  (separedit-test--with-buffer
   'help-mode
   help-content
   (should
    (equal expected
           (let ((edit-info (separedit-help-variable-edit-info)))
             (cl-assert (and edit-info t) t "[Help] ‘edit-info’ should not be nil")
             (list (nth 0 edit-info)
                   (buffer-substring-no-properties
                    (car (nth 1 edit-info)) (cdr (nth 1 edit-info)))
                   (nth 2 edit-info)
                   (nth 3 edit-info)
                   (nth 4 edit-info)))))))

(define-derived-mode helpful-mode special-mode "Dummy Mode" "For Test")

(defun --assert-helpful-value (help-content expected)
  "Verify EXPECTED is included in HELP-CONTENT.

HELP-CONTENT is a copy of *Helpful* buffer string with point holder ‘<|>’ added in value form.
EXPECTED is of the form (symbol value type local-buffer)"
  (separedit-test--with-buffer
   'helpful-mode
   help-content
   (should
    (equal expected
           (let ((edit-info (separedit-helpful-variable-edit-info)))
             (cl-assert (and edit-info t) t "[Helpful] ‘edit-info’ should not be nil")
             (list (nth 0 edit-info)
                   (buffer-substring-no-properties
                    (car (nth 1 edit-info)) (cdr (nth 1 edit-info)))
                   (nth 2 edit-info)
                   (nth 3 edit-info)
                   (nth 4 edit-info)))))))

(defun separedit-test--execute-block-edit (init-mode key-sequnce init-data expected-data &optional region-regexps)
  (let ((buf (generate-new-buffer "*init*")))
    (switch-to-buffer buf)
    (insert init-data)
    (funcall init-mode)
    ;; Force enable face / text property / syntax highlighting
    (let ((noninteractive nil))
      (font-lock-mode 1)
      (font-lock-ensure))
    (goto-char (point-min))
    (re-search-forward "<|>")
    (separedit (when region-regexps
                    (apply #'separedit-test--region-between-regexps region-regexps)))
    (test-with nil key-sequnce)
    (should
     (equal expected-data
            (buffer-substring-no-properties (point-min) (point-max))))))

(defun separedit-test--indent (mode string &optional indent-fn)
  (with-current-buffer (generate-new-buffer "*indent*")
    (insert string)
    (funcall mode)
    (funcall (or indent-fn 'indent-region) (point-min) (point-max))
    (buffer-substring-no-properties (point-min) (point-max))))

(defun separedit-test--indent-c (&rest strings)
  (separedit-test--indent 'c-mode (apply #'concat strings)))

(defun separedit-test--indent-sh (string)
  (separedit-test--indent 'shell-script-mode string 'indent-region-line-by-line))

(defun separedit-test--indent-el (string)
  (separedit-test--indent 'emacs-lisp-mode string))

(defun separedit-test--indent-py (string)
  (separedit-test--indent 'python-mode string))

(defun separedit-test--indent-rb (string)
  (separedit-test--indent 'ruby-mode string))

(defun separedit-test--indent-pascal (string)
  (separedit-test--indent 'pascal-mode string))

(defun xah-syntax-color-hex ()
  "Syntax color text of the form 「#ff1100」 and 「#abc」 in current buffer.
URL `http://ergoemacs.org/emacs/emacs_CSS_colors.html'
Version 2016-07-04"
  (interactive)
  (font-lock-add-keywords
   nil
   '(("#[ABCDEFabcdef[:digit:]]\\{3\\}"
      (0 (put-text-property
          (match-beginning 0)
          (match-end 0)
          'face (list :background
                      (let* (
                             (ms (match-string-no-properties 0))
                             (r (substring ms 1 2))
                             (g (substring ms 2 3))
                             (b (substring ms 3 4)))
                        (concat "#" r r g g b b))))))
     ("#[ABCDEFabcdef[:digit:]]\\{6\\}"
      (0 (put-text-property
          (match-beginning 0)
          (match-end 0)
          'face (list :background (match-string-no-properties 0)))))))
  (font-lock-fontify-buffer))

(defmacro separedit-test--with-buffer (mode content &rest body)
  (declare (indent 1) (debug t))
  `(let ((buf (generate-new-buffer "*separedit-test*")))
     (unwind-protect
         (with-current-buffer buf
           (insert ,content)
           (funcall ,mode)
           (goto-char (point-min))
           (unless (re-search-forward "<|>" nil t 1)
             (message "Can't find cursor placeholder ‘<|>’"))
           (let ((noninteractive nil)
                 (jit-lock-functions '(font-lock-fontify-region)))
             (font-lock-mode 1)
             (font-lock-set-defaults)
             (jit-lock-fontify-now))
           ,@body)
       (kill-buffer buf))))

(defun escape (&rest str-list)
  "Nest escaping quoted strings in STR-LIST.
\(fn s1 s2 s3 ...)
=> (make-escape
    (concat
     s1
     (make-escape
      (concat
       s2
       (make-escape
        (concat
         s3
         ...))))))"
  (let ((s ""))
    (mapc (lambda (it)
            (setq s (format "%S" (concat it s))))
          (reverse str-list))
    s))

;; Make sure `escape' correct before testing.
(require 'cl-macs)
(cl-assert (string= (escape "a" "b" "c" "d" "e") (format "%S" "a\"b\\\"c\\\\\\\"d\\\\\\\\\\\\\\\"e\\\\\\\\\\\\\\\"\\\\\\\"\\\"\"")))
(cl-assert (string= (escape "b" "c" "d" "e")     (format "%S" "b\"c\\\"d\\\\\\\"e\\\\\\\"\\\"\"")))
(cl-assert (string= (escape "c" "d" "e")         (format "%S" "c\"d\\\"e\\\"\"")))
(cl-assert (string= (escape "d" "e")             (format "%S" "d\"e\"")))
(cl-assert (string= (escape "e")                 (format "%S" "e")))

(defun escape-sq (&rest str-list)
  "Nest escaping single-quoted strings in STR-LIST.
\(fn s1 s2 s3 ...)
=> (make-escape
    (concat
     s1
     (make-escape
      (concat
       s2
       (make-escape
        (concat
         s3
         ...))))))"
  (replace-regexp-in-string "\"" "'" (apply #'escape str-list)))

(defun nest-and-assert (curr &rest nexts)
  ;;; remove escape
  (save-restriction
    (goto-char (point-min))
    (search-forward "\"")
    (apply 'narrow-to-region (separedit--string-region))
    (separedit--remove-escape "\"")
    (should (string= (car curr) (format "%S" (buffer-substring-no-properties (point-min) (point-max)))))
    (when nexts
      (apply #'nest-and-assert nexts))
  ;;; restore escape
    (separedit--restore-escape "\""))
  (should (string= (cdr curr) (format "%S" (buffer-substring-no-properties (point-min) (point-max))))))

(defun nest-and-assert-sq (curr &rest nexts)
  ;;; remove escape
  (save-restriction
    (goto-char (point-min))
    (search-forward "'")
    (apply 'narrow-to-region (separedit--string-region))
    (separedit--remove-escape "'")
    (should (string= (car curr)
                     (replace-regexp-in-string
                      "\"" "'"
                      (format "%S" (replace-regexp-in-string ;; Convert to double-quoted string, then \
                                    "'" "\""                 ;; use `format' to add escape characters.
                                    (buffer-substring-no-properties (point-min) (point-max)))))))
    (when nexts
      (apply #'nest-and-assert-sq nexts))
  ;;; restore escape
    (separedit--restore-escape "'"))
  (should (string= (cdr curr)
                     (replace-regexp-in-string
                      "\"" "'"
                      (format "%S" (replace-regexp-in-string ;; Convert to double-quoted string, then \
                                    "'" "\""                 ;; use `format' to add escape characters.
                                    (buffer-substring-no-properties (point-min) (point-max))))))))

(defun separedit--generate-markdown-toc (&optional start-level)
  "Generate markdown ToC."
  (require 's)
  (let ((headings)
        (faces (mapcar (lambda (num)
                         (intern (format "markdown-header-face-%s" num)))
                       (reverse (number-sequence
                                 (if start-level start-level 1) 6)))))
    (save-excursion
      (goto-char (point-min))
      (while (search-forward-regexp markdown-regex-header nil 'noerror)
        (push (or (match-string 1) (match-string 5)) headings)))
    (->> (reverse headings)
      ;; rename duplicates
      (-group-by #'identity)
      (--map (-map-indexed (lambda (index text)
                             (cons text (if (zerop index) text
                                          (format "%s %s" text index))))
                           (cdr it)))
      ;; generate links
      (-flatten)
      (--map (let ((level (memq (get-char-property 0 'face (car it)) faces)))
               (when level
                 (format "%s- [%s](#%s)"
                         (make-string (* (1- (length level)) 4) ?\s)
                         (substring-no-properties (car it))
                         (->> (substring-no-properties (cdr it))
                           (downcase)
                           (replace-regexp-in-string " " "-")
                           (replace-regexp-in-string "[[:punct:]]"
                                                     (lambda (s)
                                                       (if (member s '("-" "_"))
                                                           s
                                                         ""))))))))
      (-non-nil)
      (s-join "\n"))))

(defun separedit-test--generate-readme ()
  (with-temp-buffer
    (insert-file-contents "separedit.el")
    (emacs-lisp-mode)
    (goto-char (point-min))
    (let* ((reg (or (separedit-test--region-between-regexps "^;;; Commentary:\n+" "\n;;; .*$")
                    (error "Commentary not found in current file!")))
           (str (buffer-substring-no-properties (plist-get reg :beginning) (plist-get reg :end))))
      (with-temp-buffer
        (insert str)
        (separedit--remove-comment-delimiter
         (separedit--comment-delimiter-regexp 'emacs-lisp-mode))
        (markdown-mode)
        ;; Force enable face / text property / syntax highlighting
        (let ((noninteractive nil))
          (font-lock-mode 1)
          (font-lock-ensure))
        (goto-char (point-min))
        (if (re-search-forward "^{{TOC}}$" nil t)
            (progn
              (replace-match "")
              (insert (separedit--generate-markdown-toc 2)))
          (error "Can't find the ToC placeholder."))
        (buffer-string)))))

;;; separedit-test-helper.el ends here
