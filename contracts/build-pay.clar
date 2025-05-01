;; BuildPay - Smart contract for milestone-based payments in construction projects
;; Author: v0

;; Error codes
(define-constant ERR_UNAUTHORIZED u1)
(define-constant ERR_INVALID_STATE u2)
(define-constant ERR_INSUFFICIENT_FUNDS u3)
(define-constant ERR_MILESTONE_NOT_FOUND u4)
(define-constant ERR_ALREADY_APPROVED u5)
(define-constant ERR_NOT_APPROVED u6)

;; Project states
(define-constant STATE_CREATED u1)
(define-constant STATE_IN_PROGRESS u2)
(define-constant STATE_COMPLETED u3)
(define-constant STATE_CANCELLED u4)

;; Milestone status
(define-constant STATUS_PENDING u1)
(define-constant STATUS_APPROVED u2)
(define-constant STATUS_PAID u3)
(define-constant STATUS_DISPUTED u4)

;; Data structures
(define-map projects
  { project-id: uint }
  {
    owner: principal,
    contractor: principal,
    total-amount: uint,
    released-amount: uint,
    retained-amount: uint,
    retention-rate: uint,
    state: uint,
    milestone-count: uint,
    created-at: uint
  }
)

(define-map milestones
  { project-id: uint, milestone-id: uint }
  {
    description: (string-utf8 256),
    amount: uint,
    status: uint,
    approved-by: (optional principal),
    approved-at: (optional uint),
    paid-at: (optional uint)
  }
)

(define-map project-funds
  { project-id: uint }
  { balance: uint }
)

(define-data-var next-project-id uint u1)

;; Read-only functions
(define-read-only (get-project (project-id uint))
  (map-get? projects { project-id: project-id })
)

(define-read-only (get-milestone (project-id uint) (milestone-id uint))
  (map-get? milestones { project-id: project-id, milestone-id: milestone-id })
)

(define-read-only (get-project-balance (project-id uint))
  (default-to { balance: u0 } (map-get? project-funds { project-id: project-id }))
)

;; Create a new construction project with milestones
(define-public (create-project 
                (contractor principal) 
                (total-amount uint) 
                (retention-rate uint))
  (let ((project-id (var-get next-project-id))
        (block-height (get-block-info? height u0)))

    ;; Validate inputs
    (asserts! (< retention-rate u30) (err ERR_INVALID_STATE)) ;; Max 30% retention

    ;; Create the project
    (map-set projects
      { project-id: project-id }
      {
        owner: tx-sender,
        contractor: contractor,
        total-amount: total-amount,
        released-amount: u0,
        retained-amount: u0,
        retention-rate: retention-rate,
        state: STATE_CREATED,
        milestone-count: u0,
        created-at: (default-to u0 block-height)
      }
    )

    ;; Initialize project funds
    (map-set project-funds
      { project-id: project-id }
      { balance: u0 }
    )

    ;; Increment project ID counter
    (var-set next-project-id (+ project-id u1))

    (ok project-id)
  )
)

;; Fund a project
(define-public (fund-project (project-id uint) (amount uint))
  (let ((project (unwrap! (get-project project-id) (err ERR_MILESTONE_NOT_FOUND)))
        (current-balance (get balance (get-project-balance project-id))))

    ;; Check if project exists and is in valid state
    (asserts! (or (is-eq (get state project) STATE_CREATED)
                 (is-eq (get state project) STATE_IN_PROGRESS))
             (err ERR_INVALID_STATE))

    ;; Transfer STX to contract
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))

    ;; Update project funds
    (map-set project-funds
      { project-id: project-id }
      { balance: (+ current-balance amount) }
    )

    ;; If this is the first funding, update state to in progress
    (if (is-eq (get state project) STATE_CREATED)
      (map-set projects
        { project-id: project-id }
        (merge project { state: STATE_IN_PROGRESS })
      )
      true
    )

    (ok true)
  )
)

;; Add a milestone to a project
(define-public (add-milestone 
                (project-id uint) 
                (description (string-utf8 256)) 
                (amount uint))
  (let ((project (unwrap! (get-project project-id) (err ERR_MILESTONE_NOT_FOUND)))
        (milestone-id (get milestone-count project)))

    ;; Only project owner can add milestones
    (asserts! (is-eq tx-sender (get owner project)) (err ERR_UNAUTHORIZED))

    ;; Project must be in created or in progress state
    (asserts! (or (is-eq (get state project) STATE_CREATED)
                 (is-eq (get state project) STATE_IN_PROGRESS))
             (err ERR_INVALID_STATE))

    ;; Create the milestone
    (map-set milestones
      { project-id: project-id, milestone-id: milestone-id }
      {
        description: description,
        amount: amount,
        status: STATUS_PENDING,
        approved-by: none,
        approved-at: none,
        paid-at: none
      }
    )

    ;; Update milestone count
    (map-set projects
      { project-id: project-id }
      (merge project { milestone-count: (+ milestone-id u1) })
    )

    (ok milestone-id)
  )
)

