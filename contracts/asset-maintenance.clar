(define-constant contract-owner tx-sender)
(define-constant err-not-found (err u201))
(define-constant err-unauthorized (err u202))
(define-constant err-invalid-interval (err u203))
(define-constant err-already-completed (err u204))
(define-constant err-not-due (err u205))

(define-data-var next-maintenance-id uint u1)

(define-map maintenance-schedules
  { maintenance-id: uint }
  {
    asset-id: uint,
    task-name: (string-ascii 64),
    description: (string-ascii 256),
    interval-blocks: uint,
    last-completed: uint,
    next-due: uint,
    priority: (string-ascii 10),
    assigned-custodian: principal,
    created-by: principal,
    created-at: uint,
    active: bool
  }
)

(define-map maintenance-completions
  { maintenance-id: uint, completion-id: uint }
  {
    completed-by: principal,
    completed-at: uint,
    notes: (string-ascii 256),
    next-scheduled: uint,
    status: (string-ascii 20)
  }
)

(define-map asset-maintenance-count
  { asset-id: uint }
  { total-schedules: uint, overdue-count: uint }
)

(define-map custodian-maintenance-assignments
  { custodian: principal }
  (list 50 uint)
)

(define-read-only (get-maintenance-schedule (maintenance-id uint))
  (map-get? maintenance-schedules { maintenance-id: maintenance-id })
)

(define-read-only (get-maintenance-completion (maintenance-id uint) (completion-id uint))
  (map-get? maintenance-completions { maintenance-id: maintenance-id, completion-id: completion-id })
)

(define-read-only (get-asset-maintenance-summary (asset-id uint))
  (map-get? asset-maintenance-count { asset-id: asset-id })
)

(define-read-only (get-custodian-assignments (custodian principal))
  (default-to (list) (map-get? custodian-maintenance-assignments { custodian: custodian }))
)

(define-read-only (is-maintenance-overdue (maintenance-id uint))
  (match (map-get? maintenance-schedules { maintenance-id: maintenance-id })
    schedule (ok (> stacks-block-height (get next-due schedule)))
    (err err-not-found)
  )
)

(define-read-only (get-days-until-due (maintenance-id uint))
  (match (map-get? maintenance-schedules { maintenance-id: maintenance-id })
    schedule 
      (if (> (get next-due schedule) stacks-block-height)
        (ok (- (get next-due schedule) stacks-block-height))
        (ok u0))
    (err err-not-found)
  )
)

(define-public (create-maintenance-schedule 
    (asset-id uint)
    (task-name (string-ascii 64))
    (description (string-ascii 256))
    (interval-blocks uint)
    (priority (string-ascii 10))
    (assigned-custodian principal))
  (let
    (
      (maintenance-id (var-get next-maintenance-id))
      (current-time stacks-block-height)
      (next-due-time (+ current-time interval-blocks))
    )
    (asserts! (> interval-blocks u0) err-invalid-interval)
    
    (map-set maintenance-schedules
      { maintenance-id: maintenance-id }
      {
        asset-id: asset-id,
        task-name: task-name,
        description: description,
        interval-blocks: interval-blocks,
        last-completed: u0,
        next-due: next-due-time,
        priority: priority,
        assigned-custodian: assigned-custodian,
        created-by: tx-sender,
        created-at: current-time,
        active: true
      }
    )
    
    (update-asset-maintenance-count asset-id true)
    (update-custodian-assignments assigned-custodian maintenance-id)
    
    (var-set next-maintenance-id (+ maintenance-id u1))
    (ok maintenance-id)
  )
)

(define-public (complete-maintenance 
    (maintenance-id uint)
    (notes (string-ascii 256)))
  (let
    (
      (schedule (unwrap! (map-get? maintenance-schedules { maintenance-id: maintenance-id }) err-not-found))
      (current-time stacks-block-height)
      (next-due-time (+ current-time (get interval-blocks schedule)))
      (completion-id current-time)
    )
    (asserts! (or 
                (is-eq tx-sender (get assigned-custodian schedule))
                (is-eq tx-sender (get created-by schedule))
              ) 
              err-unauthorized)
    
    (map-set maintenance-completions
      { maintenance-id: maintenance-id, completion-id: completion-id }
      {
        completed-by: tx-sender,
        completed-at: current-time,
        notes: notes,
        next-scheduled: next-due-time,
        status: "completed"
      }
    )
    
    (map-set maintenance-schedules
      { maintenance-id: maintenance-id }
      (merge schedule {
        last-completed: current-time,
        next-due: next-due-time
      })
    )
    
    (ok true)
  )
)

