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

;; Milestone Verification Functions

;; Submit academic milestone verification
(define-public (verify-milestone
        (pool-id uint)
        (semester uint)
        (student-gpa uint)
    )
    (let (
            (pool (unwrap! (map-get? scholarship-pools { pool-id: pool-id })
                ERR-POOL-NOT-FOUND
            ))
        )
        ;; Authorization and validation checks
        (asserts! (is-oracle tx-sender) ERR-ORACLE-NOT-AUTHORIZED)
        (asserts! (get active pool) ERR-POOL-NOT-FOUND)
        (asserts! (is-eq semester (+ (get semesters-released pool) u1))
            ERR-MILESTONE-NOT-MET
        )
        (asserts! (<= semester (get total-semesters pool)) ERR-MILESTONE-NOT-MET)

        ;; Record verification
        (map-set milestone-verifications 
            {
                pool-id: pool-id,
                semester: semester
            } 
            {
                gpa: student-gpa,
                verified-by: tx-sender,
                verified-at: stacks-block-height,
                released: false
            }
        )

        (ok true)
    )
)

;; Fund Distribution Functions

;; Release semester funds upon successful milestone completion
(define-public (release-semester-funds
        (pool-id uint)
        (semester uint)
    )
    (let (
            (pool (unwrap! (map-get? scholarship-pools { pool-id: pool-id })
                ERR-POOL-NOT-FOUND
            ))
            (verification (unwrap!
                (map-get? milestone-verifications {
                    pool-id: pool-id,
                    semester: semester
                })
                ERR-MILESTONE-NOT-MET
            ))
        )
        ;; Validation checks
        (asserts! (get active pool) ERR-POOL-NOT-FOUND)
        (asserts! (not (get released verification)) ERR-ALREADY-CLAIMED)
        (asserts! (>= (get gpa verification) (get required-gpa pool))
            ERR-MILESTONE-NOT-MET
        )
        (asserts! (is-eq semester (+ (get semesters-released pool) u1))
            ERR-MILESTONE-NOT-MET
        )
        (asserts! (>= (get remaining-amount pool) (get amount-per-semester pool))
            ERR-INSUFFICIENT-FUNDS
        )

        ;; Transfer funds to student
        (try! (as-contract (stx-transfer? 
            (get amount-per-semester pool) 
            tx-sender
            (get student pool)
        )))

        ;; Update pool state
        (map-set scholarship-pools 
            { pool-id: pool-id }
            (merge pool {
                remaining-amount: (- (get remaining-amount pool) (get amount-per-semester pool)),
                semesters-released: (+ (get semesters-released pool) u1),
                active: (< (+ (get semesters-released pool) u1)
                    (get total-semesters pool)
                )
            })
        )

        ;; Mark verification as released
        (map-set milestone-verifications 
            {
                pool-id: pool-id,
                semester: semester
            }
            (merge verification { released: true })
        )

        (ok (get amount-per-semester pool))
    )
)

;; Emergency Functions

;; Donor emergency withdrawal for failed milestone compliance
(define-public (emergency-withdrawal (pool-id uint))
    (let (
            (pool (unwrap! (map-get? scholarship-pools { pool-id: pool-id })
                ERR-POOL-NOT-FOUND
            ))
        )
        ;; Authorization checks
        (asserts! (is-eq tx-sender (get donor pool)) ERR-NOT-AUTHORIZED)
        (asserts! (get active pool) ERR-POOL-NOT-FOUND)
        (asserts! (> (get remaining-amount pool) u0) ERR-INSUFFICIENT-FUNDS)

        ;; Validate withdrawal conditions
        (let (
                (next-semester (+ (get semesters-released pool) u1))
                (next-verification (map-get? milestone-verifications {
                    pool-id: pool-id,
                    semester: next-semester
                }))
                (withdrawal-amount (get remaining-amount pool))
            )
            ;; Ensure milestone failure or no verification
            (match next-verification
                verification
                (asserts! (< (get gpa verification) (get required-gpa pool))
                    ERR-MILESTONE-NOT-MET
                )
                true  ;; No verification exists, allow withdrawal
            )