;; Approve a milestone (by project owner or authorized inspector)
(define-public (approve-milestone (project-id uint) (milestone-id uint))
  (let ((project (unwrap! (get-project project-id) (err ERR_MILESTONE_NOT_FOUND)))
        (milestone (unwrap! (get-milestone project-id milestone-id) (err ERR_MILESTONE_NOT_FOUND)))
        (block-height (get-block-info? height u0)))

    ;; Only project owner can approve milestones
    (asserts! (is-eq tx-sender (get owner project)) (err ERR_UNAUTHORIZED))

    ;; Project must be in progress
    (asserts! (is-eq (get state project) STATE_IN_PROGRESS) (err ERR_INVALID_STATE))

    ;; Milestone must be pending
    (asserts! (is-eq (get status milestone) STATUS_PENDING) (err ERR_ALREADY_APPROVED))

    ;; Update milestone status
    (map-set milestones
      { project-id: project-id, milestone-id: milestone-id }
      (merge milestone { 
        status: STATUS_APPROVED,
        approved-by: (some tx-sender),
        approved-at: (some (default-to u0 block-height))
      })
    )

    (ok true)
  )
)

;; Release payment for an approved milestone
(define-public (release-payment (project-id uint) (milestone-id uint))
  (let ((project (unwrap! (get-project project-id) (err ERR_MILESTONE_NOT_FOUND)))
        (milestone (unwrap! (get-milestone project-id milestone-id) (err ERR_MILESTONE_NOT_FOUND)))
        (project-balance (get balance (get-project-balance project-id)))
        (block-height (get-block-info? height u0))
        (milestone-amount (get amount milestone))
        (retention-amount (/ (* milestone-amount (get retention-rate project)) u100))
        (payment-amount (- milestone-amount retention-amount)))

    ;; Only project owner can release payments
    (asserts! (is-eq tx-sender (get owner project)) (err ERR_UNAUTHORIZED))

    ;; Project must be in progress
    (asserts! (is-eq (get state project) STATE_IN_PROGRESS) (err ERR_INVALID_STATE))

    ;; Milestone must be approved
    (asserts! (is-eq (get status milestone) STATUS_APPROVED) (err ERR_NOT_APPROVED))

    ;; Check sufficient funds
    (asserts! (>= project-balance payment-amount) (err ERR_INSUFFICIENT_FUNDS))

    ;; Transfer payment to contractor
    (try! (as-contract (stx-transfer? payment-amount tx-sender (get contractor project))))

    ;; Update milestone status
    (map-set milestones
      { project-id: project-id, milestone-id: milestone-id }
      (merge milestone { 
        status: STATUS_PAID,
        paid-at: (some (default-to u0 block-height))
      })
    )

    ;; Update project funds and released amount
    (map-set project-funds
      { project-id: project-id }
      { balance: (- project-balance payment-amount) }
    )

    (map-set projects
      { project-id: project-id }
      (merge project { 
        released-amount: (+ (get released-amount project) payment-amount),
        retained-amount: (+ (get retained-amount project) retention-amount)
      })
    )

    (ok payment-amount)
  )
)

;; Complete project and release retention
(define-public (complete-project (project-id uint))
  (let ((project (unwrap! (get-project project-id) (err ERR_MILESTONE_NOT_FOUND)))
        (project-balance (get balance (get-project-balance project-id)))
        (retained-amount (get retained-amount project)))

    ;; Only project owner can complete project
    (asserts! (is-eq tx-sender (get owner project)) (err ERR_UNAUTHORIZED))

    ;; Project must be in progress
    (asserts! (is-eq (get state project) STATE_IN_PROGRESS) (err ERR_INVALID_STATE))

    ;; Check sufficient funds for retention release
    (asserts! (>= project-balance retained-amount) (err ERR_INSUFFICIENT_FUNDS))

    ;; Transfer retention to contractor
    (try! (as-contract (stx-transfer? retained-amount tx-sender (get contractor project))))

    ;; Update project state
    (map-set projects
      { project-id: project-id }
      (merge project { 
        state: STATE_COMPLETED,
        released-amount: (+ (get released-amount project) retained-amount),
        retained-amount: u0
      })
    )

    ;; Update project funds
    (map-set project-funds
      { project-id: project-id }
      { balance: (- project-balance retained-amount) }
    )

    (ok retained-amount)
  )
)

;; Cancel project and refund remaining funds to owner
(define-public (cancel-project (project-id uint))
  (let ((project (unwrap! (get-project project-id) (err ERR_MILESTONE_NOT_FOUND)))
        (project-balance (get balance (get-project-balance project-id))))

    ;; Only project owner can cancel project
    (asserts! (is-eq tx-sender (get owner project)) (err ERR_UNAUTHORIZED))

    ;; Project must not be completed
    (asserts! (not (is-eq (get state project) STATE_COMPLETED)) (err ERR_INVALID_STATE))

    ;; Transfer remaining funds back to owner
    (if (> project-balance u0)
      (try! (as-contract (stx-transfer? project-balance tx-sender (get owner project))))
      true
    )

    ;; Update project state
    (map-set projects
      { project-id: project-id }
      (merge project { state: STATE_CANCELLED })
    )

    ;; Update project funds
    (map-set project-funds
      { project-id: project-id }
      { balance: u0 }
    )

    (ok project-balance)
  )
)