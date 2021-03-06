(define (mass->logmass mass)
  (if (= mass 0)
      -inf
      (log mass)))
(define logmass->mass exp)

(define *pspec-table* (make-weak-eq-hash-table))

(define-structure
  pspec
  sampler
  logmass-function)

;; Note: it is not currently supported to nest calls to other
;; probabilistic operators within an operator's sampler.

(define (pspec-sample spec #!optional args)
  (apply (pspec-sampler spec)
         (if (default-object? args)
             '()
             args)))
(define (pspec-logmass spec args x)
  ((apply (pspec-logmass-function spec) args) x))
(define (pspec-mass spec args x)
  (logmass->mass (pspec-logmass spec args x)))

;; Note: never make one of these without also populating *pspec-table*
(define-structure
  (prob-operator-instance
   (constructor make-prob-operator-instance
                (pspec continuation args
                       #!optional name constrained?)))
  pspec
  continuation
  args
  (name '())
  (constrained? #f))

(define (instance-sample instance)
  (pspec-sample (prob-operator-instance-pspec instance)
                (prob-operator-instance-args instance)))

(define (instance-logmass instance x)
  (pspec-logmass (prob-operator-instance-pspec instance)
                 (prob-operator-instance-args instance)
                 x))

(define (instance-mass instance x)
  (logmass->mass (instance-logmass instance x)))

(define (pspec->operator pspec #!optional name constrained?)
  (let ((out
         (lambda args
           (call-with-current-continuation
            (lambda (k)
              (add-to-sampler
               (make-prob-operator-instance
                ;; this does the right thing when some args aren't
                ;; supplied
                pspec k args name constrained?)))))))
    (hash-table/put! *pspec-table* out pspec)
    out))

(define (make-operator args)
  (pspec->operator (apply make-pspec args)))

;; Note: right now (named-operator (constrained foo)) doesn't do what
;; you might expect
(define (named-operator operator name)
  (pspec->operator
   (hash-table/get *pspec-table* operator '())
   name))

;; A value tied to a certain branch of the computation. Once the
;; sampler is no longer exploring the branch, the recorded value is no
;; longer meaningful.
(define-structure
  (local-computation-record
   (constructor make-local-computation-record (value)))
  value
  (computation-state (sampler-computation-state)))

(define (local-computation-record-stale? record)
  (not (sampler-in-computation?
        (local-computation-record-computation-state record))))

(define (mem f)
  (let ((mem-table (make-equal-hash-table)))
    (lambda args
      (let* ((default-value (list 'default))
             (recorded-out
              (hash-table/get mem-table args default-value)))
        (if (or
             (eq? recorded-out default-value)
             (local-computation-record-stale? recorded-out))
            (let ((value (apply f args)))
              (hash-table/put! mem-table args
                               (make-local-computation-record value))
              value)
            (local-computation-record-value recorded-out))))))


(define add-to-sampler
  (lambda (operator-instance)
    ((prob-operator-instance-continuation operator-instance)
     (instance-sample operator-instance))))

(define *sampler-state* #f)

(define (observe observed)
  (if observed
      'ok
      (error "Inconsistent observation outside of sampling")))

(define (constrain operator value)
  (pspec->operator
   (make-pspec
    (lambda args value)
    (pspec-logmass-function
     (hash-table/get *pspec-table* operator '())))
   '()
   #t))

(define *null-computation-state* (list '*null-computation-state*))

(define sampler-computation-state
  (lambda () *null-computation-state*))

(define sampler-in-computation?
  (lambda (state) (eq? state *null-computation-state*)))
