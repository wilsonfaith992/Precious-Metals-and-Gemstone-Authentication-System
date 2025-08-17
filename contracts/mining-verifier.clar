;; Mining Verifier Contract
;; Manages mining operation verification and ethical sourcing

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-MINE-NOT-FOUND (err u301))
(define-constant ERR-MINE-EXISTS (err u302))
(define-constant ERR-INVALID-INPUT (err u303))
(define-constant ERR-NOT-COMPLIANT (err u304))

;; Data Variables
(define-data-var verification-counter uint u0)

;; Data Maps
(define-map mining-operations
  { mine-id: (string-ascii 100) }
  {
    mine-name: (string-ascii 200),
    location: (string-ascii 200),
    operator: principal,
    registered-at: uint,
    conflict-free: bool,
    environmental-compliant: bool,
    worker-safety-compliant: bool,
    active: bool
  }
)

(define-map mining-certifications
  { mine-id: (string-ascii 100), cert-type: (string-ascii 50) }
  {
    issuer: (string-ascii 200),
    issued-at: uint,
    expires-at: uint,
    valid: bool
  }
)

(define-map extraction-records
  { certificate-id: (string-ascii 50) }
  {
    mine-id: (string-ascii 100),
    extraction-date: uint,
    quantity: uint,
    quality-grade: (string-ascii 10),
    verified: bool
  }
)

(define-map authorized-inspectors principal bool)

;; Authorization Functions
(define-public (add-inspector (inspector principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (map-set authorized-inspectors inspector true))
  )
)

;; Mining Operation Functions
(define-public (register-mining-operation
  (mine-id (string-ascii 100))
  (mine-name (string-ascii 200))
  (location (string-ascii 200))
  (operator principal))
  (let
    (
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (asserts! (> (len mine-id) u0) ERR-INVALID-INPUT)
    (asserts! (> (len mine-name) u0) ERR-INVALID-INPUT)
    (asserts! (> (len location) u0) ERR-INVALID-INPUT)
    (asserts! (is-none (map-get? mining-operations { mine-id: mine-id })) ERR-MINE-EXISTS)

    (map-set mining-operations
      { mine-id: mine-id }
      {
        mine-name: mine-name,
        location: location,
        operator: operator,
        registered-at: current-time,
        conflict-free: false,
        environmental-compliant: false,
        worker-safety-compliant: false,
        active: true
      }
    )
    (ok mine-id)
  )
)

(define-public (verify-mining-operation
  (mine-id (string-ascii 100))
  (conflict-free bool)
  (environmental-compliant bool)
  (worker-safety-compliant bool))
  (let
    (
      (mine (unwrap! (map-get? mining-operations { mine-id: mine-id }) ERR-MINE-NOT-FOUND))
      (is-authorized (default-to false (map-get? authorized-inspectors tx-sender)))
    )
    (asserts! (or is-authorized (is-eq tx-sender CONTRACT-OWNER)) ERR-NOT-AUTHORIZED)

    (map-set mining-operations
      { mine-id: mine-id }
      (merge mine {
        conflict-free: conflict-free,
        environmental-compliant: environmental-compliant,
        worker-safety-compliant: worker-safety-compliant
      })
    )
    (ok true)
  )
)

(define-public (add-certification
  (mine-id (string-ascii 100))
  (cert-type (string-ascii 50))
  (issuer (string-ascii 200))
  (expires-at uint))
  (let
    (
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
      (mine (unwrap! (map-get? mining-operations { mine-id: mine-id }) ERR-MINE-NOT-FOUND))
      (is-authorized (default-to false (map-get? authorized-inspectors tx-sender)))
    )
    (asserts! (or is-authorized (is-eq tx-sender CONTRACT-OWNER)) ERR-NOT-AUTHORIZED)
    (asserts! (> expires-at current-time) ERR-INVALID-INPUT)

    (map-set mining-certifications
      { mine-id: mine-id, cert-type: cert-type }
      {
        issuer: issuer,
        issued-at: current-time,
        expires-at: expires-at,
        valid: true
      }
    )
    (ok true)
  )
)

(define-public (record-extraction
  (certificate-id (string-ascii 50))
  (mine-id (string-ascii 100))
  (extraction-date uint)
  (quantity uint)
  (quality-grade (string-ascii 10)))
  (let
    (
      (mine (unwrap! (map-get? mining-operations { mine-id: mine-id }) ERR-MINE-NOT-FOUND))
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (asserts! (or (is-eq tx-sender (get operator mine)) (is-eq tx-sender CONTRACT-OWNER)) ERR-NOT-AUTHORIZED)
    (asserts! (get active mine) ERR-NOT-COMPLIANT)
    (asserts! (> quantity u0) ERR-INVALID-INPUT)
    (asserts! (<= extraction-date current-time) ERR-INVALID-INPUT)

    (map-set extraction-records
      { certificate-id: certificate-id }
      {
        mine-id: mine-id,
        extraction-date: extraction-date,
        quantity: quantity,
        quality-grade: quality-grade,
        verified: false
      }
    )
    (ok true)
  )
)

(define-public (verify-extraction (certificate-id (string-ascii 50)))
  (let
    (
      (extraction (unwrap! (map-get? extraction-records { certificate-id: certificate-id }) ERR-INVALID-INPUT))
      (is-authorized (default-to false (map-get? authorized-inspectors tx-sender)))
    )
    (asserts! (or is-authorized (is-eq tx-sender CONTRACT-OWNER)) ERR-NOT-AUTHORIZED)

    (map-set extraction-records
      { certificate-id: certificate-id }
      (merge extraction { verified: true })
    )
    (ok true)
  )
)

;; Read-only Functions
(define-read-only (get-mining-operation (mine-id (string-ascii 100)))
  (map-get? mining-operations { mine-id: mine-id })
)

(define-read-only (get-certification
  (mine-id (string-ascii 100))
  (cert-type (string-ascii 50)))
  (let
    (
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (match (map-get? mining-certifications { mine-id: mine-id, cert-type: cert-type })
      cert (and
             (get valid cert)
             (> (get expires-at cert) current-time))
      false
    )
  )
)

(define-read-only (get-extraction-record (certificate-id (string-ascii 50)))
  (map-get? extraction-records { certificate-id: certificate-id })
)

(define-read-only (is-mine-compliant (mine-id (string-ascii 100)))
  (match (map-get? mining-operations { mine-id: mine-id })
    mine (and
           (get conflict-free mine)
           (get environmental-compliant mine)
           (get worker-safety-compliant mine)
           (get active mine))
    false
  )
)

(define-read-only (is-certification-valid
  (mine-id (string-ascii 100))
  (cert-type (string-ascii 50)))
  (let
    (
      (current-time (unwrap-panic (get-block-info? time (- block-height u1))))
    )
    (match (map-get? mining-certifications { mine-id: mine-id, cert-type: cert-type })
      cert (and
             (get valid cert)
             (> (get expires-at cert) current-time))
      false
    )
  )
)

(define-read-only (is-extraction-verified (certificate-id (string-ascii 50)))
  (match (map-get? extraction-records { certificate-id: certificate-id })
    extraction (get verified extraction)
    false
  )
)
