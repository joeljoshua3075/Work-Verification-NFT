(define-non-fungible-token work-verification-nft uint)

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-unauthorized (err u103))
(define-constant err-invalid-rating (err u104))
(define-constant err-dispute-exists (err u105))
(define-constant err-dispute-resolved (err u106))
(define-constant err-non-transferable (err u107))
(define-constant err-milestone-not-found (err u108))
(define-constant err-milestone-completed (err u109))
(define-constant err-insufficient-funds (err u110))
(define-constant err-milestone-not-funded (err u111))
(define-constant err-invalid-milestone-index (err u112))

(define-data-var last-token-id uint u0)
(define-data-var dao-address (optional principal) none)
(define-data-var platform-fee uint u250)

(define-map work-metadata uint {
    client: principal,
    freelancer: principal,
    job-title: (string-ascii 128),
    job-description: (string-ascii 512),
    completion-date: uint,
    rating: uint,
    payment-amount: uint,
    status: (string-ascii 20),
    dispute-id: (optional uint)
})

(define-map client-jobs principal (list 100 uint))
(define-map freelancer-portfolio principal (list 100 uint))
(define-map total-earnings principal uint)
(define-map reputation-scores principal {
    total-jobs: uint,
    average-rating: uint,
    total-earnings: uint
})

(define-map disputes uint {
    token-id: uint,
    initiator: principal,
    reason: (string-ascii 256),
    created-at: uint,
    resolved: bool,
    resolution: (optional (string-ascii 256)),
    arbitrator: (optional principal)
})

(define-data-var last-dispute-id uint u0)
(define-data-var last-milestone-id uint u0)

(define-map multisig-confirmations {token-id: uint, confirmer: principal} bool)
(define-map multisig-required-confirmations uint uint)

(define-map milestones uint {
    client: principal,
    freelancer: principal,
    description: (string-ascii 256),
    amount: uint,
    funded: bool,
    completed: bool,
    completion-time: (optional uint),
    project-id: (optional uint)
})

(define-map project-milestones uint (list 10 uint))
(define-map escrow-balances {milestone-id: uint} uint)

(define-read-only (get-last-token-id)
    (var-get last-token-id)
)

(define-read-only (get-token-uri (token-id uint))
    (ok none)
)

(define-read-only (get-owner (token-id uint))
    (nft-get-owner? work-verification-nft token-id)
)

(define-read-only (get-work-metadata (token-id uint))
    (map-get? work-metadata token-id)
)

(define-read-only (get-client-jobs (client principal))
    (default-to (list) (map-get? client-jobs client))
)

(define-read-only (get-freelancer-portfolio (freelancer principal))
    (default-to (list) (map-get? freelancer-portfolio freelancer))
)

(define-read-only (get-reputation-score (user principal))
    (map-get? reputation-scores user)
)

(define-read-only (get-total-earnings (freelancer principal))
    (default-to u0 (map-get? total-earnings freelancer))
)

(define-read-only (get-dispute (dispute-id uint))
    (map-get? disputes dispute-id)
)

(define-read-only (get-platform-fee)
    (var-get platform-fee)
)

(define-read-only (get-milestone (milestone-id uint))
    (map-get? milestones milestone-id)
)

(define-read-only (get-project-milestones (project-id uint))
    (default-to (list) (map-get? project-milestones project-id))
)

(define-read-only (get-escrow-balance (milestone-id uint))
    (default-to u0 (map-get? escrow-balances {milestone-id: milestone-id}))
)

(define-read-only (calculate-reputation (freelancer principal))
    (let ((portfolio (get-freelancer-portfolio freelancer)))
        (fold calculate-single-rating portfolio {total-rating: u0, job-count: u0})
    )
)

(define-private (calculate-single-rating (token-id uint) (acc {total-rating: uint, job-count: uint}))
    (match (get-work-metadata token-id)
        metadata (let ((rating (get rating metadata)))
            {
                total-rating: (+ (get total-rating acc) rating),
                job-count: (+ (get job-count acc) u1)
            }
        )
        acc
    )
)

(define-public (mint-work-nft 
    (client principal)
    (freelancer principal)
    (job-title (string-ascii 128))
    (job-description (string-ascii 512))
    (rating uint)
    (payment-amount uint))
    (let ((token-id (+ (var-get last-token-id) u1)))
        (asserts! (or (is-eq tx-sender client) (is-eq tx-sender contract-owner)) err-unauthorized)
        (asserts! (and (>= rating u1) (<= rating u5)) err-invalid-rating)
        
        (try! (nft-mint? work-verification-nft token-id freelancer))
        
        (map-set work-metadata token-id {
            client: client,
            freelancer: freelancer,
            job-title: job-title,
            job-description: job-description,
            completion-date: stacks-block-height,
            rating: rating,
            payment-amount: payment-amount,
            status: "completed",
            dispute-id: none
        })
        
        (unwrap-panic (update-client-jobs client token-id))
        (unwrap-panic (update-freelancer-portfolio freelancer token-id))
        (unwrap-panic (update-total-earnings freelancer payment-amount))
        (unwrap-panic (update-reputation-score freelancer rating))
        
        (var-set last-token-id token-id)
        (ok token-id)
    )
)

