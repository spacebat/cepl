(in-package :cgl)

;; {TODO} need to put this in some macros utils package
(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun function-formp (x) x))

;; This macro runs the shader pipeline and returns the currently bound fbo
;; This with-bind-fbo macro will shadow the map-g macro in order to use the
;; hard-bind-fbo argument and optimize the return of the current-fbo
;;
;; We have to make %current-fbo special so that we can have a map-g inside
;; a function that was called from inside a block in which with-bind-fbo
;; was used.
(defmacro %map-g (hard-bind-fbo pipeline-func stream uniforms)
  (assert (function-formp pipeline-func))
  (let ((pipeline-name (second pipeline-func)))
    `(progn
       (,(symb-package :cgl :$$-dispatch- pipeline-name) ,stream ,@uniforms)
       ,(if hard-bind-fbo
            hard-bind-fbo
            'cgl::%current-fbo))))


;; This is a passthrough macro that exists so that with-bind-fbo can shadow it
(defmacro map-g (pipeline-func stream &rest uniforms)
  `(%map-g nil ,pipeline-func ,stream ,uniforms))

;; Ok got some macro madness going on here so I want to be clear what
;; is happening. Here are some facts
;;
;; - Map-G runs a pipeline with the input and then returns a framebuffer
;; - the current framebuffer is in the %current-fbo var.
;;
;; Given that, if we are inside a with-bind-fbo, we know what the the
;; fbo will be, then we can return the local var and not have to query
;; the special var which would have an overhead associated with it.
;; Q: is this moot because of having to set %current-fbo
;; A: I hope not, I think given correct settings the compiler may be able
;;    to optimize away this let as nothing uses it.
(defmacro with-bind-fbo ((fbo &key (target :framebuffer) (unbind t)
                              (with-viewport t) (attachment-for-size 0)
                              (draw-buffers t))
                         &body body)
  (labels ((inject-map-g-form (fbo-symbol)
             (subst fbo-symbol 'a
                    ``(%map-g a ,pipeline-func ,stream ,uniforms))))
    (let ((once-fbo (gensym "once-fbo")))
      `(macrolet ((map-g (pipeline-func stream &rest uniforms)
                    ,(inject-map-g-form once-fbo)))
         (let* ((,once-fbo ,fbo)
                (%current-fbo ,once-fbo))
           (%bind-fbo ,once-fbo ,target)
           ,(when draw-buffers
                  (cond ((equal draw-buffers t) `(%fbo-draw-buffers ,once-fbo))
                        ((listp draw-buffers)
                         (%write-draw-buffer-pattern-call draw-buffers))))
           (prog1 (,@(if with-viewport
                         `(with-fbo-viewport (,once-fbo ,attachment-for-size))
                         '(progn))
                     ,@body)
             (when ,unbind (%unbind-fbo))))))))

;; EXAMPLES
;;
;; (map-g #'test a :tex tx)
;;
;; (macroexpand-dammit:macroexpand-dammit
;;       '(with-bind-fbo (some-fbo)
;;         (let ((jam (map-g #'test a :tex tx)))
;;           (print jam))))


(defun %write-draw-buffer-pattern-call (pattern)
  "This plays with the dispatch call from compose-pipelines
   The idea is that the dispatch func can preallocate one array
   with the draw-buffers patterns for ALL the passes in it, then
   we just upload from that one block of memory.
   All of this can be decided at compile time. It's gonna go fast!"
  (destructuring-bind (pointer len) pattern
    `(progn (%gl:draw-buffers ,len ,pointer)
            (cffi:incf-pointer
             ,pointer (* ,len (foreign-type-size 'cl-opengl-bindings:enum))))))
