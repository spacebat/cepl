;; In this file I'm looking at the main loop and thinking
;; about how I want to do event handling. I want to have the 
;; nuts and bolts of the main loop up front where I can see it
;; to allow quick changes and also just so you can really grasp
;; what is happening. It just feels like the main loop is too 
;; important to be left to magic!

(in-package :cepl-examples)

;; Globals - Too damn many of them, but its in keeping with
;;           the tutorials online
(defparameter *prog-1* nil)
(defparameter *frustrum-scale* nil)
(defparameter *cam-clip-matrix* nil)
(defparameter *shaders* nil)
(defparameter *vertex-data-list* nil)
(defparameter *vertex-data-gl* nil)
(defparameter *index-data-list* nil)
(defparameter *index-data-gl* nil)
(defparameter *vert-buffer* nil)
(defparameter *index-buffer* nil)
(defparameter *buffer-layout* nil)
(defparameter *vao-1* nil)
(defparameter *entities* nil)
(defparameter *camera* nil)


;; Define data formats 
(cgl:define-interleaved-attribute-format vert-data 
  (:type :float :components (x y z))
  (:type :float :components (r g b a)))

;; The entities used in this demo
(defstruct entity 
  (stream nil)
  (position (v:make-vector 0.0 0.0 -20.0))
  (rotation (v:make-vector 0.0 0.0 0.0))
  (scale (v:make-vector 1.0 1.0 1.0))
  (left nil)
  (right nil)
  (forward nil)
  (backward nil))

(defstruct camera 
  (position (v:make-vector 0.0 0.0 0.0))
  (look-direction (v:make-vector 0.0 0.0 -1.0))
  (up-direction (v:make-vector 0.0 1.0 0.0)))

(defun point-camera-at (camera point)
  (setf (camera-look-direction camera)
	(v:normalize (v:- point (camera-position camera))))
  camera)

(defun calculate-cam-look-at-w2c-matrix (camera)
  (let* ((look-dir (v:normalize (camera-look-direction camera)))
	 (up-dir (v:normalize (camera-up-direction camera)))
	 (right-dir (v:normalize (v:cross look-dir up-dir)))
	 (perp-up-dir (v:cross right-dir look-dir))
	 (rot-matrix (m4:transpose
		      (m4::rotation-from-matrix3
		       (m3:make-from-rows right-dir
					  perp-up-dir
					  (v:1- (v:make-vector 0.0 0.0 0.0)
						look-dir)))))
	 (trans-matrix (m4:translation 
			(v:1- (v:make-vector 0.0 0.0 0.0)
			      (camera-position camera)))))
    (m4:m* rot-matrix trans-matrix)))

(defun resolve-cam-position (sphere-cam-rel-pos cam-target)
  (let* ((phi (* base-maths:+one-degree-in-radians+
		 (v-x sphere-cam-rel-pos)))
	 (theta (* base-maths:+one-degree-in-radians+
		   (+ 90.0 (v-y sphere-cam-rel-pos))))
	 (sin-theta (sin theta))
	 (con-theta (cos theta))
	 (sin-phi (sin phi))
	 (cos-phi (cos phi))
	 (dir-to-cam (v:make-vector (* sin-theta cos-phi)
			con-theta
			(* sin-theta sin-phi))))
    (v:+ cam-target (v:* dir-to-cam (v-z sphere-cam-rel-pos)))))

;----------------------------------------------