(define-private (update-client-jobs (client principal) (token-id uint))
    (let ((current-jobs (get-client-jobs client)))
        (map-set client-jobs client (unwrap-panic (as-max-len? (append current-jobs token-id) u100)))
        (ok true)
    )
)

(define-private (update-freelancer-portfolio (freelancer principal) (token-id uint))
    (let ((current-portfolio (get-freelancer-portfolio freelancer)))
        (map-set freelancer-portfolio freelancer (unwrap-panic (as-max-len? (append current-portfolio token-id) u100)))
        (ok true)
    )
)

(define-private (update-total-earnings (freelancer principal) (amount uint))
    (let ((current-earnings (get-total-earnings freelancer)))
        (map-set total-earnings freelancer (+ current-earnings amount))
        (ok true)
    )
)

(define-private (update-reputation-score (freelancer principal) (new-rating uint))
    (let ((current-score (default-to {total-jobs: u0, average-rating: u0, total-earnings: u0} 
                                   (get-reputation-score freelancer)))
          (new-job-count (+ (get total-jobs current-score) u1))
          (total-rating-points (+ (* (get average-rating current-score) (get total-jobs current-score)) new-rating))
          (new-average (/ total-rating-points new-job-count))
          (current-total-earnings (get-total-earnings freelancer)))
        (map-set reputation-scores freelancer {
            total-jobs: new-job-count,
            average-rating: new-average,
            total-earnings: current-total-earnings
        })
        (ok true)
    )
)

(define-public (create-dispute (token-id uint) (reason (string-ascii 256)))
    (let ((dispute-id (+ (var-get last-dispute-id) u1))
          (metadata (unwrap! (get-work-metadata token-id) err-not-found)))
        (asserts! (or (is-eq tx-sender (get client metadata)) 
                     (is-eq tx-sender (get freelancer metadata))) err-unauthorized)
        (asserts! (is-none (get dispute-id metadata)) err-dispute-exists)
        
        (map-set disputes dispute-id {
            token-id: token-id,
            initiator: tx-sender,
            reason: reason,
            created-at: stacks-block-height,
            resolved: false,
            resolution: none,
            arbitrator: none
        })
        
        (map-set work-metadata token-id (merge metadata {dispute-id: (some dispute-id)}))
        (var-set last-dispute-id dispute-id)
        (ok dispute-id)
    )
)

(define-public (resolve-dispute (dispute-id uint) (resolution (string-ascii 256)))
    (let ((dispute (unwrap! (get-dispute dispute-id) err-not-found))
          (dao (var-get dao-address)))
        (asserts! (or (is-eq tx-sender contract-owner) 
                     (and (is-some dao) (is-eq tx-sender (unwrap-panic dao)))) err-unauthorized)
        (asserts! (not (get resolved dispute)) err-dispute-resolved)
        
        (map-set disputes dispute-id (merge dispute {
            resolved: true,
            resolution: (some resolution),
            arbitrator: (some tx-sender)
        }))
        (ok true)
    )
)

(define-public (multisig-confirm (token-id uint))
    (let ((metadata (unwrap! (get-work-metadata token-id) err-not-found)))
        (asserts! (is-eq tx-sender (get client metadata)) err-unauthorized)
        (map-set multisig-confirmations {token-id: token-id, confirmer: tx-sender} true)
        (ok true)
    )
)

(define-public (set-dao-address (new-dao principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set dao-address (some new-dao))
        (ok true)
    )
)

(define-public (set-platform-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= new-fee u1000) err-invalid-rating)
        (var-set platform-fee new-fee)
        (ok true)
    )
)

(define-public (transfer (token-id uint) (sender principal) (recipient principal))
    err-non-transferable
)

(define-read-only (get-freelancer-stats (freelancer principal))
    (let ((portfolio (get-freelancer-portfolio freelancer))
          (reputation (get-reputation-score freelancer))
          (earnings (get-total-earnings freelancer)))
        {
            total-jobs: (len portfolio),
            reputation-score: reputation,
            total-earnings: earnings,
            recent-jobs: (if (> (len portfolio) u5) 
                           (slice? portfolio (- (len portfolio) u5) (len portfolio))
                           (some portfolio))
        }
    )
)

