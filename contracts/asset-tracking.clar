(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-already-exists (err u103))
(define-constant err-invalid-status (err u104))
(define-constant err-not-custodian (err u105))

(define-data-var next-asset-id uint u1)

(define-map assets
  { asset-id: uint }
  {
    name: (string-ascii 64),
    description: (string-ascii 256),
    owner: principal,
    current-custodian: principal,
    status: (string-ascii 20),
    location: (string-ascii 100),
    created-at: uint,
    last-updated: uint
  }
)

(define-map asset-history
  { asset-id: uint, timestamp: uint }
  {
    custodian: principal,
    status: (string-ascii 20),
    location: (string-ascii 100),
    notes: (string-ascii 256)
  }
)

(define-map custodians
  { custodian: principal }
  {
    name: (string-ascii 64),
    role: (string-ascii 32),
    active: bool,
    registered-at: uint
  }
)

(define-map asset-custodians
  { asset-id: uint, custodian: principal }
  { authorized: bool }
)

(define-read-only (get-asset (asset-id uint))
  (map-get? assets { asset-id: asset-id })
)

(define-read-only (get-asset-history (asset-id uint) (timestamp uint))
  (map-get? asset-history { asset-id: asset-id, timestamp: timestamp })
)

(define-read-only (get-custodian (custodian principal))
  (map-get? custodians { custodian: custodian })
)

(define-read-only (is-authorized-custodian (asset-id uint) (custodian principal))
  (default-to false (get authorized (map-get? asset-custodians { asset-id: asset-id, custodian: custodian })))
)

(define-read-only (get-next-asset-id)
  (var-get next-asset-id)
)

(define-public (register-custodian (name (string-ascii 64)) (role (string-ascii 32)))
  (begin
    (asserts! (or (is-eq tx-sender contract-owner) 
                 (is-none (map-get? custodians { custodian: tx-sender }))) 
             err-already-exists)
    
    (map-set custodians
      { custodian: tx-sender }
      {
        name: name,
        role: role,
        active: true,
        registered-at: stacks-block-height
      }
    )
    (ok true)
  )
)

(define-public (create-asset (name (string-ascii 64)) (description (string-ascii 256)) (location (string-ascii 100)))
  (let
    (
      (asset-id (var-get next-asset-id))
      (current-time stacks-block-height)
    )
    (asserts! (is-some (map-get? custodians { custodian: tx-sender })) err-unauthorized)
    
    (map-set assets
      { asset-id: asset-id }
      {
        name: name,
        description: description,
        owner: tx-sender,
        current-custodian: tx-sender,
        status: "created",
        location: location,
        created-at: current-time,
        last-updated: current-time
      }
    )
    
    (map-set asset-history
      { asset-id: asset-id, timestamp: current-time }
      {
        custodian: tx-sender,
        status: "created",
        location: location,
        notes: "Asset created"
      }
    )
    
    (map-set asset-custodians
      { asset-id: asset-id, custodian: tx-sender }
      { authorized: true }
    )
    
    (var-set next-asset-id (+ asset-id u1))
    
    (ok asset-id)
  )
)

(define-public (authorize-custodian (asset-id uint) (custodian principal))
  (let
    (
      (asset (unwrap! (map-get? assets { asset-id: asset-id }) err-not-found))
    )
    (asserts! (is-eq (get owner asset) tx-sender) err-owner-only)
    (asserts! (is-some (map-get? custodians { custodian: custodian })) err-unauthorized)
    
    (map-set asset-custodians
      { asset-id: asset-id, custodian: custodian }
      { authorized: true }
    )
    
    (ok true)
  )
)

(define-public (revoke-custodian (asset-id uint) (custodian principal))
  (let
    (
      (asset (unwrap! (map-get? assets { asset-id: asset-id }) err-not-found))
    )
    (asserts! (is-eq (get owner asset) tx-sender) err-owner-only)
    (asserts! (not (is-eq (get current-custodian asset) custodian)) err-unauthorized)
    
    (map-set asset-custodians
      { asset-id: asset-id, custodian: custodian }
      { authorized: false }
    )
    
    (ok true)
  )
)

(define-public (update-asset-status (asset-id uint) (status (string-ascii 20)) (location (string-ascii 100)) (notes (string-ascii 256)))
  (let
    (
      (asset (unwrap! (map-get? assets { asset-id: asset-id }) err-not-found))
      (current-time stacks-block-height)
    )
    (asserts! (or 
                (is-eq tx-sender (get current-custodian asset))
                (is-authorized-custodian asset-id tx-sender)
              ) 
              err-not-custodian)
    
    (map-set assets
      { asset-id: asset-id }
      (merge asset {
        current-custodian: tx-sender,
        status: status,
        location: location,
        last-updated: current-time
      })
    )
    
    (map-set asset-history
      { asset-id: asset-id, timestamp: current-time }
      {
        custodian: tx-sender,
        status: status,
        location: location,
        notes: notes
      }
    )
    
    (ok true)
  )
)

(define-public (transfer-asset (asset-id uint) (new-custodian principal) (location (string-ascii 100)) (notes (string-ascii 256)))
  (let
    (
      (asset (unwrap! (map-get? assets { asset-id: asset-id }) err-not-found))
      (current-time stacks-block-height)
    )
    (asserts! (is-eq tx-sender (get current-custodian asset)) err-not-custodian)
    (asserts! (is-authorized-custodian asset-id new-custodian) err-unauthorized)
    
    (map-set assets
      { asset-id: asset-id }
      (merge asset {
        current-custodian: new-custodian,
        status: "transferred",
        location: location,
        last-updated: current-time
      })
    )
    
    (map-set asset-history
      { asset-id: asset-id, timestamp: current-time }
      {
        custodian: new-custodian,
        status: "transferred",
        location: location,
        notes: notes
      }
    )
    
    (ok true)
  )
)

(define-public (get-asset-status (asset-id uint))
  (let
    (
      (asset (unwrap! (map-get? assets { asset-id: asset-id }) err-not-found))
    )
    (ok {
      status: (get status asset),
      location: (get location asset),
      current-custodian: (get current-custodian asset)
    })
  )
)

(define-private (zip-asset-data 
    (name (string-ascii 64))
    (description (string-ascii 256))
    (location (string-ascii 100)))
    {
        name: name,
        description: description,
        location: location
    })



(define-private (create-asset-from-lists (item (tuple (name (string-ascii 64)) 
                                                     (description (string-ascii 256)) 
                                                     (location (string-ascii 100))))
                                       (prior-result (list 10 uint)))
    (let
        ((asset-id (var-get next-asset-id))
         (current-time stacks-block-height))
        (map-set assets
            { asset-id: asset-id }
            {
                name: (get name item),
                description: (get description item),
                owner: tx-sender,
                current-custodian: tx-sender,
                status: "created",
                location: (get location item),
                created-at: current-time,
                last-updated: current-time
            })
        (var-set next-asset-id (+ asset-id u1))
        (append prior-result asset-id)
    )
)

(define-map asset-search-indices
    {
        search-key: (string-ascii 128),
        search-type: (string-ascii 20)
    }
    (list 100 uint)
)




(define-read-only (search-assets-by-criteria 
    (search-key (string-ascii 128))
    (search-type (string-ascii 20)))
    (ok (default-to (list) 
        (map-get? asset-search-indices 
            { search-key: search-key, 
              search-type: search-type })))
)