;; Asset Warranty & Claims Management Contract
;; Handles warranty registration, claims processing, and vendor management

(define-constant contract-owner tx-sender)
(define-constant err-not-found (err u301))
(define-constant err-unauthorized (err u302))
(define-constant err-warranty-expired (err u303))
(define-constant err-invalid-claim (err u304))
(define-constant err-claim-already-filed (err u305))
(define-constant err-vendor-not-registered (err u306))
(define-constant err-warranty-already-exists (err u307))

(define-data-var next-warranty-id uint u1)
(define-data-var next-claim-id uint u1)
(define-data-var next-vendor-id uint u1)

;; Vendor registry for warranty providers
(define-map vendors
  { vendor-id: uint }
  {
    name: (string-ascii 64),
    contact-email: (string-ascii 100),
    phone: (string-ascii 20),
    address: (string-ascii 200),
    warranty-types: (list 10 (string-ascii 32)),
    active: bool,
    registered-by: principal,
    registered-at: uint
  }
)

;; Asset warranty registrations
(define-map asset-warranties
  { warranty-id: uint }
  {
    asset-id: uint,
    vendor-id: uint,
    warranty-type: (string-ascii 32),
    coverage-description: (string-ascii 256),
    start-date: uint,
    end-date: uint,
    terms: (string-ascii 500),
    purchase-price: uint,
    warranty-number: (string-ascii 64),
    registered-by: principal,
    registered-at: uint,
    active: bool
  }
)

;; Warranty claims tracking
(define-map warranty-claims
  { claim-id: uint }
  {
    warranty-id: uint,
    asset-id: uint,
    vendor-id: uint,
    claim-type: (string-ascii 32),
    issue-description: (string-ascii 500),
    claim-amount: uint,
    filed-by: principal,
    filed-at: uint,
    status: (string-ascii 20),
    resolution-notes: (string-ascii 500),
    resolved-by: (optional principal),
    resolved-at: (optional uint),
    approved-amount: (optional uint)
  }
)

;; Asset warranty lookup for quick access
(define-map asset-warranty-index
  { asset-id: uint }
  (list 10 uint)
)

;; Vendor claim statistics
(define-map vendor-claim-stats
  { vendor-id: uint }
  {
    total-claims: uint,
    approved-claims: uint,
    denied-claims: uint,
    total-claim-amount: uint,
    total-approved-amount: uint
  }
)

;; Register a new vendor
(define-public (register-vendor 
    (name (string-ascii 64))
    (contact-email (string-ascii 100))
    (phone (string-ascii 20))
    (address (string-ascii 200))
    (warranty-types (list 10 (string-ascii 32))))
  (let
    (
      (vendor-id (var-get next-vendor-id))
      (current-time stacks-block-height)
    )
    (map-set vendors
      { vendor-id: vendor-id }
      {
        name: name,
        contact-email: contact-email,
        phone: phone,
        address: address,
        warranty-types: warranty-types,
        active: true,
        registered-by: tx-sender,
        registered-at: current-time
      }
    )
    
    ;; Initialize vendor claim statistics
    (map-set vendor-claim-stats
      { vendor-id: vendor-id }
      {
        total-claims: u0,
        approved-claims: u0,
        denied-claims: u0,
        total-claim-amount: u0,
        total-approved-amount: u0
      }
    )
    
    (var-set next-vendor-id (+ vendor-id u1))
    (ok vendor-id)
  )
)

;; Register warranty for an asset
(define-public (register-asset-warranty 
    (asset-id uint)
    (vendor-id uint)
    (warranty-type (string-ascii 32))
    (coverage-description (string-ascii 256))
    (start-date uint)
    (end-date uint)
    (terms (string-ascii 500))
    (purchase-price uint)
    (warranty-number (string-ascii 64)))
  (let
    (
      (warranty-id (var-get next-warranty-id))
      (current-time stacks-block-height)
      (existing-warranties (default-to (list) (map-get? asset-warranty-index { asset-id: asset-id })))
    )
    ;; Verify vendor exists and is active
    (let
      (
        (vendor (unwrap! (map-get? vendors { vendor-id: vendor-id }) err-vendor-not-registered))
      )
      (asserts! (get active vendor) err-vendor-not-registered)
    )
    
    ;; Validate warranty dates
    (asserts! (> end-date start-date) err-invalid-claim)
    
    ;; Register the warranty
    (map-set asset-warranties
      { warranty-id: warranty-id }
      {
        asset-id: asset-id,
        vendor-id: vendor-id,
        warranty-type: warranty-type,
        coverage-description: coverage-description,
        start-date: start-date,
        end-date: end-date,
        terms: terms,
        purchase-price: purchase-price,
        warranty-number: warranty-number,
        registered-by: tx-sender,
        registered-at: current-time,
        active: true
      }
    )
    
    ;; Update asset warranty index
    (map-set asset-warranty-index
      { asset-id: asset-id }
      (unwrap-panic (as-max-len? (append existing-warranties warranty-id) u10))
    )
    
    (var-set next-warranty-id (+ warranty-id u1))
    (ok warranty-id)
  )
)