(define-read-only (get-client-stats (client principal))
    (let ((jobs (get-client-jobs client)))
        {
            total-jobs-posted: (len jobs),
            recent-jobs: (if (> (len jobs) u5) 
                           (slice? jobs (- (len jobs) u5) (len jobs))
                           (some jobs))
        }
    )
)

(define-read-only (get-top-freelancers (limit uint))
    (ok "Feature requires off-chain indexing")
)

(define-read-only (verify-work-completion (token-id uint))
    (match (get-work-metadata token-id)
        metadata (ok {
            verified: true,
            client: (get client metadata),
            freelancer: (get freelancer metadata),
            completion-date: (get completion-date metadata),
            rating: (get rating metadata),
            has-dispute: (is-some (get dispute-id metadata))
        })
        (err err-not-found)
    )
)

(define-public (create-milestone 
    (client principal)
    (freelancer principal)
    (description (string-ascii 256))
    (amount uint)
    (project-id (optional uint)))
    (let ((milestone-id (+ (var-get last-milestone-id) u1)))
        (asserts! (is-eq tx-sender client) err-unauthorized)
        (asserts! (> amount u0) err-insufficient-funds)
        
        (map-set milestones milestone-id {
            client: client,
            freelancer: freelancer,
            description: description,
            amount: amount,
            funded: false,
            completed: false,
            completion-time: none,
            project-id: project-id
        })
        
        (match project-id
            pid (let ((current-milestones (get-project-milestones pid)))
                (map-set project-milestones pid 
                    (unwrap-panic (as-max-len? (append current-milestones milestone-id) u10))))
            true)
        
        (var-set last-milestone-id milestone-id)
        (ok milestone-id)
    )
)

(define-public (fund-milestone (milestone-id uint))
    (let ((milestone (unwrap! (get-milestone milestone-id) err-milestone-not-found)))
        (asserts! (is-eq tx-sender (get client milestone)) err-unauthorized)
        (asserts! (not (get funded milestone)) err-milestone-completed)
        
        (let ((payment-amount (get amount milestone)))
            (unwrap! (stx-transfer? payment-amount tx-sender (as-contract tx-sender)) 
                    err-insufficient-funds)
            
            (map-set milestones milestone-id (merge milestone {funded: true}))
            (map-set escrow-balances {milestone-id: milestone-id} payment-amount)
            (ok true)
        )
    )
)

(define-public (complete-milestone (milestone-id uint))
    (let ((milestone (unwrap! (get-milestone milestone-id) err-milestone-not-found)))
        (asserts! (is-eq tx-sender (get freelancer milestone)) err-unauthorized)
        (asserts! (get funded milestone) err-milestone-not-funded)
        (asserts! (not (get completed milestone)) err-milestone-completed)
        
        (map-set milestones milestone-id (merge milestone {
            completed: true,
            completion-time: (some stacks-block-height)
        }))
        (ok true)
    )
)

(define-public (release-milestone-payment (milestone-id uint))
    (let ((milestone (unwrap! (get-milestone milestone-id) err-milestone-not-found))
          (escrow-amount (get-escrow-balance milestone-id)))
        (asserts! (is-eq tx-sender (get client milestone)) err-unauthorized)
        (asserts! (get completed milestone) err-milestone-not-funded)
        (asserts! (> escrow-amount u0) err-insufficient-funds)
        
        (let ((platform-fee-amount (/ (* escrow-amount (var-get platform-fee)) u10000))
              (freelancer-payment (- escrow-amount platform-fee-amount)))
            
            (as-contract (unwrap! (stx-transfer? freelancer-payment tx-sender (get freelancer milestone)) 
                                 err-insufficient-funds))
            (as-contract (unwrap! (stx-transfer? platform-fee-amount tx-sender contract-owner) 
                                 err-insufficient-funds))
            
            (map-delete escrow-balances {milestone-id: milestone-id})
            (ok true)
        )
    )
)

(define-public (emergency-withdraw (milestone-id uint))
    (let ((milestone (unwrap! (get-milestone milestone-id) err-milestone-not-found))
          (escrow-amount (get-escrow-balance milestone-id)))
        (asserts! (or (is-eq tx-sender contract-owner)
                     (and (is-eq tx-sender (get client milestone))
                          (> (- stacks-block-height (default-to u0 (get completion-time milestone))) u1000)))
                 err-unauthorized)
        (asserts! (> escrow-amount u0) err-insufficient-funds)
        
        (as-contract (unwrap! (stx-transfer? escrow-amount tx-sender (get client milestone)) 
                             err-insufficient-funds))
        
        (map-delete escrow-balances {milestone-id: milestone-id})
        (ok true)
    )
)
