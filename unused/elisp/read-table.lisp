;;;; -*- Mode: Lisp; indent-tabs-mode: nil -*-

(in-package "ELISP-INTERNALS")

(defvar *elisp-readtable* (copy-readtable))

(cl:defun read-vector (stream char)
  (when (char= char #\[)
    (coerce (read-delimited-list #\] stream t) 'vector)))

(cl:defun read-character (stream char)
  (if (char= char #\?)
      (read-string-char stream :event)
      (values)))

;;; Note to self. Implement this, head hurts, another day.
;;; Is hopefully mostly done...
(cl:defun emit-character (charspec context)
  (cl:case context
    (:character
     (cl:let ((char (char-code (car (last charspec)))))
       (if (member :control charspec)
           (setf char (mod char 32)))
       (if (member :meta charspec)
           (setf char (+ 128 char)))
       (code-char char)
     ))
    (:event
     (cl:let ((string (with-output-to-string (s)
                        (write-char #\" s)
                        (loop for entity in charspec
                              do (case entity
                                   (:control
                                    (write-char #\C s)
                                    (write-char #\- s))
                                   (:meta
                                    (write-char #\M s)
                                    (write-char #\- s))
                                   (t (write-char entity s))))
                        (write-char #\" s))))
       (with-input-from-string (hackstring string)
         (eval (hemlock-ext::parse-key-fun hackstring #\k 2))))
     )))

(defun read-octal (stream acc level)
  (cl:if (= level 3)
      (code-char acc)
    (let ((char (cl:read-char stream nil stream t)))
      (case char
        ((#\0 #\1 #\2 #\3 #\4 #\5 #\6 #\7)
         (if (and (char= char #\0) (zerop acc))
             (code-char 0)
           (let ((value (position char '(#\0 #\1 #\2 #\3 #\4 #\5 #\6 #\7) :test #'char=)))
             (cl:if (< (+ value (* 8 acc)) 256)
                    (read-octal stream (+ value (* 8 acc)) (1+ level))
                    (progn (unread-char char stream) (code-char acc))))))
        (t (if (zerop acc)
               char
             (progn
               (unread-char char stream)
               (code-char acc))))))))

(cl:defun read-string-char (stream context)
  (cl:let ((char (cl:read-char stream nil stream t)))
    (if (char= char #\\)
        (cl:let ((next (cl:read-char stream nil stream t)))
          (case next
            (#\a (emit-character '(:control #\g) context))
            (#\n (emit-character '(:control #\j) context))
            (#\b (emit-character '(:control #\h) context))
            (#\r (emit-character '(:control #\m) context))
            (#\v (emit-character '(:control #\k) context))
            (#\f (emit-character '(:control #\l) context))
            (#\t (emit-character '(:control #\i) context))
            (#\e (emit-character '(:control #\[) context))
            (#\\ #\\)
            (#\" #\")
            (#\d (emit-character '(#\Rubout) context))
            ((#\C #\M)
             (unread-char next stream)
             (emit-character
              (do ((char (read-char stream) (read-char stream))
                   (expect-dash nil (not expect-dash))
                   (terminate nil)
                   (collection nil))
                  ((or (and expect-dash (not (char= char #\-)))
                       terminate)
                   (unread-char char stream)
                   (nreverse collection))
                (cond (expect-dash)
                      ((char= char #\M)
                       (setf collection (cons :meta collection)))
                      ((char= char #\C)
                       (setf collection (cons :control collection)))
                      (t (setf terminate t)
                         (setf collection (cons char collection)))))
              context))
            ((#\0 #\1 #\2 #\3 #\4 #\5 #\6 #\7)
             (read-octal stream 0 0)
            )))
      char)))

(cl:defun read-string (stream char)
  (if (char= char #\")
      (with-output-to-string (s)
        (loop for char = (read-string-char stream :character)
              if (char= char #\") return s
              else do (cl:write-char char s)))))

(cl:defun sharp-ampersand (stream ignore arg)
  (declare (ignore ignore arg))
  (let ((length (cl:read stream t stream t)))
    (if (not (integerp length))
        (values)
      (let ((string (read stream stream stream t))
            (rv (make-array (list length) :element-type 'bit :initial-element 0)))
        (if (stringp string)
            (progn
              (loop for ix from 0 to (1- length)
                  do (multiple-value-bind (char shift) (truncate ix 8)
                       (let ((val (char-code (char string char))))
                         (unless (zerop (logand val (ash 1 shift)))
                           (setf (aref rv ix) 1)))))
              rv)
          (values))))))

(set-macro-character #\[ 'read-vector nil *elisp-readtable*)
(set-macro-character #\] (get-macro-character #\)) nil *elisp-readtable*)
(set-macro-character #\? 'read-character nil *elisp-readtable*)
(set-macro-character #\" 'read-string nil *elisp-readtable*)
(set-dispatch-macro-character #\# #\& #'sharp-ampersand *elisp-readtable*)
(set-syntax-from-char #\[ #\()
(set-syntax-from-char #\] #\))
