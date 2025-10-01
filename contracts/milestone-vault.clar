;; Title: MilestoneVault
;; Summary: Trustless milestone-driven educational fund distribution protocol
;; Description: A decentralized scholarship management system enabling donors to establish 
;;              conditional funding pools that automatically disburse educational grants when 
;;              students achieve verified academic milestones. Built on Bitcoin's security layer,
;;              this protocol ensures transparent, tamper-proof fund allocation with oracle-verified
;;              performance metrics and multi-semester milestone tracking.

;; Error Constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-POOL-NOT-FOUND (err u101))
(define-constant ERR-INSUFFICIENT-FUNDS (err u102))
(define-constant ERR-MILESTONE-NOT-MET (err u103))
(define-constant ERR-ALREADY-CLAIMED (err u104))
(define-constant ERR-INVALID-AMOUNT (err u105))
(define-constant ERR-INVALID-STUDENT (err u106))
(define-constant ERR-ORACLE-NOT-AUTHORIZED (err u107))

;; Contract Constants
(define-constant CONTRACT-OWNER tx-sender)

;; State Variables
(define-data-var pool-counter uint u0)

;; Data Maps

;; Oracle Registry - Authorized verifiers for academic milestones
(define-map oracles
    principal
    bool
)

;; Scholarship Pool Registry - Core funding structure
(define-map scholarship-pools
    { pool-id: uint }
    {
        donor: principal,
        total-amount: uint,
        remaining-amount: uint,
        student: principal,
        required-gpa: uint,              ;; GPA * 100 (e.g., 3.50 = 350)
        total-semesters: uint,
        amount-per-semester: uint,
        semesters-released: uint,
        created-at: uint,
        active: bool
    }
)

;; Milestone Verification Registry - Academic performance tracking
(define-map milestone-verifications
    {
        pool-id: uint,
        semester: uint
    }
    {
        gpa: uint,                       ;; GPA * 100
        verified-by: principal,
        verified-at: uint,
        released: bool
    }
)

;; Initialization
(map-set oracles CONTRACT-OWNER true)

;; Oracle Management Functions

(define-public (add-oracle (oracle principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (ok (map-set oracles oracle true))
    )
)

(define-public (remove-oracle (oracle principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (ok (map-delete oracles oracle))
    )
)

;; Core Scholarship Pool Functions

;; Create new milestone-based scholarship pool
(define-public (create-scholarship-pool
        (student principal)
        (required-gpa uint)
        (total-semesters uint)
        (amount-per-semester uint)
    )
    (let (
            (pool-id (+ (var-get pool-counter) u1))
            (total-amount (* total-semesters amount-per-semester))
        )
        ;; Validation checks
        (asserts! (> amount-per-semester u0) ERR-INVALID-AMOUNT)
        (asserts! (> total-semesters u0) ERR-INVALID-AMOUNT)
        (asserts! (> required-gpa u0) ERR-INVALID-AMOUNT)
        (asserts! (<= required-gpa u400) ERR-INVALID-AMOUNT)  ;; Max GPA 4.0

        ;; Lock funds in contract
        (try! (stx-transfer? total-amount tx-sender (as-contract tx-sender)))

        ;; Initialize pool
        (map-set scholarship-pools 
            { pool-id: pool-id } 
            {
                donor: tx-sender,
                total-amount: total-amount,
                remaining-amount: total-amount,
                student: student,
                required-gpa: required-gpa,
                total-semesters: total-semesters,
                amount-per-semester: amount-per-semester,
                semesters-released: u0,
                created-at: stacks-block-height,
                active: true
            }
        )

        (var-set pool-counter pool-id)
        (ok pool-id)
    )
)