(defun init () 
  (setf *camera* (make-camera :position (v:make-vector 0.0 0.0 0.0)))
  (setf *shaders* (mapcar #'cgl:make-shader `("7.vert" "7.frag")))
  (setf *prog-1* (cgl:make-program *shaders*))
  (setf *frustrum-scale* 
	(cepl-camera:calculate-frustrum-scale 45.0))
  (setf *cam-clip-matrix* (cepl-camera:make-cam-clip-matrix 
			   *frustrum-scale*))
  (cgl:set-program-uniforms *prog-1* :cameratoclipmatrix *cam-clip-matrix*)

  ;;setup data 
  (let ((monkey-data 
	 (first (model-parsers:parse-obj-file "7.obj"))))
    (setf *vertex-data-list* (gethash :vertices monkey-data))
    (setf *index-data-list* (gethash :faces monkey-data)))

  (setf *vertex-data-list* (mapcar 
			    #'(lambda (x) 
				(list x (list (random 1.0) (random 1.0) (random 1.0) 1.0))) *vertex-data-list*))

  (setf *index-data-list* 
	(loop for face in *index-data-list*
	   append (mapcar #'car (subseq face 0 3))))

  ;; put in glarrays
  (setf *vertex-data-gl* 
	(cgl:alloc-array-gl 'vert-data 
			    (length *vertex-data-list*)))
  (cgl:destructuring-populate *vertex-data-gl* 
			      *vertex-data-list*)
  (setf *index-data-gl* 
	  (cgl:alloc-array-gl :short
			      (length *index-data-list*)))
  (loop for index in *index-data-list*
       for i from 0
       do (setf (cgl::aref-gl *index-data-gl* i) index))

  ;;setup buffers
  (setf *vert-buffer* (cgl:gen-buffer))
  (setf *buffer-layout*
  	(cgl:buffer-data *vert-buffer* *vertex-data-gl*))

  (setf *index-buffer* (cgl:gen-buffer))
  (cgl:buffer-data *index-buffer* *index-data-gl* 
		   :buffer-type :element-array-buffer)

  ;;setup vaos
  (setf *vao-1* (cgl:make-vao *buffer-layout* *index-buffer*))

  ;;create entities
  (let ((stream (cgl:make-gl-stream 
  			      :vao *vao-1*
  			      :length (length *index-data-list*)
  			      :element-type :unsigned-short)))
    (setf *entities* 
	  (list 
	   (make-entity :position (v:make-vector 0.0 0.0 -15.0)
			:rotation (v:make-vector -1.57079633 0.0 0.0)
			:stream stream))))
  
  ;;set options
  (cgl::clear-color 0.0 0.0 0.0 0.0)
  (gl:enable :cull-face)
  (gl:cull-face :back)
  (gl:front-face :ccw)
  (gl:enable :depth-test)
  (gl:depth-mask :true)
  (gl:depth-func :lequal)
  (gl:depth-range 0.0 1.0)
  (gl:enable :depth-clamp))  

(defun entity-matrix (entity)
  (reduce #'m4:m* (list
		   (m4:translation (entity-position entity))
		   (m4:rotation-from-euler (entity-rotation entity))
		   (m4:scale (entity-scale entity)))))


;----------------------------------------------

(defun draw ()
  (update-entity (first *entities*))
  (cgl::clear-depth 1.0)
  (cgl::clear :color-buffer-bit :depth-buffer-bit)

  (cgl:set-program-uniforms *prog-1* :worldtocameramatrix 
			    (calculate-cam-look-at-w2c-matrix
			     *camera*))
  
  (loop for entity in *entities*
       do (cgl::draw-streams *prog-1* (list (entity-stream entity)) 
  		   :modeltoworldmatrix (entity-matrix entity)))
  (gl:flush)
  (sdl:update-display))

(defun reshape (width height)  
  (setf (matrix4:melm *cam-clip-matrix* 0 0)
  	(* *frustrum-scale* (/ height width)))
  (setf (matrix4:melm *cam-clip-matrix* 1 1)
  	*frustrum-scale*)
  (cgl:set-program-uniforms *prog-1* 
			    :cameratoclipmatrix *cam-clip-matrix*)
  (cgl::viewport 0 0 width height))

(defun update-swank ()
  (let ((connection (or swank::*emacs-connection*
			(swank::default-connection))))
    (when connection
      (swank::handle-requests connection t))))

(defun update-entity (entity)
  (when (entity-right entity)
    (setf (entity-rotation entity) 
	  (v:+ (entity-rotation entity)
	       (v:make-vector 0.00 -0.05 0.00))))
  (when (entity-left entity)
    (setf (entity-rotation entity) 
	  (v:+ (entity-rotation entity)
	       (v:make-vector 0.00 0.05 0.00))))
  (when (entity-forward entity)
    (setf (entity-position entity) 
	  (v:+ (entity-position entity)
	       (v:make-vector 0.00 0.00 -0.20))))
  (when (entity-backward entity)
    (setf (entity-position entity) 
	  (v:+ (entity-position entity)
	       (v:make-vector 0.00 0.00 0.20)))))

;----------------------------------------------

(defun key-name (sdl-event)
  (cffi:foreign-slot-value (cffi:foreign-slot-pointer 
			    sdl-event
			    'sdl-cffi::sdl-keyboard-event
			    'sdl-cffi::keysym)
                           'sdl-cffi::sdl-key-sym 'sdl-cffi::sym))

(defun forwardp (event)
  (and (eq (sdl:event-type event) :key-down-event)
       (eq (key-name event) :sdl-key-w)))

(defun backwardp (event)
  (and (eq (sdl:event-type event) :key-down-event)
       (eq (key-name event) :sdl-key-s)))

(defun rightp (event)
  (and (eq (sdl:event-type event) :key-down-event)
       (eq (key-name event) :sdl-key-a)))

(defun leftp (event)
  (and (eq (sdl:event-type event) :key-down-event)
       (eq (key-name event) :sdl-key-d)))

(defun forward-upp (event)
  (and (eq (sdl:event-type event) :key-up-event)
       (eq (key-name event) :sdl-key-w)))

(defun backward-upp (event)
  (and (eq (sdl:event-type event) :key-up-event)
       (eq (key-name event) :sdl-key-s)))

(defun right-upp (event)
  (and (eq (sdl:event-type event) :key-up-event)
       (eq (key-name event) :sdl-key-a)))

(defun left-upp (event)
  (and (eq (sdl:event-type event) :key-up-event)
       (eq (key-name event) :sdl-key-d)))

;; this wont do as when expired it stops working
;; (let ((event-cache nil)
;;       (target '(1 2 3 4)))
;;   (tlambda (make-itime-cache) (beforep !time 5000) (key)
;;     (if (eq key (car event-cache))
;; 	(progn 
;; 	  (setf event-cache (cdr event-cache))
;; 	  (when (null event-cache)
;; 	    (setf event-cache target)
;; 	    t))
;; 	(progn
;; 	  (setf event-cache target)
;; 	  nil))))

(defun make-timed-event-emmiter (event target-sequence time-limit)
  (let ((event-cache nil)
	(target target-sequence)
	(time-cache (make-itime-cache)))
    (lambda (key)
      (if (and (eq key (car event-cache))
	       (beforep time-cache time-limit))
	  (progn
	    (setf event-cache (cdr event-cache))
	    (when (eq event-cache nil)
	      event))
	  (progn
	    (setf event-cache target)
	    (funcall time-cache :reset)
	    nil)))))

(defun event-type-tester (type)
  (lambda (event) (eq (sdl:event-type event) type)))

(defun make-event-emitter (event-symb target-eventp)
  (lambda (event)
    (when (funcall target-eventp event)
      event-symb)))

(defun get-events (event-emitters)
  (loop for event in (collect-sdl-events)
     append (loop for emmiter in event-emitters
		 collect (funcall emmiter event))))
 

;----------------------------------------------


;; [TODO] Should look for quit event and just return that if found.
(defun collect-sdl-events ()
  (let ((x (sdl:new-event)))
    (LOOP UNTIL (= 0 (LISPBUILDER-SDL-CFFI::SDL-POLL-EVENT x))
       collect x)))


;; currently anything changed in here is going to need a restart
;; this is obviously unacceptable and will be fixed when I can
;; extract the sdl event handling from their loop system.
(defun run-demo ()
  (sdl:with-init ()
    (sdl:window
     640 480
     :opengl t
     :resizable t
     :flags sdl-cffi::sdl-opengl
     :opengl-attributes '((:sdl-gl-doublebuffer 1)
			  (:sdl-gl-alpha-size 0)
			  (:sdl-gl-depth-size 16)
			  (:sdl-gl-stencil-size 8)
			  (:sdl-gl-red-size 8)
			  (:sdl-gl-green-size 8)
			  (:sdl-gl-blue-size 8)
			  (:SDL-GL-SWAP-CONTROL 1)))
    (setf (sdl:frame-rate) 0)
    (init)
    (reshape 640 480)
    (setf cl-opengl-bindings:*gl-get-proc-address* #'sdl-cffi::sdl-gl-get-proc-address)
    ;; I've been tearing apart sdl's 'with-events' macro to see
    ;; what they include in the main loop. I'm trying to make 
    ;; as thin a layer between the user and the code as possible
    ;; do I feel that the 'with-events' macro has a little too
    ;; much magic.
    ;; Below I have ripped out the parts I need to make this 
    ;; function in the same way as 7.lisp.
    ;; I am currently experimenting with time in the protocode
    ;; folder, and as soon as I have nailed that down I will
    ;; and player controls to this (or prehaps another) example.
    (let ((draw-timer (make-time-buffer))
	  (draw-stepper (make-stepper (/ 1000.0 60)))
	  (running t)
	  (event-emmiters `(,(make-event-emitter 
			      :quit
			      (event-type-tester :quit-event))
			    ,(make-event-emitter
			      :forward
			      #'forwardp)
			    ,(make-event-emitter
			      :backward
			      #'backwardp)
			    ,(make-event-emitter
			      :left
			      #'leftp)
			    ,(make-event-emitter
			      :right
			      #'rightp)
			    ,(make-event-emitter
			      :forward-up
			      #'forward-upp)
			    ,(make-event-emitter
			      :backward-up
			      #'backward-upp)
			    ,(make-event-emitter
			      :left-up
			      #'left-upp)
			    ,(make-event-emitter
			      :right-up
			      #'right-upp))))
      (do-until (not running)
	(dolist (event (get-events event-emmiters))
	  (case event
	    (:quit (setf running nil))
	    (:forward (forward))
	    (:backward (backward))
	    (:left (left))
	    (:right (right))
	    (:forward-up (forward-up))
	    (:backward-up (backward-up))
	    (:left-up (left-up))
	    (:right-up (right-up))))
	(on-step-call (draw-stepper 
		       (funcall draw-timer))
	  (continuable (update-swank))
	  (continuable (draw)))
	(sdl::process-audio)))))

(defun forward ()
  (let ((entity (first *entities*)))
    (setf (entity-forward entity) t)))

(defun backward ()
  (let ((entity (first *entities*)))
    (setf (entity-backward entity) t)))

(defun left ()
  (let ((entity (first *entities*)))
    (setf (entity-left entity) t)))

(defun right ()
  (let ((entity (first *entities*)))
    (setf (entity-right entity) t)))

(defun forward-up ()
  (let ((entity (first *entities*)))
    (setf (entity-forward entity) nil)))

(defun backward-up ()
  (let ((entity (first *entities*)))
    (setf (entity-backward entity) nil)))

(defun left-up ()
  (let ((entity (first *entities*)))
    (setf (entity-left entity) nil)))

(defun right-up ()
  (let ((entity (first *entities*)))
    (setf (entity-right entity) nil)))