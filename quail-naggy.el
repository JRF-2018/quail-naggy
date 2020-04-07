;; -*- mode: Emacs-Lisp; coding: utf-8 -*-
;;; quail-naggy.el --- A simple input method.
;; Time-stamp: <2020-01-24T02:45:43Z>
;;
(defconst quail-naggy-version-number "0.16"
  "Version number for this version of quail-naggy.")
(defconst quail-naggy-version
  (format "quail-naggy version %s" quail-naggy-version-number)
  "Version string for this version of quail-naggy.")
;;
;; Author: JRF (http://jrf.cocolog-nifty.com/)
;; Keywords: mule, multilingual, input method
;; Language of Comments: Japanese.

;; License:
;;
;;   The author is a Japanese.
;;
;;   I intended this program to be public-domain, but you can treat
;;   this program under the (new) BSD-License or under the Artistic
;;   License, if it is convenient for you.
;;
;;   Within three months after the release of this program, I
;;   especially admit responsibility of efforts for rational requests
;;   of correction to this program.
;;
;;   I often have bouts of schizophrenia, but I believe that my
;;   intention is legitimately fulfilled.
;;
;; Author's Link:
;;
;;   http://jrf.cocolog-nifty.com/software/
;;   (The page is written in Japanese.)
;;

;; Notice:
;; 
;;   この Elisp ファイルは、主に、Emacs 23.3 付属の quail/japanese.el
;;   と kkc.el および、私がずいぶん前に作った vkegg.el を参考にして作ら
;;   れている。
;;
;;   「単漢字変換」というアイデアとその実用性は、PC-9801用および
;;   Windows用の日本語 IME『風』から学んだ。
;;

;; 設定例:
;;
;;   /usr/share/emacs/site-lisp/quail-naggy 以下に quail-naggy.el や
;;   naggy-backend.plその他のファイルがインストールされているとす
;;   る。.emacs に以下のように書く。
;;
;; ;;
;; ;; Naggy
;; ;;
;; (setq load-path (append load-path (list "/usr/share/emacs/site-lisp/quail-naggy")))
;; (require 'quail-naggy)
;; (setq naggy-backend-program "/usr/bin/perl")
;; (setq naggy-backend-options
;;      '("/usr/share/emacs/site-lisp/quail-naggy/naggy-backend.pl"))
;; (setq default-input-method "japanese-naggy")
;;

;;; Code:

(if (featurep 'unicode) (require 'unicode))
(if (not (functionp 'ucs-to-char))
    (defun ucs-to-char (c) (decode-char 'ucs c)))
(require 'quail)
(require 'mule-util)


;;
;; naggy-backend
;;

(defvar naggy-backend-program "naggy-backend.pl")
(defvar naggy-backend-options nil)
(defvar naggy-backend-necessary-options '("-D" "FRONT_END=quail-naggy"))
(defvar naggy-backend-timeout 15)
(defvar naggy-backend-process-start-hook nil)
(defvar naggy-backend-process-now-starting nil)

(defun naggy-escape-string (src)
  (if (string= src "")
      "\\0"
    (save-match-data
      (let ((dest "") (pos 0) c)
	(while (string-match "[\x00-\x20\x7F\\\\#]" src pos)
	  (setq c (format "\\x%02X" (string-to-char (match-string 0 src))))
	  (setq dest (concat dest (substring src pos (match-beginning 0)) c))
	  (setq pos (match-end 0)))
	(concat dest (substring src pos))))))

(defun naggy-unescape-string (src)
  (save-match-data
    (let ((dest "") (pos 0) c x u)
      (while (string-match "\\\\[0nt]\\|\\\\[^01-9A-Za-z]\\|\\\\x[01-9a-fA-F][01-9a-fA-F]\\|\\\\u{[01-9a-fA-F]+}\\|\\\\u([01-9a-fA-F]+)" src pos)
	(setq x (string-to-char (substring (match-string 0 src) 1 2)))
	(cond ((= x ?0) (setq c ""))
	      ((= x ?t) (setq c "\t"))
	      ((= x ?n) (setq c "\n"))
	      ((= x ?x) (setq u (substring (match-string 0 src) 2)))
	      ((= x ?u) (setq u (substring (match-string 0 src) 3)))
	      (t (setq c (char-to-string x))))
	(if u
	    (setq c (char-to-string (ucs-to-char (string-to-number u 16)))))
	(setq dest (concat dest (substring src pos (match-beginning 0)) c))
	(setq pos (match-end 0)))
      (concat dest (substring src pos)))))

;;; テスト用コード
;(naggy-unescape-string (naggy-escape-string ""))
;(naggy-unescape-string (naggy-escape-string "a b\\#c"))
;(naggy-unescape-string "a\\x5cb\\0c")
;(naggy-unescape-string "a\\u{3042}b\\0c")
;(naggy-unescape-string "a\\\\\\u(3042)b\\0c")

(defun naggy-backend-process-filter (proc s)
  (let ((buf (process-buffer proc)))
    (when (buffer-live-p buf)
      (with-current-buffer buf
	(let ((moving (= (point) (process-mark proc))))
	  (save-excursion
	    (let ((buffer-undo-list t)
		  (inhibit-read-only t))
	      (goto-char (process-mark proc))
	      (insert s)
	      (set-marker (process-mark proc) (point))
	      (while (re-search-backward	
			   "^# \\(info\\|warn\\) +\\(.*\\)\n" nil t)
		(message (format "naggy-backend: %s %s"
				 (match-string 1)
				 (naggy-unescape-string (match-string 2))))
		(delete-region (match-beginning 0) (match-end 0)))))
	  (if moving (goto-char (process-mark proc))))))))

(defun naggy-backend-command (args)
  (let* ((r nil)
	 (buf (get-buffer-create " *naggy-backend*"))
	 (process (get-buffer-process buf)))
    (save-excursion
      (set-buffer buf)
      (setq buffer-auto-save-file-name nil)
      (erase-buffer)
      (if (and (null process) (not naggy-backend-process-now-starting))
	  (progn 
	    (setq naggy-backend-process-now-starting t)
	    (setq process
		  (let ((process-connection-type nil))
		    (apply (function start-process)
			   (append
			    (list "naggy-backend" buf
				  naggy-backend-program)
			    naggy-backend-options
			    naggy-backend-necessary-options))))
	    (set-process-query-on-exit-flag process nil)
	    (set-process-coding-system process 'utf-8-unix)
	    (set-process-filter process 'naggy-backend-process-filter)
	    (run-hooks 'naggy-backend-process-start-hook)
	    (setq naggy-backend-process-now-starting nil)))
      (if (null process)
	  (error "Can't invoke naggy-backend.pl"))
      (let ((cmd ""))
	(while args
	  (setq cmd (concat cmd (naggy-escape-string (car args))))
	  (setq args (cdr args))
	  (if args
	      (setq cmd (concat cmd " "))
	    (setq cmd (concat cmd "\n"))))
	(process-send-string process cmd))
      (catch 'recieved
	(while (accept-process-output process naggy-backend-timeout)
	  (goto-char (process-mark process))
	  (if (search-backward "# end" 0 t)
	      (let (bg type (ed (1- (point))))
		(search-backward "# begin" 0 t)
		(goto-char (match-end 0))
		(skip-chars-forward " \t")
		(setq bg (point))
		(skip-chars-forward "^ \t\n")
		(setq type (buffer-substring bg (point)))
		(forward-line)
		(skip-chars-forward " \t\n")
		(setq bg (point))
		(cond
		 ((string= type "unit")
		  (throw 'recieved t))
		 ((string= type "string")
		  (skip-chars-forward "^\n")
		  (throw 'recieved
			 (naggy-unescape-string
			  (buffer-substring bg (point)))))
		 ((string= type "base64")
		  (throw 'recieved
			 (base64-decode-string
			  (buffer-substring bg ed))))
		 (t
		  (let (l r)
		    (while (< (point) ed)
		      (setq l nil)
		      (skip-chars-forward " \t")
		      (while (not (eolp))
			(setq bg (point))
			(skip-chars-forward "^ \t\n")
			(setq l (cons (naggy-unescape-string
				       (buffer-substring bg (point))) l))
			(skip-chars-forward " \t"))
		      (setq r (cons (reverse l) r))
		      (forward-line))
		    (throw 'recieved (reverse r))))))
	    (goto-char (process-mark process))
	    (if (search-backward "# error" 0 t)
		(let (bg)
		  (goto-char (match-end 0))
		  (skip-chars-forward " \t")
		  (setq bg (point))
		  (skip-chars-forward "^\n")
		  (message (concat "Error on naggy-backend: "
				   (naggy-unescape-string
				    (buffer-substring bg (point)))))
		  (throw 'recieved nil)))))
	(error "naggy-backend: Time-out.")))))

;;; テスト用コード
;(naggy-backend-command '("base64test"))
;(naggy-backend-command '("listtest"))
;(naggy-backend-command '("warntest"))
;(naggy-backend-command '("test string"))
;(naggy-backend-command '("nop"))
;(naggy-backend-command '("translit" "alpha-hira" "akairingo"))
;(naggy-backend-command '("exit"))
;(add-hook 'naggy-backend-process-start-hook
;	  (lambda () (message "start hook ok")))

(defun naggy-backend-start ()
  (interactive)
  (naggy-backend-command '("nop")))

(defun naggy-backend-restart ()
  (interactive)
  (naggy-backend-command '("exit"))
  (naggy-backend-command '("nop")))


;;
;; quail-naggy
;;

(defun quail-naggy-terminate-fullwidth ()
  (interactive)
  (setq quail-conversion-str
	(naggy-backend-command (list "translit" "hw-fw"
				     quail-conversion-str)))
  (quail-no-conversion))

(defun quail-naggy-terminate-hiragana ()
  (interactive)
  (setq quail-conversion-str
	(naggy-backend-command (list "translit" "alpha-hira"
				     quail-conversion-str)))
  (quail-no-conversion))

(defun quail-naggy-terminate-katakana ()
  (interactive)
  (setq quail-conversion-str
	(naggy-backend-command (list "translit" "alpha-kata"
				     quail-conversion-str)))
  (quail-no-conversion))

(defun quail-naggy-terminate-hwkata ()
  (interactive)
  (setq quail-conversion-str
	(naggy-backend-command (list "translit" "alpha-hwkata"
				     quail-conversion-str)))
  (quail-no-conversion))

(defun quail-naggy-cancel ()
  (interactive)
  (setq quail-conversion-str "")
  (quail-no-conversion))

(defun quail-naggy-convert ()
  (interactive)
  (let* ((from (copy-marker (overlay-start quail-conv-overlay)))
	 (len (- (overlay-end quail-conv-overlay) from)))
    (if (<= len 0)
	(progn
	  (quail-naggy-insert-space)
	  (quail-no-conversion))
      (quail-delete-overlays)
      (setq quail-current-str nil)
      (unwind-protect
	  (let ((result (naggy-convert-region from (+ from len))))
	    (move-overlay quail-conv-overlay from (point))
	    (setq quail-conversion-str (buffer-substring from (point)))
	    (if (= (+ from result) (point))
		(setq quail-converting nil))
	    (setq quail-translating nil))
	(set-marker from nil)))))

(defun quail-naggy-convert-with-prev-modification ()
  (interactive)
  (if naggy-convert-prev-modification
      (let ((pos (overlay-start quail-overlay)))
	(insert (concat "#" naggy-convert-prev-modification))
	(move-overlay quail-overlay pos (point))
	(if (overlayp quail-conv-overlay)
	    (if (not (overlay-start quail-conv-overlay))
		(move-overlay quail-conv-overlay pos (point))
	      (if (< (overlay-end quail-conv-overlay) (point))
		  (move-overlay quail-conv-overlay
				(overlay-start quail-conv-overlay)
				(point)))))))
  (quail-naggy-convert))

(defun quail-naggy-insert-space ()
  (interactive)
  (setq quail-current-key
	(concat quail-current-key " "))
  (or (catch 'quail-tag
	(quail-update-translation (quail-translate-key))
	t)
      (setq quail-translating nil)))

(quail-define-package
 "japanese-naggy" "Japanese" "naggy"
 nil
 "単漢字変換 Input Method。Naggy。
"
 nil
 t t nil nil nil nil nil
 'quail-naggy-update-translation ; updater
 '((" " . quail-naggy-convert)
   ("\e " . quail-naggy-convert-with-prev-modification)
   ("\C-m" . quail-no-conversion)
   ("\C-g" . quail-naggy-cancel)
   ([return] . quail-no-conversion)
   ([?\S- ] . quail-naggy-insert-space)
   ("\C-i" . quail-naggy-terminate-fullwidth)
   ("\e\t" . quail-naggy-terminate-hiragana)
   ([S-return] . quail-naggy-terminate-hiragana)
   ([nfer] . quail-naggy-terminate-hiragana)
   ([execute] . quail-naggy-terminate-hiragana)
   ([muhenkan] . quail-naggy-terminate-hiragana)
   ([noconvert] . quail-naggy-terminate-hiragana)
   ([non-convert] . quail-naggy-terminate-hiragana)
   ([S-tab] . quail-naggy-terminate-katakana)
   ([xfer] . quail-naggy-terminate-katakana)
   ([kanji] . quail-naggy-terminate-katakana)
   ([henkan] . quail-naggy-terminate-katakana)
   ([henkan-mode] . quail-naggy-terminate-katakana)
   ([numbersign] . quail-naggy-terminate-katakana)
   ([convert] . quail-naggy-terminate-katakana)
   ([S-xfer] . quail-naggy-terminate-hwkata)
   ([S-kanji] . quail-naggy-terminate-hwkata)
   ([S-henkan] . quail-naggy-terminate-hwkata)
   ([S-henkan-mode] . quail-naggy-terminate-hwkata)
   ([S-numbersign] . quail-naggy-terminate-hwkata)
   ([S-convert] . quail-naggy-terminate-hwkata))
 )

 (let ((c 32))
   (while (< c 127)
     (quail-defrule (char-to-string c) (char-to-string c))
     (setq c (1+ c))))


(defun quail-naggy-update-translation (control-flag)
  (if (null control-flag)
      (setq quail-current-str
	    (or quail-current-str quail-current-key))
    (if (integerp control-flag)
	(if (= control-flag 0)
	    (setq quail-current-str (aref quail-current-key 0))
	  (setq quail-current-str (aref quail-current-key 0))
	  (if (integerp control-flag)
	      (setq unread-command-events
		    (list (aref quail-current-key control-flag)))))))
  control-flag)


;;
;; naggy-vk
;;

(defvar naggy-vk-use-frame 
  (if (or (eq window-system 'x) (eq window-system 'w32))
      'top
    nil)
  "frameを使うか否か。
      nil : 使わない。windowを分割して表示。
      t : 使う。
      'auto : 自動的に表示位置を判別。
      'top : 自動的に top 辺りに表示。
      'invisible : 変換中のみ frameを表示。")

;; X-Window上ではフレームを使う.

(defvar naggy-vk-kouho-frame-geometry nil
  "候補表示を行なう frame の geometry。")

;; 実際に位置を指定する場合,
;;例 1: (setq naggy-vk-kouho-frame-geometry "-0+0")
;;例 2: (setq naggy-vk-kouho-frame-geometry '((top . 0) (left . -)))
;;
;;例 3: 相対的に位置を指定する場合,
;;(let* ((top (cdr (assq 'top (frame-parameters))))
;;       (left (cdr (assq 'left (frame-parameters))))
;;       (bottom (+ top (frame-pixel-height))))
;;  (setq naggy-vk-kouho-frame-geometry 
;;	(list (cons 'top (- top (* 7 (frame-char-height))))
;;	      (cons 'left (+ left (* (/ (- (frame-width) 50) 2)
;;				     (frame-char-width)))))))

(defvar naggy-vk-auto-window-margin 11
  "naggy-vk-use-frame を 'auto に設定した場合, frame の表示位置をカーソルの中心からどれだけ離すかを pixel 値で示す。")

(defvar naggy-vk-use-mode-line t
  "t ならば, モードラインまで使って frame を小さく表示する。")

(defvar naggy-vk-split-window-length 6
  "frame を使わない場合のウィンドウの高さ。")

(defvar naggy-vk-frame-length 6
  "frame を使う場合のウィンドウの高さ。")

(defvar naggy-vk-blank-string "○--"
  "候補がない部分の文字列。")
(defvar naggy-vk-fullwidth-space ?　
  "全角スペース。")

(defvar naggy-vk-home-position-face 'bold)
(defvar naggy-vk-highlight-face 'highlight)
(defvar naggy-vk-secondary-face 'secondary-selection)
(defvar naggy-vk-highlight-char nil
  "non-nil string ならば highligt 時にその文字を後ろにつける。")

;;
;; システム変数
;;
(defvar naggy-vk-kouho-frame nil
  "候補を表示するframe")

(defvar naggy-vk-selected-window nil)

(defvar naggy-vk-state nil)

(defvar naggy-vk-candidates nil
  "naggy-vk-zenkouho 中の番号を 40 個ならべた vector ページの vector。")
(defvar naggy-vk-current-plane nil)
(defvar naggy-vk-current-kouho-number nil
  "現在指定されている naggy-vk-zenkouho の中の番号。")
(defvar naggy-vk-current-cursor nil
  "現在指定されている naggy-vk の上の位置。")

(defvar naggy-vk-zenkouho nil
  "全候補のリスト。")

(defconst naggy-vk-logo
  (concat 
   "1--- 2--- 3--- 4--- 5---|6--- 7--- 8--- 9--- 0---\n"
   "q--- w--- e--- r--- t---|y--- u--- i--- o--- p---\n"
   "a--- s--- d--- f--- g---|h--- j--- k--- l--- '---\n"
   "z--- x--- c--- v--- b---|n--- m--- ,--- .--- /---\n"
   "                                            Naggy"))

(defvar naggy-vk-char-to-pos-tbl
  (let ((dest nil)
	(tbl (concat "1234567890"
		     "qwertyuiop"
		     "asdfghjkl;"
		     "zxcvbnm,./"))
	(i 0))
    (while (< i 40)
      (setq dest (cons (cons (aref tbl i) i) dest))
      (setq i (1+ i)))
    dest)
  "キーボード上の文字と表の対応。")

(defun naggy-vk-make-candidates-from-zenkouho ()
  (let (i c cur (len (length naggy-vk-zenkouho)) (max 0))
    (setq i 0)
    (while (< i len)
      (setq cur (nth i naggy-vk-zenkouho))
      (setq c (string-to-number (nth 1 cur)))
      (if (> c max)
	  (setq max c))
      (setq i (1+ i)))
    (setq len (/ (+ max 40) 40))
    (setq naggy-vk-candidates (make-vector len nil))
    (setq i 0)
    (while (< i len)
      (aset naggy-vk-candidates i (make-vector 40 nil))
      (setq i (1+ i)))
    (setq len (length naggy-vk-zenkouho))
    (setq i 0)
    (while (< i len)
      (setq cur (nth i naggy-vk-zenkouho))
      (setq c (string-to-number (nth 1 cur)))
      (aset (aref naggy-vk-candidates (/ c 40)) (% c 40) i)
      (setq i (1+ i)))))

(defun naggy-vk-first-kouho-number-of-plane (plane)
  (let (i cur num (len (length naggy-vk-zenkouho)))
    (setq i 0)
    (while (and (null num) (< i len))
      (setq cur (nth i naggy-vk-zenkouho))
      (if (= plane (/ (string-to-number (nth 1 cur)) 40))
	  (setq num i))
      (setq i (1+ i)))
    num))

(defun naggy-vk-current-window-position ()
  (let* ((y 0) (w (selected-window)) (ht (window-height))
	 (motion (compute-motion (window-start) '(0 . 0)
				 (point)
				 (cons (window-width) (window-height))
				 (1- (window-width))
				 (cons (window-hscroll) 0)
				 w)))
    (catch 'ok
      (while (< y ht)
	(if (eq w (window-at 0 y))
	    (throw 'ok y)
	  (setq y (1+ y)))))
    (cons (car (cdr motion)) (+ (car (cdr (cdr motion))) y))))

(defun naggy-vk-get-kouho-frame-geometry ()
  (cond ((eq naggy-vk-use-frame 'auto)
	 (let* ((margin naggy-vk-auto-window-margin)
		(param (frame-parameters))
		(top (+ (cdr (assq 'top param)) 20))
		(left (cdr (assq 'left param)))
		(ht (cdr (assq 'height param)))
		(cht (frame-char-height))
		(cwt (frame-char-width))
		(pos (naggy-vk-current-window-position)))
	   (setq left
		 (let ((max (- (+ left (frame-pixel-width)) (* 50 cwt)))
		       (min left)
		       (pos (+ left (* cwt (- (car pos) 6)))))
		   (if (> pos max)
		       max
		     (if (< pos min)
			 min
		       pos))))
	   (if (<= (cdr pos) (/ ht 2))
	       (list 
		(cons 'top (+ top (+ margin (+ (/ cht 2) 
					       (* cht (1+ (cdr pos)))))))
		(cons 'left left))
	     (list
	      (cons 'top (+ top  (- (+ (* cht (- (cdr pos) 
						 (if naggy-vk-use-mode-line 5 6)))
				       (/ cht 2))
				    margin)))
	      (cons 'left left)))))
	((or (eq naggy-vk-use-frame 'top) (eq naggy-vk-use-frame 'invisible))
	 (let* ((top (mod (cdr (assq 'top (frame-parameters))) 
			  (x-display-pixel-height)))
		(left (mod (cdr (assq 'left (frame-parameters)))
			   (x-display-pixel-width)))
		(bottom (+ top (frame-pixel-height))))
	   (list (cons 'top (- top (* 7 (frame-char-height))))
		 (cons 'left (+ left (* (/ (- (frame-width) 50) 2)
					(frame-char-width)))))))

	(t
	 (if (stringp naggy-vk-kouho-frame-geometry)
	     (x-parse-geometry naggy-vk-kouho-frame-geometry)
	   naggy-vk-kouho-frame-geometry))))

(defun naggy-vk-open-kouho-window ()
  "候補表示用のウィンドウを開き, そこをセレクトする。
  naggy-vk-display-kouho-list内でのみ使用。"
  (setq naggy-vk-state 'open)
  (if naggy-vk-use-frame
      (progn
	(or (and naggy-vk-kouho-frame (frame-live-p naggy-vk-kouho-frame))
	    (let ((inhibit-quit t))
	      (setq naggy-vk-kouho-frame 
		    (make-frame (append (naggy-vk-get-kouho-frame-geometry)
					(list
					 '(name . "naggy_vk_candidates") 
					 (cons 'height 
					       (if naggy-vk-use-mode-line 
						   (1- naggy-vk-frame-length)
						 naggy-vk-frame-length))
					 '(visibility . nil)
					 (if naggy-vk-highlight-char
					     '(width . 51)
					   '(width . 50))
					 '(vertical-scroll-bars . nil)
					 '(menu-bar-lines . nil)
					 '(user-position t)
					 (cons 'modeline naggy-vk-use-mode-line)
					 '(minibuffer . nil)))))))
	(if (or (eq naggy-vk-use-frame 'auto)
		(eq naggy-vk-use-frame 'top))
	    (modify-frame-parameters naggy-vk-kouho-frame 
				     (naggy-vk-get-kouho-frame-geometry)))
	(or (frame-visible-p naggy-vk-kouho-frame)
	    (make-frame-visible naggy-vk-kouho-frame))
	(if (string-match "XEmacs" emacs-version)
	    (progn
	      (set-specifier scrollbar-width (list naggy-vk-kouho-frame 0))
	      (set-specifier default-toolbar-visible-p
			     (list naggy-vk-kouho-frame nil))))
	(raise-frame naggy-vk-kouho-frame)
	(redirect-frame-focus naggy-vk-kouho-frame (selected-frame))
	(select-frame naggy-vk-kouho-frame))
    (or (and naggy-vk-kouho-frame (window-live-p naggy-vk-kouho-frame)
	     (null (one-window-p)))
	(progn
	  (let (new (selected (selected-window)))
	    (setq new (split-window selected 
				    (- (window-height selected) 
				       (if naggy-vk-use-mode-line 
					   (1- naggy-vk-split-window-length)
					 naggy-vk-split-window-length))
				    nil))
	    (setq naggy-vk-kouho-frame (next-window selected)))))
    (select-window naggy-vk-kouho-frame)))

(defun naggy-vk-close-kouho-window ()
  "候補表示用のウィンドウを必要とあらば閉じる。
  naggy-vk-display-kouho-list内でのみ使用。"
  (save-excursion
    (set-buffer (get-buffer-create " *naggy-vk-candidates*"))
    (setq buffer-read-only nil)
    (erase-buffer)
    (if naggy-vk-logo
	(insert naggy-vk-logo))
    (if naggy-vk-use-mode-line
	(setq mode-line-format (format "%50s" " Naggy ")))
    (setq buffer-read-only t))
  (if naggy-vk-use-frame
      (and naggy-vk-kouho-frame (frame-live-p naggy-vk-kouho-frame)

;	   (or (redirect-frame-focus naggy-vk-kouho-frame nil) t)
	   (or (eq naggy-vk-use-frame 'invisible)
	       (eq naggy-vk-use-frame 'auto))
;	       (make-frame-invisible naggy-vk-kouho-frame)
;	   (if (<= 34 (string-to-int (substring emacs-version 3)))
;	       (make-frame-invisible naggy-vk-kouho-frame)
;	     (delete-frame naggy-vk-kouho-frame)))
	   (make-frame-invisible naggy-vk-kouho-frame))
    (and naggy-vk-kouho-frame (window-live-p naggy-vk-kouho-frame)
	 (delete-window naggy-vk-kouho-frame))
    (setq naggy-vk-kouho-frame nil))
  (setq naggy-vk-state 'close))


(defun naggy-vk-insert-candidate-string (dest-buffer pos)
  "バッファ上に n 番目の候補を含むリストを挿入する。
  naggy-vk-display-kouho-list内でのみ使用。"
  (let* (c f s cur hilit knum cand (i 0))
    (setq cand (aref naggy-vk-candidates
		     (% naggy-vk-current-plane (length naggy-vk-candidates))))
    (setq i 0
	  s 0)
    (while (< i 40)
      (setq f (point))
      (setq c (aref cand i))
      (if (= pos i)
	  (progn
	    (setq s (point))
	    (if (and c (null naggy-vk-current-kouho-number))
		(setq naggy-vk-current-kouho-number c))))
      (setq cur (and c (nth c naggy-vk-zenkouho)))
      (setq hilit (and cur (string= (nth 2 cur) "h")))
      (insert (if c
		  (truncate-string-to-width (nth 0 cur) 4 nil ?-)
		naggy-vk-blank-string))
      (if window-system
	  (progn
	    (if (or (eq i 26) (eq i 23))
		(put-text-property f (point) 'face naggy-vk-home-position-face))
	    (if c
		(progn
		  (put-text-property f (point) 'kouho-number
				     (cons dest-buffer c))
		  (if hilit
		      (progn
			(put-text-property f (point) 'mouse-face 
					   naggy-vk-secondary-face)
			(put-text-property f (point) 'face
					   naggy-vk-highlight-face))
		    (put-text-property f (point) 
				       'mouse-face naggy-vk-highlight-face))))))
      (if (and hilit naggy-vk-highlight-char)
	  (cond
	   ((= (% i 10) 9) (insert (concat naggy-vk-highlight-char "\n")))
	   ((= (% i 10) 4) (insert naggy-vk-highlight-char))
	   (t (insert naggy-vk-highlight-char)))
	(cond
	 ((= (% i 10) 9) (insert "\n"))
	 ((= (% i 10) 4) (insert "|"))
	 (t (insert " "))))
      (setq i (1+ i)))
  (if (null naggy-vk-current-kouho-number)
	(setq cur "")
      (setq cur (nth naggy-vk-current-kouho-number naggy-vk-zenkouho))
      (setq cur (if (string= (nth 3 cur) "")
		    (nth 0 cur)
		  (concat (nth 0 cur) "; " (nth 3 cur)))))
    (if naggy-vk-use-mode-line
	(progn
	  (goto-char 0)
	  (setq mode-line-format (format "%2d/%2d %-43s"
					 (1+
					  (% naggy-vk-current-plane
					     (length naggy-vk-candidates)))
					 (length naggy-vk-candidates)
					 cur)))
      (insert (format "%2d/%2d %s"
		      (1+
		       (% naggy-vk-current-plane
			  (length naggy-vk-candidates)))
		      (length naggy-vk-candidates)
		      cur)))
    (goto-char s)))

(defun naggy-vk-display-kouho-list ()
  "候補表示ウィンドウの表示のメインルーチン。
  naggy-vk-current-kouho-number が設定されていて naggy-current-place が nil のときはその候補のページを表示する。naggy-vk-current-kouho-number が nil のときは naggy-vk-current-plane と naggy-vk-current-cursor を元に表示する。"
  (interactive)
  (run-hooks 'naggy-vk-display-hook)
  (let (pt (selected (selected-window)) 
	   (dest-buffer (current-buffer))
	   (naggy-vk-buffer (get-buffer-create " *naggy-vk-candidates*")))
    (if (null naggy-vk-current-kouho-number)
	(if (null naggy-vk-current-cursor)
	    (setq naggy-vk-current-cursor 0))
      (let* ((cur (nth naggy-vk-current-kouho-number naggy-vk-zenkouho))
	     (c (string-to-number (nth 1 cur))))
	(if (null naggy-vk-current-plane)
	    (setq naggy-vk-current-plane (/ c 40)))
	(if (= (% naggy-vk-current-plane (length naggy-vk-candidates))
	       (/ c 40))
	    (setq naggy-vk-current-cursor (% c 40))
	  (setq naggy-vk-current-cursor 0))))
    (save-excursion 
      (set-buffer naggy-vk-buffer)
      (if (null (eq major-mode 'naggy-vk-mode))
	  (naggy-vk-mode))
      (setq buffer-read-only nil)
      (erase-buffer)
      (naggy-vk-insert-candidate-string dest-buffer
					naggy-vk-current-cursor)
      (setq pt (point))
      (setq buffer-read-only t))
    (if (not (input-pending-p))
	(let (done)
	  (unwind-protect
	      (save-excursion
		(naggy-vk-open-kouho-window)
		(switch-to-buffer naggy-vk-buffer)
		(goto-char pt)
		(setq done t))
	    (or done (naggy-vk-close-kouho-window)))))
    (bury-buffer naggy-vk-buffer)
    (setq naggy-vk-selected-window selected)
    (select-window selected)))


;; 候補ウィンドウ内の設定
(defvar naggy-vk-mode-map (make-sparse-keymap)
  "マウス用のキーマップ。")

(defun naggy-vk-mode ()
  "候補表示ウィンドウ内のモード。"
  (interactive)
  (kill-all-local-variables)
  (use-local-map naggy-vk-mode-map)
  (setq mode-name "Naggy")
  (setq major-mode 'naggy-vk-mode)
  (setq buffer-read-only t)
  (buffer-disable-undo)
  (run-hooks 'naggy-vk-mode-hook))

(defvar naggy-vk-mode-hook nil
  "naggy-vk の起動時のフック。")
(defvar naggy-vk-display-hook nil
  "naggy-vk 候補ウィンドウ表示時のフック。")

(defun naggy-vk-shift-space ()
  (interactive)
  (if (string= current-input-method-title "naggy")
      (insert naggy-vk-fullwidth-space)
    (insert ? )))

(global-set-key [?\S- ] 'naggy-vk-shift-space)


;;
;; naggy-convert
;;

(defvar naggy-convert-input-method-title "Naggy"
  "Naggy が変換中のときのモードライン上での文字列。")

(defun naggy-convert-help ()
  "Show key bindings available while converting by Naggy."
  (interactive)
  (with-output-to-temp-buffer "*Help*"
    (princ (substitute-command-keys "\\{naggy-convert-keymap}"))))

(defvar naggy-convert-keymap
  (let* ((map (make-sparse-keymap))
	 (tbl (concat "1234567890"
		      "qwertyuiop"
		      "asdfghjkl;"
		      "zxcvbnm,./"))
	 (len (length tbl))
	 (i 0))
    (while (< i len)
      (define-key map (char-to-string (aref tbl i))
	'naggy-convert-select-and-terminate)
      (define-key map (concat "\e" (char-to-string (aref tbl i)))
	'naggy-convert-select)
      (setq i (1+ i)))
    (define-key map " " 'naggy-convert-next-page)
    (define-key map "\C-h" 'naggy-convert-prev-page)
    (define-key map [backspace] 'naggy-convert-prev-page)
    (define-key map [delete] 'naggy-convert-prev-page)
    (define-key map "\r" 'naggy-convert-terminate)
    (define-key map [return] 'naggy-convert-terminate)
;    (define-key map "\C-n" 'naggy-convert-next-kouho)
;    (define-key map "\C-p" 'naggy-convert-prev-kouho)
;    (define-key map "\C-f" 'naggy-convert-right-kouho)
;    (define-key map "\C-b" 'naggy-convert-left-kouho)
    (define-key map "\C-n" 'naggy-vk-down-kouho)
    (define-key map "\C-p" 'naggy-vk-up-kouho)
    (define-key map "\C-f" 'naggy-vk-right-kouho)
    (define-key map "\C-b" 'naggy-vk-left-kouho)
    (define-key map "\C-g" 'naggy-convert-cancel)
    (define-key map "\C-c" 'naggy-convert-cancel)
    (define-key map "\C-?" 'naggy-convert-help)
    (define-key map [mouse-1] 'naggy-vk-mouse-select)
    (define-key map [down-mouse-1] 'ignore)
    (define-key map [mouse-2] 'naggy-vk-mouse-select-and-terminate)
    (define-key map [down-mouse-2] 'ignore)
    (define-key map "\t" 'naggy-convert-terminate-fullwidth)
    (define-key map "\e\t" 'naggy-convert-terminate-hiragana)
    (define-key map [S-return] 'naggy-convert-terminate-hiragana)
    (define-key map [nfer] 'naggy-convert-terminate-hiragana)
    (define-key map [execute] 'naggy-convert-terminate-hiragana)
    (define-key map [muhenkan] 'naggy-convert-terminate-hiragana)
    (define-key map [noconvert] 'naggy-convert-terminate-hiragana)
    (define-key map [non-convert] 'naggy-convert-terminate-hiragana)
    (define-key map [S-tab] 'naggy-convert-terminate-katakana)
    (define-key map [xfer] 'naggy-convert-terminate-katakana)
    (define-key map [kanji] 'naggy-convert-terminate-katakana)
    (define-key map [henkan] 'naggy-convert-terminate-katakana)
    (define-key map [henkan-mode] 'naggy-convert-terminate-katakana)
    (define-key map [numbersign] 'naggy-convert-terminate-katakana)
    (define-key map [convert] 'naggy-convert-terminate-katakana)
    (define-key map [S-xfer] 'naggy-convert-terminate-hwkata)
    (define-key map [S-kanji] 'naggy-convert-terminate-hwkata)
    (define-key map [S-henkan] 'naggy-convert-terminate-hwkata)
    (define-key map [S-henkan-mode] 'naggy-convert-terminate-hwkata)
    (define-key map [S-numbersign] 'naggy-convert-terminate-hwkata)
    (define-key map [S-convert] 'naggy-convert-terminate-hwkata)
    map)
  "Keymap for Naggy.")

(defvar naggy-convert-original-string nil)
(defvar naggy-convert-overlay nil)
(defvar naggy-convert-length nil)
(defvar naggy-convert-prev-modification nil)

(put 'naggy-convert-error 'error-conditions '(naggy-convert-error error))
(defun naggy-convert-error (&rest args)
  (signal 'naggy-convert-error (apply 'format args)))

(defvar naggy-convert-converting nil)

(defun naggy-convert-insert-kouho ()
  (let ((pt (overlay-start naggy-convert-overlay))
	(cur (and naggy-vk-current-kouho-number
		  (nth naggy-vk-current-kouho-number naggy-vk-zenkouho))))
    (if (null cur)
	nil
      (goto-char pt)
      (delete-region pt (overlay-end naggy-convert-overlay))
      (insert (nth 0 cur))
      (move-overlay naggy-convert-overlay pt (point))
      (goto-char pt))))

(defun naggy-convert-region (from to)
  "単漢字変換する。"
  (interactive "r")
  (setq naggy-convert-original-string (buffer-substring from to))
  (goto-char from)
  
  (save-match-data
    (let ((s naggy-convert-original-string))
      (if (string-match "#\\([^#]+\\)$" s)
	  (setq naggy-convert-prev-modification (match-string 1 s)))))

  ;; Setup an overlay.
  (if (overlayp naggy-convert-overlay)
      (move-overlay naggy-convert-overlay from to)
    (setq naggy-convert-overlay (make-overlay from to nil nil t))
    (overlay-put naggy-convert-overlay 'face 'highlight))
  (unwind-protect
      (let ((current-input-method-title naggy-convert-input-method-title)
	    (input-method-function nil)
	    (modified-p (buffer-modified-p)))
	;; At first convert the region to the first candidate.
	(setq naggy-vk-zenkouho
	      (naggy-backend-command
	       (list "convert" naggy-convert-original-string)))
	(cond
	 ((null naggy-vk-zenkouho)
	  (naggy-convert-cancel)
	  (beep)
	  0)
	 ((stringp naggy-vk-zenkouho)
	  (goto-char (overlay-start naggy-convert-overlay))
	  (delete-region (overlay-start naggy-convert-overlay)
			 (overlay-end naggy-convert-overlay))
	  (insert naggy-vk-zenkouho)
	  (move-overlay naggy-convert-overlay (point) (point))
	  (- (overlay-start naggy-convert-overlay) from))
	 (t
	  (naggy-vk-make-candidates-from-zenkouho)
	  (setq naggy-vk-current-kouho-number 0)
	  (setq naggy-vk-current-plane 0)
	  (naggy-vk-display-kouho-list)
	  (naggy-convert-insert-kouho)

	  ;; Then, ask users to select a desirable conversion.
	  (force-mode-line-update)
	  (setq naggy-convert-converting t)
	  (while naggy-convert-converting
	    (set-buffer-modified-p modified-p)
	    (let* ((overriding-terminal-local-map naggy-convert-keymap)
		   (help-char nil)
		   (keyseq (read-key-sequence nil))
		   (cmd (lookup-key naggy-convert-keymap keyseq)))
	      (if (commandp cmd)
		  (condition-case err
		      (progn
			(call-interactively cmd))
		    (naggy-convert-error (message "%s" (cdr err)) (beep)))
		;; KEYSEQ is not defined in naggy-convert-keymap.
		;; Let's put the event back.
		(setq unread-input-method-events
		      (append (string-to-list (this-single-command-raw-keys))
			      unread-input-method-events))
		(naggy-convert-cancel))))
	  (naggy-vk-close-kouho-window)
	  (force-mode-line-update)
	  (goto-char (overlay-end naggy-convert-overlay))
	  (- (overlay-start naggy-convert-overlay) from))))
    (delete-overlay naggy-convert-overlay)))

(defun naggy-convert-terminate ()
  "Exit from naggy-convert mode by fixing the current conversion."
  (interactive)
  (goto-char (overlay-end naggy-convert-overlay))
  (move-overlay naggy-convert-overlay (point) (point))
  (setq naggy-convert-converting nil))

(defun naggy-convert-cancel ()
  "Exit from naggy-convert mode by canceling any conversions."
  (interactive)
  (goto-char (overlay-start naggy-convert-overlay))
  (delete-region (overlay-start naggy-convert-overlay)
		 (overlay-end naggy-convert-overlay))
  (insert naggy-convert-original-string)
  (setq naggy-convert-converting nil))

(defun naggy-convert-select ()
  "Select one candidate."
  (interactive)
  (let* ((c (event-basic-type last-input-event))
	 (a (assq c naggy-vk-char-to-pos-tbl)))
    (if (null a)
	(beep)
      (setq c (aref naggy-vk-candidates
		    (% naggy-vk-current-plane
		       (length naggy-vk-candidates))))
      (setq a (aref c (cdr a)))
      (if (null a)
	  (beep)
	(setq naggy-vk-current-kouho-number a)
	(setq naggy-vk-current-cursor nil)
	(naggy-vk-display-kouho-list)
	(naggy-convert-insert-kouho)))))

(defun naggy-convert-select-and-terminate ()
  "Select one candidate and terminate."
  (interactive)
  (let* ((c (event-basic-type last-input-event))
	 (a (assq c naggy-vk-char-to-pos-tbl)))
    (if (null a)
	(beep)
      (setq c (aref naggy-vk-candidates
		    (% naggy-vk-current-plane
		       (length naggy-vk-candidates))))
      (setq a (aref c (cdr a)))
      (if (null a)
	  (beep)
	(setq naggy-vk-current-kouho-number a)
	(setq naggy-vk-current-cursor nil)
	(naggy-convert-insert-kouho)
	(naggy-convert-terminate)))))

(defun naggy-convert-terminate-fullwidth ()
  "Convert to Full-Width Character."
  (interactive)
  (let ((s 
	 (naggy-backend-command (list "translit" "hw-fw"
				      naggy-convert-original-string))))
    (message s)
    (goto-char (overlay-start naggy-convert-overlay))
    (delete-region (overlay-start naggy-convert-overlay)
		   (overlay-end naggy-convert-overlay))
    (insert s)
    (move-overlay naggy-convert-overlay (point) (point))
    (setq naggy-convert-converting nil)))

(defun naggy-convert-terminate-katakana ()
  "Convert to Katakana."
  (interactive)
  (let ((s 
	 (naggy-backend-command (list "translit" "alpha-kata"
				      naggy-convert-original-string))))
    (message s)
    (goto-char (overlay-start naggy-convert-overlay))
    (delete-region (overlay-start naggy-convert-overlay)
		   (overlay-end naggy-convert-overlay))
    (insert s)
    (move-overlay naggy-convert-overlay (point) (point))
    (setq naggy-convert-converting nil)))

(defun naggy-convert-terminate-hiragana ()
  "Convert to Hiragana."
  (interactive)
  (let ((s 
	 (naggy-backend-command (list "translit" "alpha-hira"
				      naggy-convert-original-string))))
    (goto-char (overlay-start naggy-convert-overlay))
    (delete-region (overlay-start naggy-convert-overlay)
		   (overlay-end naggy-convert-overlay))
    (insert s)
    (move-overlay naggy-convert-overlay (point) (point))
    (setq naggy-convert-converting nil)))

(defun naggy-convert-next-page ()
  "次の40個の候補をキーボードに割り当て。"
  (interactive)
  (setq naggy-vk-current-plane (1+ naggy-vk-current-plane))
  (if (null naggy-vk-current-kouho-number)
      (setq naggy-vk-current-kouho-number
	    (naggy-vk-first-kouho-number-of-plane
	     (% naggy-vk-current-plane (length naggy-vk-candidates))))
    (setq naggy-vk-current-kouho-number (1+ naggy-vk-current-kouho-number))
    (if (>= naggy-vk-current-kouho-number (length naggy-vk-zenkouho))
	(setq naggy-vk-current-kouho-number 0)))
  (setq naggy-vk-current-cursor nil)
  (naggy-vk-display-kouho-list)
  (naggy-convert-insert-kouho))

(defun naggy-convert-prev-page ()
  "前の40個の候補をキーボードに割り当て。"
  (interactive)
  (setq naggy-vk-current-plane (1- naggy-vk-current-plane))
  (if (< naggy-vk-current-plane 0)
      (naggy-convert-cancel)
    (if (null naggy-vk-current-kouho-number)
	(setq naggy-vk-current-kouho-number
	      (naggy-vk-first-kouho-number-of-plane
	       (% naggy-vk-current-plane (length naggy-vk-candidates))))
      (setq naggy-vk-current-kouho-number (1- naggy-vk-current-kouho-number))
      (if (< naggy-vk-current-kouho-number 0)
	  (setq naggy-vk-current-kouho-number (1- (length naggy-vk-zenkouho)))))
    (setq naggy-vk-current-cursor nil)
    (naggy-vk-display-kouho-list)
    (naggy-convert-insert-kouho)))

(defun naggy-vk-up-kouho ()
  "仮想キーボード上で上に動く。"
  (interactive)
  (if (< naggy-vk-current-cursor 10)
      (beep)
    (setq naggy-vk-current-cursor
	  (- naggy-vk-current-cursor 10))
    (setq naggy-vk-current-kouho-number nil)
    (naggy-vk-display-kouho-list)
    (naggy-convert-insert-kouho)))

(defun naggy-vk-down-kouho ()
  "仮想キーボード上で下に動く。"
  (interactive)
  (if (>= naggy-vk-current-cursor 30)
      (beep)
    (setq naggy-vk-current-cursor
	  (+ naggy-vk-current-cursor 10))
    (setq naggy-vk-current-kouho-number nil)
    (naggy-vk-display-kouho-list)
    (naggy-convert-insert-kouho)))

(defun naggy-vk-left-kouho ()
  "仮想キーボード上で左に動く。"
  (interactive)
  (if (<= naggy-vk-current-cursor 0)
      (beep)
    (setq naggy-vk-current-cursor
	  (1- naggy-vk-current-cursor))
    (setq naggy-vk-current-kouho-number nil)
    (naggy-vk-display-kouho-list)
    (naggy-convert-insert-kouho)))

(defun naggy-vk-right-kouho ()
  "仮想キーボード上で右に動く。"
  (interactive)
  (if (>= naggy-vk-current-cursor 39)
      (beep)
    (setq naggy-vk-current-cursor
	  (1+ naggy-vk-current-cursor))
    (setq naggy-vk-current-kouho-number nil)
    (naggy-vk-display-kouho-list)
    (naggy-convert-insert-kouho)))

(defun naggy-convert-right-kouho ()
  "仮想キーボード上で右に動く。"
  (interactive)
  (let* ((buf (current-buffer))
	 (vbuf (set-buffer " *naggy-vk-candidates*"))
	 (pt (point))
	 (prop (get-text-property (point) 'kouho-number))
	 (cprop prop))
    (save-excursion
      (while (and (eq prop cprop) (null (eobp)))
	(forward-char 1)
	(setq cprop (or (get-text-property (point) 'kouho-number)
			prop)))
      (if (eq prop cprop)
	  (beep)
	(setq pt (point))
	(set-buffer (car cprop))
	(setq naggy-vk-current-cursor nil)
	(setq naggy-vk-current-kouho-number (cdr cprop))))
    (goto-char pt)
    (if (eq buf vbuf)
	t
      (set-buffer buf)
      (naggy-vk-display-kouho-list)
      (naggy-convert-insert-kouho))))

(defun naggy-convert-left-kouho ()
  "仮想キーボード上で左に動く。"
  (interactive)
  (let* ((buf (current-buffer))
	 (vbuf (set-buffer " *naggy-vk-candidates*"))
	 (pt (point))
	 (prop (get-text-property (point) 'kouho-number))
	 (cprop prop))
    (save-excursion
      (while (and (eq prop cprop) (null (bobp)))
	(backward-char 1)
	(setq cprop (or (get-text-property (point) 'kouho-number)
			prop)))
      (if (eq prop cprop)
	  (beep)
	(setq pt (point))
	(set-buffer (car cprop))
	(setq naggy-vk-current-cursor nil)
	(setq naggy-vk-current-kouho-number (cdr cprop))))
    (goto-char pt)
    (if (eq buf vbuf)
	t
      (set-buffer buf)
      (naggy-vk-display-kouho-list)
      (naggy-convert-insert-kouho))))

(defun naggy-convert-next-kouho ()
  "次の順番の候補。"
  (interactive)
  (if (null naggy-vk-current-kouho-number)
      (setq naggy-vk-current-kouho-number 0)
    (setq naggy-vk-current-kouho-number (1+ naggy-vk-current-kouho-number))
    (if (>= naggy-vk-current-kouho-number (length naggy-vk-zenkouho))
	(setq naggy-vk-current-kouho-number 0)))
  (setq naggy-vk-current-cursor nil)
  (naggy-vk-display-kouho-list)
  (naggy-convert-insert-kouho))

(defun naggy-convert-prev-kouho ()
  "前の順番の候補。"
  (interactive)
  (if (null naggy-vk-current-kouho-number)
      (setq naggy-vk-current-kouho-number 0)
    (setq naggy-vk-current-kouho-number (1- naggy-vk-current-kouho-number))
    (if (< naggy-vk-current-kouho-number 0)
	(setq naggy-vk-current-kouho-number (1- (length naggy-vk-zenkouho)))))
  (setq naggy-vk-current-cursor nil)
  (naggy-vk-display-kouho-list)
  (naggy-convert-insert-kouho))

(defun naggy-vk-mouse-select (ev)
  (interactive "@e")
  (let ((n (get-text-property (posn-point (event-start ev))
			      'kouho-number)))
    (select-frame (window-frame naggy-vk-selected-window))
    (select-window naggy-vk-selected-window)
    (if n
	(progn
	  (setq naggy-vk-current-kouho-number (cdr n))
	  (setq naggy-vk-current-cursor nil)
	  (naggy-vk-display-kouho-list)
	  (naggy-convert-insert-kouho)))))

(defun naggy-vk-mouse-select-and-terminate (ev)
  (interactive "@e")
  (naggy-vk-mouse-select ev)
  (naggy-convert-terminate))

(provide 'quail-naggy)