(define-public (reschedule-maintenance 
    (maintenance-id uint)
    (new-due-date uint)
    (reason (string-ascii 256)))
  (let
    (
      (schedule (unwrap! (map-get? maintenance-schedules { maintenance-id: maintenance-id }) err-not-found))
      (current-time stacks-block-height)
    )
    (asserts! (or 
                (is-eq tx-sender (get assigned-custodian schedule))
                (is-eq tx-sender (get created-by schedule))
              ) 
              err-unauthorized)
    (asserts! (> new-due-date current-time) err-invalid-interval)
    
    (map-set maintenance-schedules
      { maintenance-id: maintenance-id }
      (merge schedule { next-due: new-due-date })
    )
    
    (map-set maintenance-completions
      { maintenance-id: maintenance-id, completion-id: current-time }
      {
        completed-by: tx-sender,
        completed-at: current-time,
        notes: reason,
        next-scheduled: new-due-date,
        status: "rescheduled"
      }
    )
    
    (ok true)
  )
)

(define-public (deactivate-maintenance-schedule (maintenance-id uint))
  (let
    (
      (schedule (unwrap! (map-get? maintenance-schedules { maintenance-id: maintenance-id }) err-not-found))
    )
    (asserts! (is-eq tx-sender (get created-by schedule)) err-unauthorized)
    
    (map-set maintenance-schedules
      { maintenance-id: maintenance-id }
      (merge schedule { active: false })
    )
    
    (update-asset-maintenance-count (get asset-id schedule) false)
    (ok true)
  )
)

(define-public (reassign-maintenance 
    (maintenance-id uint)
    (new-custodian principal))
  (let
    (
      (schedule (unwrap! (map-get? maintenance-schedules { maintenance-id: maintenance-id }) err-not-found))
    )
    (asserts! (is-eq tx-sender (get created-by schedule)) err-unauthorized)
    
    (map-set maintenance-schedules
      { maintenance-id: maintenance-id }
      (merge schedule { assigned-custodian: new-custodian })
    )
    
    (update-custodian-assignments new-custodian maintenance-id)
    (ok true)
  )
)

;; (define-read-only (get-overdue-maintenance-for-asset (asset-id uint))
;;   (let
;;     (
;;       (current-time stacks-block-height)
;;     )
;;     (ok (filter is-overdue-and-matches-asset 
;;          (generate-maintenance-id-list u1 (var-get next-maintenance-id) asset-id)))
;;   )
;; )

(define-read-only (get-upcoming-maintenance-for-custodian (custodian principal) (days-ahead uint))
  (let
    (
      (future-time (+ stacks-block-height days-ahead))
      (assignments (get-custodian-assignments custodian))
    )
    (ok (filter-upcoming-maintenance assignments future-time))
  )
)

(define-private (update-asset-maintenance-count (asset-id uint) (increment bool))
  (let
    (
      (current-count (default-to { total-schedules: u0, overdue-count: u0 } 
                      (map-get? asset-maintenance-count { asset-id: asset-id })))
      (new-total (if increment 
                   (+ (get total-schedules current-count) u1)
                   (- (get total-schedules current-count) u1)))
    )
    (map-set asset-maintenance-count
      { asset-id: asset-id }
      { total-schedules: new-total, overdue-count: (get overdue-count current-count) }
    )
  )
)

(define-private (update-custodian-assignments (custodian principal) (maintenance-id uint))
  (let
    (
      (current-assignments (get-custodian-assignments custodian))
    )
    (map-set custodian-maintenance-assignments
      { custodian: custodian }
      (unwrap-panic (as-max-len? (append current-assignments maintenance-id) u50))
    )
  )
)

(define-private (is-overdue-and-matches-asset (maintenance-id uint))
  (match (map-get? maintenance-schedules { maintenance-id: maintenance-id })
    schedule (and 
               (get active schedule)
               (> stacks-block-height (get next-due schedule)))
    false
  )
)

(define-private (generate-maintenance-id-list (start uint) (end uint) (asset-id uint))
  (list)
)

(define-private (filter-upcoming-maintenance (maintenance-ids (list 50 uint)) (future-time uint))
  (filter is-upcoming-maintenance maintenance-ids)
)

(define-private (is-upcoming-maintenance (maintenance-id uint))
  (match (map-get? maintenance-schedules { maintenance-id: maintenance-id })
    schedule (and 
               (get active schedule)
               (<= stacks-block-height (get next-due schedule)))
    false
  )
)

(define-read-only (get-maintenance-statistics)
  (let
    (
      (total-schedules (var-get next-maintenance-id))
    )
    (ok {
      total-maintenance-schedules: (- total-schedules u1),
      current-block: stacks-block-height
    })
  )
)