;; File a warranty claim
(define-public (file-warranty-claim 
    (warranty-id uint)
    (claim-type (string-ascii 32))
    (issue-description (string-ascii 500))
    (claim-amount uint))
  (let
    (
      (warranty (unwrap! (map-get? asset-warranties { warranty-id: warranty-id }) err-not-found))
      (claim-id (var-get next-claim-id))
      (current-time stacks-block-height)
    )
    ;; Verify warranty is active and not expired
    (asserts! (get active warranty) err-warranty-expired)
    (asserts! (<= current-time (get end-date warranty)) err-warranty-expired)
    (asserts! (>= current-time (get start-date warranty)) err-invalid-claim)
    
    ;; File the claim
    (map-set warranty-claims
      { claim-id: claim-id }
      {
        warranty-id: warranty-id,
        asset-id: (get asset-id warranty),
        vendor-id: (get vendor-id warranty),
        claim-type: claim-type,
        issue-description: issue-description,
        claim-amount: claim-amount,
        filed-by: tx-sender,
        filed-at: current-time,
        status: "pending",
        resolution-notes: "",
        resolved-by: none,
        resolved-at: none,
        approved-amount: none
      }
    )
    
    ;; Update vendor statistics
    (update-vendor-claim-stats (get vendor-id warranty) claim-amount false none)
    
    (var-set next-claim-id (+ claim-id u1))
    (ok claim-id)
  )
)

;; Process warranty claim (vendor or authorized personnel only)
(define-public (process-warranty-claim 
    (claim-id uint)
    (status (string-ascii 20))
    (resolution-notes (string-ascii 500))
    (approved-amount (optional uint)))
  (let
    (
      (claim (unwrap! (map-get? warranty-claims { claim-id: claim-id }) err-not-found))
      (warranty (unwrap! (map-get? asset-warranties { warranty-id: (get warranty-id claim) }) err-not-found))
      (vendor (unwrap! (map-get? vendors { vendor-id: (get vendor-id claim) }) err-not-found))
      (current-time stacks-block-height)
    )
    ;; Authorization check: vendor or warranty registrar
    (asserts! (or 
                (is-eq tx-sender (get registered-by vendor))
                (is-eq tx-sender (get registered-by warranty))
              ) 
              err-unauthorized)
    
    ;; Update claim status
    (map-set warranty-claims
      { claim-id: claim-id }
      (merge claim {
        status: status,
        resolution-notes: resolution-notes,
        resolved-by: (some tx-sender),
        resolved-at: (some current-time),
        approved-amount: approved-amount
      })
    )
    
    ;; Update vendor statistics based on resolution
    (if (is-eq status "approved")
      (update-vendor-claim-stats (get vendor-id claim) u0 true approved-amount)
      (if (is-eq status "denied")
        (update-vendor-claim-stats (get vendor-id claim) u0 false none)
        true
      )
    )
    
    (ok true)
  )
)

;; Check if asset has active warranty coverage
(define-read-only (check-warranty-coverage (asset-id uint))
  (let
    (
      (warranty-ids (default-to (list) (map-get? asset-warranty-index { asset-id: asset-id })))
      (current-time stacks-block-height)
    )
    (ok (fold check-warranty-active warranty-ids false))
  )
)

;; Get warranty information
(define-read-only (get-warranty (warranty-id uint))
  (map-get? asset-warranties { warranty-id: warranty-id })
)

;; Get claim information
(define-read-only (get-claim (claim-id uint))
  (map-get? warranty-claims { claim-id: claim-id })
)

;; Get vendor information
(define-read-only (get-vendor (vendor-id uint))
  (map-get? vendors { vendor-id: vendor-id })
)

;; Get asset warranties
(define-read-only (get-asset-warranties (asset-id uint))
  (default-to (list) (map-get? asset-warranty-index { asset-id: asset-id }))
)

;; Get vendor claim statistics
(define-read-only (get-vendor-statistics (vendor-id uint))
  (map-get? vendor-claim-stats { vendor-id: vendor-id })
)

;; Private function to update vendor claim statistics
(define-private (update-vendor-claim-stats (vendor-id uint) (claim-amount uint) (is-resolution bool) (approved-amount (optional uint)))
  (let
    (
      (current-stats (default-to 
                      { total-claims: u0, approved-claims: u0, denied-claims: u0, total-claim-amount: u0, total-approved-amount: u0 }
                      (map-get? vendor-claim-stats { vendor-id: vendor-id })))
    )
    (if is-resolution
      ;; This is a claim resolution
      (match approved-amount
        amount
          ;; Approved claim
          (map-set vendor-claim-stats
            { vendor-id: vendor-id }
            {
              total-claims: (get total-claims current-stats),
              approved-claims: (+ (get approved-claims current-stats) u1),
              denied-claims: (get denied-claims current-stats),
              total-claim-amount: (get total-claim-amount current-stats),
              total-approved-amount: (+ (get total-approved-amount current-stats) amount)
            }
          )
        ;; Denied claim
        (map-set vendor-claim-stats
          { vendor-id: vendor-id }
          (merge current-stats { denied-claims: (+ (get denied-claims current-stats) u1) })
        )
      )
      ;; This is a new claim filing
      (map-set vendor-claim-stats
        { vendor-id: vendor-id }
        {
          total-claims: (+ (get total-claims current-stats) u1),
          approved-claims: (get approved-claims current-stats),
          denied-claims: (get denied-claims current-stats),
          total-claim-amount: (+ (get total-claim-amount current-stats) claim-amount),
          total-approved-amount: (get total-approved-amount current-stats)
        }
      )
    )
  )
)

;; Private function to check if a warranty is active
(define-private (check-warranty-active (warranty-id uint) (acc bool))
  (if acc
    true
    (match (map-get? asset-warranties { warranty-id: warranty-id })
      warranty
        (and 
          (get active warranty)
          (<= stacks-block-height (get end-date warranty))
          (>= stacks-block-height (get start-date warranty))
        )
      false
    )
  )
)



