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
(define-constant err-skill-not-found (err u113))
(define-constant err-insufficient-skill-jobs (err u114))

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

(define-map skill-categories uint {
    name: (string-ascii 64),
    min-jobs-required: uint,
    min-average-rating: uint
})

(define-map freelancer-skills {freelancer: principal, skill-id: uint} {
    jobs-completed: uint,
    total-rating: uint,
    average-rating: uint,
    certified: bool,
    certification-date: (optional uint)
})

(define-map job-skills uint (list 5 uint))
(define-data-var last-skill-id uint u0)

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

(define-read-only (get-skill-category (skill-id uint))
    (map-get? skill-categories skill-id)
)

(define-read-only (get-freelancer-skill (freelancer principal) (skill-id uint))
    (map-get? freelancer-skills {freelancer: freelancer, skill-id: skill-id})
)

(define-read-only (get-job-skills (token-id uint))
    (default-to (list) (map-get? job-skills token-id))
)

(define-read-only (get-last-skill-id)
    (var-get last-skill-id)
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
    (payment-amount uint)
    (skill-ids (list 5 uint)))
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
        
        (map-set job-skills token-id skill-ids)
        
        (unwrap-panic (update-client-jobs client token-id))
        (unwrap-panic (update-freelancer-portfolio freelancer token-id))
        (unwrap-panic (update-total-earnings freelancer payment-amount))
        (unwrap-panic (update-reputation-score freelancer rating))
        (unwrap-panic (update-freelancer-skills freelancer skill-ids rating))
        
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

(define-private (update-freelancer-skills (freelancer principal) (skill-ids (list 5 uint)) (rating uint))
    (begin
        (fold update-skill-with-context skill-ids {freelancer: freelancer, rating: rating, success: true})
        (ok true)
    )
)

(define-private (update-skill-with-context (skill-id uint) (context {freelancer: principal, rating: uint, success: bool}))
    (let ((freelancer (get freelancer context))
          (rating (get rating context))
          (current-skill (default-to 
              {jobs-completed: u0, total-rating: u0, average-rating: u0, certified: false, certification-date: none}
              (get-freelancer-skill freelancer skill-id)))
          (new-jobs-completed (+ (get jobs-completed current-skill) u1))
          (new-total-rating (+ (get total-rating current-skill) rating))
          (new-average-rating (/ new-total-rating new-jobs-completed)))
        
        (map-set freelancer-skills {freelancer: freelancer, skill-id: skill-id} {
            jobs-completed: new-jobs-completed,
            total-rating: new-total-rating,
            average-rating: new-average-rating,
            certified: (get certified current-skill),
            certification-date: (get certification-date current-skill)
        })
        {freelancer: freelancer, rating: rating, success: true}
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

(define-public (create-skill-category 
    (name (string-ascii 64))
    (min-jobs-required uint)
    (min-average-rating uint))
    (let ((skill-id (+ (var-get last-skill-id) u1)))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (and (>= min-average-rating u1) (<= min-average-rating u5)) err-invalid-rating)
        (asserts! (> min-jobs-required u0) err-insufficient-skill-jobs)
        
        (map-set skill-categories skill-id {
            name: name,
            min-jobs-required: min-jobs-required,
            min-average-rating: min-average-rating
        })
        
        (var-set last-skill-id skill-id)
        (ok skill-id)
    )
)

(define-public (certify-skill (freelancer principal) (skill-id uint))
    (let ((skill-category (unwrap! (get-skill-category skill-id) err-skill-not-found))
          (freelancer-skill (default-to 
              {jobs-completed: u0, total-rating: u0, average-rating: u0, certified: false, certification-date: none}
              (get-freelancer-skill freelancer skill-id))))
        
        (asserts! (>= (get jobs-completed freelancer-skill) (get min-jobs-required skill-category)) err-insufficient-skill-jobs)
        (asserts! (>= (get average-rating freelancer-skill) (get min-average-rating skill-category)) err-invalid-rating)
        (asserts! (not (get certified freelancer-skill)) err-already-exists)
        
        (map-set freelancer-skills {freelancer: freelancer, skill-id: skill-id} 
            (merge freelancer-skill {
                certified: true,
                certification-date: (some stacks-block-height)
            }))
        
        (ok true)
    )
)

(define-read-only (get-freelancer-certifications (freelancer principal))
    (let ((skill-ids (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10)))
        (filter is-certified-skill 
            (map get-skill-with-id skill-ids))
    )
)

(define-private (get-skill-with-id (skill-id uint))
    {skill-id: skill-id, 
     freelancer: tx-sender}
)

(define-private (is-certified-skill (skill-data {skill-id: uint, freelancer: principal}))
    (let ((skill (get-freelancer-skill (get freelancer skill-data) (get skill-id skill-data))))
        (match skill
            s (get certified s)
            false)
    )
)

;; Project Templates System - New Independent Feature
(define-constant err-template-not-found (err u115))
(define-constant err-invalid-template-id (err u116))
(define-constant err-template-already-exists (err u117))
(define-constant err-invalid-milestone-count (err u118))
(define-constant err-template-in-use (err u119))

(define-data-var last-template-id uint u0)

(define-map project-templates uint {
    creator: principal,
    name: (string-ascii 128),
    description: (string-ascii 512),
    category: (string-ascii 64),
    estimated-duration: uint,
    total-budget-range: {min: uint, max: uint},
    required-skills: (list 5 uint),
    milestone-count: uint,
    milestone-percentages: (list 10 uint),
    created-at: uint,
    usage-count: uint,
    rating: uint,
    active: bool
})

(define-map template-reviews {template-id: uint, reviewer: principal} {
    rating: uint,
    comment: (string-ascii 256),
    created-at: uint
})

(define-map template-milestones {template-id: uint, milestone-index: uint} {
    title: (string-ascii 128),
    description: (string-ascii 256),
    deliverables: (string-ascii 512),
    percentage: uint
})

(define-map user-templates principal (list 20 uint))
(define-map template-usage-history uint (list 50 principal))

;; Read-only functions for Project Templates
(define-read-only (get-template (template-id uint))
    (map-get? project-templates template-id)
)

(define-read-only (get-template-milestone (template-id uint) (milestone-index uint))
    (map-get? template-milestones {template-id: template-id, milestone-index: milestone-index})
)

(define-read-only (get-template-review (template-id uint) (reviewer principal))
    (map-get? template-reviews {template-id: template-id, reviewer: reviewer})
)

(define-read-only (get-user-templates (user principal))
    (default-to (list) (map-get? user-templates user))
)

(define-read-only (get-template-usage-history (template-id uint))
    (default-to (list) (map-get? template-usage-history template-id))
)

(define-read-only (get-last-template-id)
    (var-get last-template-id)
)

(define-read-only (get-popular-templates (category (string-ascii 64)))
    (ok "Feature requires off-chain indexing for category filtering")
)

;; Public functions for Project Templates
(define-public (create-project-template 
    (name (string-ascii 128))
    (description (string-ascii 512))
    (category (string-ascii 64))
    (estimated-duration uint)
    (budget-min uint)
    (budget-max uint)
    (required-skills (list 5 uint))
    (milestone-titles (list 10 (string-ascii 128)))
    (milestone-descriptions (list 10 (string-ascii 256)))
    (milestone-deliverables (list 10 (string-ascii 512)))
    (milestone-percentages (list 10 uint)))
    (let ((template-id (+ (var-get last-template-id) u1))
          (milestone-count (len milestone-percentages))
          (total-percentage (fold + milestone-percentages u0)))
        
        (asserts! (> milestone-count u0) err-invalid-milestone-count)
        (asserts! (<= milestone-count u10) err-invalid-milestone-count)
        (asserts! (is-eq total-percentage u100) err-invalid-milestone-count)
        (asserts! (< budget-min budget-max) err-insufficient-funds)
        
        (map-set project-templates template-id {
            creator: tx-sender,
            name: name,
            description: description,
            category: category,
            estimated-duration: estimated-duration,
            total-budget-range: {min: budget-min, max: budget-max},
            required-skills: required-skills,
            milestone-count: milestone-count,
            milestone-percentages: milestone-percentages,
            created-at: stacks-block-height,
            usage-count: u0,
            rating: u0,
            active: true
        })
        
        (unwrap-panic (process-template-milestones template-id milestone-titles milestone-descriptions milestone-deliverables milestone-percentages))
        (unwrap-panic (add-template-to-user tx-sender template-id))
        
        (var-set last-template-id template-id)
        (ok template-id)
    )
)

(define-private (process-template-milestones
    (template-id uint)
    (titles (list 10 (string-ascii 128)))
    (descriptions (list 10 (string-ascii 256)))
    (deliverables (list 10 (string-ascii 512)))
    (percentages (list 10 uint)))
    (let ((milestone-count (len titles)))
        (fold store-milestone-data 
            (list u0 u1 u2 u3 u4 u5 u6 u7 u8 u9)
            {template-id: template-id, 
             titles: titles, 
             descriptions: descriptions, 
             deliverables: deliverables, 
             percentages: percentages, 
             count: milestone-count,
             success: true})
        (ok true)
    )
)

(define-private (store-milestone-data 
    (index uint) 
    (context {template-id: uint, titles: (list 10 (string-ascii 128)), descriptions: (list 10 (string-ascii 256)), deliverables: (list 10 (string-ascii 512)), percentages: (list 10 uint), count: uint, success: bool}))
    (if (and (get success context) (< index (get count context)))
        (let ((template-id (get template-id context))
              (titles (get titles context))
              (descriptions (get descriptions context))
              (deliverables (get deliverables context))
              (percentages (get percentages context)))
            (map-set template-milestones {template-id: template-id, milestone-index: index} {
                title: (unwrap-panic (element-at titles index)),
                description: (unwrap-panic (element-at descriptions index)),
                deliverables: (unwrap-panic (element-at deliverables index)),
                percentage: (unwrap-panic (element-at percentages index))
            })
            context
        )
        context
    )
)

(define-private (add-template-to-user (user principal) (template-id uint))
    (let ((current-templates (get-user-templates user)))
        (map-set user-templates user (unwrap-panic (as-max-len? (append current-templates template-id) u20)))
        (ok true)
    )
)

(define-public (use-project-template (template-id uint))
    (let ((template (unwrap! (get-template template-id) err-template-not-found)))
        (asserts! (get active template) err-template-not-found)
        
        (map-set project-templates template-id (merge template {
            usage-count: (+ (get usage-count template) u1)
        }))
        
        (let ((current-usage (get-template-usage-history template-id)))
            (map-set template-usage-history template-id 
                (unwrap-panic (as-max-len? (append current-usage tx-sender) u50)))
        )
        
        (ok template-id)
    )
)

(define-public (rate-template (template-id uint) (rating uint) (comment (string-ascii 256)))
    (let ((template (unwrap! (get-template template-id) err-template-not-found)))
        (asserts! (and (>= rating u1) (<= rating u5)) err-invalid-rating)
        (asserts! (get active template) err-template-not-found)
        
        (map-set template-reviews {template-id: template-id, reviewer: tx-sender} {
            rating: rating,
            comment: comment,
            created-at: stacks-block-height
        })
        
        (unwrap-panic (update-template-rating template-id rating))
        (ok true)
    )
)

(define-private (update-template-rating (template-id uint) (new-rating uint))
    (let ((template (unwrap! (get-template template-id) err-template-not-found))
          (current-rating (get rating template))
          (usage-count (get usage-count template)))
        (if (is-eq current-rating u0)
            (map-set project-templates template-id (merge template {rating: new-rating}))
            (let ((total-ratings (* current-rating usage-count))
                  (updated-total (+ total-ratings new-rating))
                  (new-average (/ updated-total (+ usage-count u1))))
                (map-set project-templates template-id (merge template {rating: new-average}))
            )
        )
        (ok true)
    )
)

(define-public (deactivate-template (template-id uint))
    (let ((template (unwrap! (get-template template-id) err-template-not-found)))
        (asserts! (or (is-eq tx-sender (get creator template)) (is-eq tx-sender contract-owner)) err-unauthorized)
        
        (map-set project-templates template-id (merge template {active: false}))
        (ok true)
    )
)

(define-public (clone-template (template-id uint) (new-name (string-ascii 128)))
    (let ((original-template (unwrap! (get-template template-id) err-template-not-found))
          (new-template-id (+ (var-get last-template-id) u1)))
        (asserts! (get active original-template) err-template-not-found)
        
        (map-set project-templates new-template-id (merge original-template {
            creator: tx-sender,
            name: new-name,
            created-at: stacks-block-height,
            usage-count: u0,
            rating: u0
        }))
        
        (unwrap-panic (add-template-to-user tx-sender new-template-id))
        
        (var-set last-template-id new-template-id)
        (ok new-template-id)
    )
)

(define-read-only (calculate-template-compatibility (template-id uint) (freelancer principal))
    (let ((template (unwrap! (get-template template-id) err-template-not-found))
          (required-skills (get required-skills template))
          (missing-skills-result (filter-missing-skills freelancer required-skills)))
        (ok {
            template-id: template-id,
            compatibility-score: (calculate-skill-match freelancer required-skills),
            missing-skills: (get missing missing-skills-result),
            estimated-budget: (get total-budget-range template),
            estimated-duration: (get estimated-duration template)
        })
    )
)

(define-private (calculate-skill-match (freelancer principal) (required-skills (list 5 uint)))
    (let ((match-count (fold count-skill-matches required-skills {freelancer: freelancer, count: u0})))
        (/ (* (get count match-count) u100) (len required-skills))
    )
)

(define-private (count-skill-matches (skill-id uint) (acc {freelancer: principal, count: uint}))
    (let ((freelancer (get freelancer acc))
          (current-count (get count acc)))
        {freelancer: freelancer, count: (if (is-some (get-freelancer-skill freelancer skill-id)) (+ current-count u1) current-count)}
    )
)

(define-private (filter-missing-skills (freelancer principal) (required-skills (list 5 uint)))
    (fold collect-missing-skills required-skills {freelancer: freelancer, missing: (list)})
)

(define-private (collect-missing-skills (skill-id uint) (acc {freelancer: principal, missing: (list 5 uint)}))
    (let ((freelancer (get freelancer acc))
          (missing-list (get missing acc)))
        {freelancer: freelancer, 
         missing: (if (is-none (get-freelancer-skill freelancer skill-id))
                     (unwrap-panic (as-max-len? (append missing-list skill-id) u5))
                     missing-list)}
    )
)

;; Analytics Dashboard System - New Independent Feature
(define-constant err-invalid-timeframe (err u120))
(define-constant err-analytics-disabled (err u121))
(define-constant err-insufficient-data (err u122))
(define-constant err-badge-not-found (err u123))
(define-constant err-badge-already-earned (err u124))
(define-constant err-requirements-not-met (err u125))

;; Analytics data storage
(define-data-var analytics-enabled bool true)
(define-data-var platform-start-height uint u0)

(define-map daily-stats uint {
    jobs-completed: uint,
    total-volume: uint,
    new-freelancers: uint,
    new-clients: uint,
    disputes-created: uint,
    disputes-resolved: uint,
    milestones-created: uint,
    milestones-completed: uint,
    templates-created: uint,
    templates-used: uint
})

(define-map monthly-stats uint {
    total-jobs: uint,
    total-volume: uint,
    average-job-rating: uint,
    active-freelancers: uint,
    active-clients: uint,
    platform-fees-collected: uint,
    top-skill-category: uint,
    growth-rate: uint
})

(define-map user-activity-stats principal {
    first-activity: uint,
    last-activity: uint,
    total-transactions: uint,
    user-type: (string-ascii 20), ;; "client", "freelancer", "both"
    streak-days: uint,
    peak-rating: uint
})

(define-map skill-category-stats uint {
    total-jobs: uint,
    total-volume: uint,
    average-rating: uint,
    unique-freelancers: uint,
    growth-trend: (string-ascii 20) ;; "up", "down", "stable"
})

(define-map platform-milestones uint {
    milestone-name: (string-ascii 128),
    target-value: uint,
    current-value: uint,
    achieved: bool,
    achievement-date: (optional uint),
    category: (string-ascii 32) ;; "volume", "users", "jobs", "quality"
})

(define-data-var last-milestone-key uint u0)

;; Initialize platform tracking
(begin
    (var-set platform-start-height stacks-block-height)
    ;; Set initial milestones
    (map-set platform-milestones u1 {
        milestone-name: "First 100 Jobs Completed",
        target-value: u100,
        current-value: u0,
        achieved: false,
        achievement-date: none,
        category: "jobs"
    })
    (map-set platform-milestones u2 {
        milestone-name: "1M STX in Total Volume",
        target-value: u1000000000000,
        current-value: u0,
        achieved: false,
        achievement-date: none,
        category: "volume"
    })
    (map-set platform-milestones u3 {
        milestone-name: "500 Active Users",
        target-value: u500,
        current-value: u0,
        achieved: false,
        achievement-date: none,
        category: "users"
    })
    (var-set last-milestone-key u3)
)

;; Read-only analytics functions
(define-read-only (get-daily-stats (day uint))
    (default-to {
        jobs-completed: u0,
        total-volume: u0,
        new-freelancers: u0,
        new-clients: u0,
        disputes-created: u0,
        disputes-resolved: u0,
        milestones-created: u0,
        milestones-completed: u0,
        templates-created: u0,
        templates-used: u0
    } (map-get? daily-stats day))
)

(define-read-only (get-monthly-stats (month uint))
    (map-get? monthly-stats month)
)

(define-read-only (get-user-activity-stats (user principal))
    (map-get? user-activity-stats user)
)

(define-read-only (get-skill-category-stats (skill-id uint))
    (map-get? skill-category-stats skill-id)
)

(define-read-only (get-platform-milestone (milestone-id uint))
    (map-get? platform-milestones milestone-id)
)

(define-read-only (is-analytics-enabled)
    (var-get analytics-enabled)
)

(define-read-only (get-platform-overview)
    (let ((current-day (get-day-from-height stacks-block-height))
          (total-tokens (var-get last-token-id))
          (total-disputes (var-get last-dispute-id))
          (total-milestones (var-get last-milestone-id))
          (total-templates (var-get last-template-id)))
        {
            platform-age-days: (- current-day (get-day-from-height (var-get platform-start-height))),
            total-jobs: total-tokens,
            total-disputes: total-disputes,
            total-milestones: total-milestones,
            total-templates: total-templates,
            platform-fee: (var-get platform-fee),
            analytics-enabled: (var-get analytics-enabled)
        }
    )
)

(define-read-only (get-performance-metrics (timeframe (string-ascii 20)))
    (if (is-eq timeframe "daily")
        (get-daily-performance)
        (if (is-eq timeframe "weekly")
            (get-weekly-performance)
            (if (is-eq timeframe "monthly")
                (get-monthly-performance)
                (err err-invalid-timeframe)
            )
        )
    )
)

(define-private (get-day-from-height (height uint))
    (/ height u144) ;; Approximate blocks per day
)

(define-private (get-daily-performance)
    (let ((today (get-day-from-height stacks-block-height))
          (today-stats (get-daily-stats today))
          (yesterday-stats (get-daily-stats (- today u1))))
        (ok {
            period: "daily",
            jobs-completed: (get jobs-completed today-stats),
            volume: (get total-volume today-stats),
            growth-rate: (calculate-growth-rate 
                         (get jobs-completed yesterday-stats)
                         (get jobs-completed today-stats)),
            new-users: (+ (get new-freelancers today-stats) (get new-clients today-stats))
        })
    )
)

(define-private (get-weekly-performance)
    (let ((today (get-day-from-height stacks-block-height))
          (week-stats (aggregate-week-stats today)))
        (ok {
            period: "weekly",
            jobs-completed: (get total-jobs week-stats),
            volume: (get total-volume week-stats),
            growth-rate: u0,
            new-users: (+ (get active-freelancers week-stats) (get active-clients week-stats))
        })
    )
)

(define-private (get-monthly-performance)
    (let ((current-month (/ (get-day-from-height stacks-block-height) u30))
          (month-stats (get-monthly-stats current-month)))
        (ok {
            period: "monthly",
            jobs-completed: (match month-stats stats (get total-jobs stats) u0),
            volume: (match month-stats stats (get total-volume stats) u0),
            growth-rate: (match month-stats stats (get growth-rate stats) u0),
            new-users: u0
        })
    )
)

(define-private (aggregate-week-stats (end-day uint))
    ;; Simplified aggregation - in practice would sum daily stats
    {
        total-jobs: u0,
        total-volume: u0,
        active-freelancers: u0,
        active-clients: u0
    }
)

(define-private (calculate-growth-rate (previous uint) (current uint))
    (if (is-eq previous u0)
        u100 ;; 100% growth from zero
        (if (> current previous)
            (/ (* (- current previous) u100) previous)
            u0
        )
    )
)

;; Analytics update functions (called internally)
(define-private (update-daily-analytics (job-volume uint) (event-type (string-ascii 20)))
    (if (var-get analytics-enabled)
        (let ((today (get-day-from-height stacks-block-height))
              (current-stats (get-daily-stats today)))
            (if (is-eq event-type "job-completed")
                (map-set daily-stats today (merge current-stats {
                    jobs-completed: (+ (get jobs-completed current-stats) u1),
                    total-volume: (+ (get total-volume current-stats) job-volume)
                }))
                (if (is-eq event-type "dispute-created")
                    (map-set daily-stats today (merge current-stats {
                        disputes-created: (+ (get disputes-created current-stats) u1)
                    }))
                    (if (is-eq event-type "milestone-completed")
                        (map-set daily-stats today (merge current-stats {
                            milestones-completed: (+ (get milestones-completed current-stats) u1)
                        }))
                        (map-set daily-stats today (merge current-stats {
                            templates-used: (+ (get templates-used current-stats) u1)
                        }))
                    )
                )
            )
            true
        )
        false
    )
)

(define-private (update-user-activity (user principal) (activity-type (string-ascii 20)))
    (if (var-get analytics-enabled)
        (let ((current-stats (default-to {
                first-activity: stacks-block-height,
                last-activity: stacks-block-height,
                total-transactions: u0,
                user-type: "unknown",
                streak-days: u1,
                peak-rating: u0
              } (get-user-activity-stats user))))
            (map-set user-activity-stats user (merge current-stats {
                last-activity: stacks-block-height,
                total-transactions: (+ (get total-transactions current-stats) u1),
                user-type: activity-type
            }))
            true
        )
        false
    )
)

(define-private (check-and-update-milestones (metric-type (string-ascii 20)) (value uint))
    (let ((milestone-1 (get-platform-milestone u1))
          (milestone-2 (get-platform-milestone u2)))
        (match milestone-1
            m1 (if (and (is-eq metric-type "jobs") (not (get achieved m1)))
                   (if (>= value (get target-value m1))
                       (map-set platform-milestones u1 (merge m1 {
                           current-value: value,
                           achieved: true,
                           achievement-date: (some stacks-block-height)
                       }))
                       (map-set platform-milestones u1 (merge m1 {
                           current-value: value
                       }))
                   )
                   true
               )
            true
        )
        true
    )
)

;; Public analytics management functions
(define-public (toggle-analytics)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set analytics-enabled (not (var-get analytics-enabled)))
        (ok (var-get analytics-enabled))
    )
)

(define-public (create-custom-milestone 
    (name (string-ascii 128))
    (target-value uint)
    (category (string-ascii 32)))
    (let ((milestone-id (+ (var-get last-milestone-key) u1)))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> target-value u0) err-insufficient-funds)
        
        (map-set platform-milestones milestone-id {
            milestone-name: name,
            target-value: target-value,
            current-value: u0,
            achieved: false,
            achievement-date: none,
            category: category
        })
        
        (var-set last-milestone-key milestone-id)
        (ok milestone-id)
    )
)

(define-public (export-analytics-snapshot)
    (begin
        (asserts! (var-get analytics-enabled) err-analytics-disabled)
        (let ((overview (get-platform-overview))
              (daily-perf (unwrap-panic (get-daily-performance)))
              (milestone-1 (get-platform-milestone u1))
              (milestone-2 (get-platform-milestone u2)))
            (ok {
                snapshot-height: stacks-block-height,
                platform-overview: overview,
                daily-performance: daily-perf,
                key-milestones: {
                    jobs-milestone: milestone-1,
                    volume-milestone: milestone-2
                }
            })
        )
    )
)

;; Enhanced mint function with analytics tracking
(define-private (track-job-completion (payment-amount uint))
    (begin
        (update-daily-analytics payment-amount "job-completed")
        (update-user-activity tx-sender "freelancer")
        (check-and-update-milestones "jobs" (var-get last-token-id))
        (check-and-update-milestones "volume" payment-amount)
        true
    )
)

;; Integration hooks for existing functions (minimal modifications)
;; These would be called from existing functions to update analytics

;; Reputation Badge System - New Independent Feature
(define-data-var last-badge-id uint u0)

(define-map badge-definitions uint {
    name: (string-ascii 64),
    description: (string-ascii 256),
    badge-type: (string-ascii 32),
    requirement-type: (string-ascii 32),
    requirement-value: uint,
    rarity: (string-ascii 20),
    active: bool,
    created-at: uint
})

(define-map user-badges {user: principal, badge-id: uint} {
    earned-at: uint,
    progress-value: uint,
    tier: uint,
    visible: bool
})

(define-map badge-holders uint (list 100 principal))
(define-map user-badge-list principal (list 50 uint))

(define-map badge-progress {user: principal, badge-id: uint} {
    current-value: uint,
    last-updated: uint,
    locked: bool
})

(begin
    (map-set badge-definitions u1 {
        name: "First Steps",
        description: "Complete your first job on the platform",
        badge-type: "achievement",
        requirement-type: "jobs-completed",
        requirement-value: u1,
        rarity: "common",
        active: true,
        created-at: stacks-block-height
    })
    (map-set badge-definitions u2 {
        name: "Rising Star",
        description: "Earn a 5-star average rating across 10 jobs",
        badge-type: "achievement",
        requirement-type: "rating-milestone",
        requirement-value: u10,
        rarity: "rare",
        active: true,
        created-at: stacks-block-height
    })
    (map-set badge-definitions u3 {
        name: "Veteran Freelancer",
        description: "Successfully complete 50 jobs",
        badge-type: "achievement",
        requirement-type: "jobs-completed",
        requirement-value: u50,
        rarity: "epic",
        active: true,
        created-at: stacks-block-height
    })
    (map-set badge-definitions u4 {
        name: "High Earner",
        description: "Accumulate 100,000 STX in total earnings",
        badge-type: "achievement",
        requirement-type: "total-earnings",
        requirement-value: u100000000000,
        rarity: "epic",
        active: true,
        created-at: stacks-block-height
    })
    (map-set badge-definitions u5 {
        name: "Trusted Client",
        description: "Post and complete 25 jobs as a client",
        badge-type: "achievement",
        requirement-type: "client-jobs",
        requirement-value: u25,
        rarity: "rare",
        active: true,
        created-at: stacks-block-height
    })
    (map-set badge-definitions u6 {
        name: "Master Specialist",
        description: "Earn certification in 5 different skills",
        badge-type: "achievement",
        requirement-type: "certifications",
        requirement-value: u5,
        rarity: "legendary",
        active: true,
        created-at: stacks-block-height
    })
    (map-set badge-definitions u7 {
        name: "Dispute Resolver",
        description: "Complete 20 jobs without any disputes",
        badge-type: "achievement",
        requirement-type: "dispute-free",
        requirement-value: u20,
        rarity: "rare",
        active: true,
        created-at: stacks-block-height
    })
    (map-set badge-definitions u8 {
        name: "Early Adopter",
        description: "Join platform within first 1000 blocks",
        badge-type: "special",
        requirement-type: "early-join",
        requirement-value: u1000,
        rarity: "legendary",
        active: true,
        created-at: stacks-block-height
    })
    (var-set last-badge-id u8)
)

(define-read-only (get-badge-definition (badge-id uint))
    (map-get? badge-definitions badge-id)
)

(define-read-only (get-user-badge (user principal) (badge-id uint))
    (map-get? user-badges {user: user, badge-id: badge-id})
)

(define-read-only (get-badge-progress (user principal) (badge-id uint))
    (map-get? badge-progress {user: user, badge-id: badge-id})
)

(define-read-only (get-user-badges (user principal))
    (default-to (list) (map-get? user-badge-list user))
)

(define-read-only (get-badge-holders (badge-id uint))
    (default-to (list) (map-get? badge-holders badge-id))
)

(define-read-only (get-badge-count (user principal))
    (len (get-user-badges user))
)

(define-read-only (has-badge (user principal) (badge-id uint))
    (is-some (get-user-badge user badge-id))
)

(define-read-only (get-all-active-badges)
    (let ((badge-ids (list u1 u2 u3 u4 u5 u6 u7 u8)))
        (filter is-active-badge badge-ids)
    )
)

(define-private (is-active-badge (badge-id uint))
    (match (get-badge-definition badge-id)
        badge (get active badge)
        false
    )
)

(define-read-only (check-badge-eligibility (user principal) (badge-id uint))
    (let ((badge-def (unwrap! (get-badge-definition badge-id) (err err-badge-not-found)))
          (user-reputation (get-reputation-score user))
          (user-earnings (get-total-earnings user))
          (requirement-type (get requirement-type badge-def))
          (requirement-value (get requirement-value badge-def)))
        (if (is-some (get-user-badge user badge-id))
            (err err-badge-already-earned)
            (ok (check-requirement user requirement-type requirement-value user-reputation user-earnings))
        )
    )
)

(define-private (check-requirement 
    (user principal) 
    (req-type (string-ascii 32)) 
    (req-value uint) 
    (reputation (optional {total-jobs: uint, average-rating: uint, total-earnings: uint})) 
    (earnings uint))
    (if (is-eq req-type "jobs-completed")
        (match reputation
            rep (>= (get total-jobs rep) req-value)
            false
        )
        (if (is-eq req-type "rating-milestone")
            (match reputation
                rep (and (>= (get total-jobs rep) req-value) (is-eq (get average-rating rep) u5))
                false
            )
            (if (is-eq req-type "total-earnings")
                (>= earnings req-value)
                (if (is-eq req-type "client-jobs")
                    (>= (len (get-client-jobs user)) req-value)
                    (if (is-eq req-type "certifications")
                        (>= (get count (count-certifications user)) req-value)
                        (if (is-eq req-type "dispute-free")
                            (check-dispute-free-streak user req-value)
                            (if (is-eq req-type "early-join")
                                (check-early-adopter user req-value)
                                false
                            )
                        )
                    )
                )
            )
        )
    )
)

(define-private (count-certifications (user principal))
    (let ((skill-ids (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10)))
        (fold count-certified-skills skill-ids {user: user, count: u0})
    )
)

(define-private (count-certified-skills (skill-id uint) (acc {user: principal, count: uint}))
    (let ((user (get user acc))
          (current-count (get count acc)))
        {user: user, count: (if (is-skill-certified user skill-id) (+ current-count u1) current-count)}
    )
)

(define-private (is-skill-certified (user principal) (skill-id uint))
    (match (get-freelancer-skill user skill-id)
        skill (get certified skill)
        false
    )
)

(define-private (check-dispute-free-streak (user principal) (required-jobs uint))
    (let ((portfolio (get-freelancer-portfolio user))
          (recent-jobs (if (> (len portfolio) required-jobs)
                          (unwrap-panic (slice? portfolio (- (len portfolio) required-jobs) (len portfolio)))
                          portfolio)))
        (and 
            (>= (len recent-jobs) required-jobs)
            (is-eq (fold count-disputes recent-jobs u0) u0)
        )
    )
)

(define-private (count-disputes (token-id uint) (acc uint))
    (match (get-work-metadata token-id)
        metadata (if (is-some (get dispute-id metadata)) (+ acc u1) acc)
        acc
    )
)

(define-private (check-early-adopter (user principal) (block-limit uint))
    (match (get-user-activity-stats user)
        stats (<= (- (get first-activity stats) (var-get platform-start-height)) block-limit)
        false
    )
)

(define-public (award-badge (user principal) (badge-id uint))
    (let ((badge-def (unwrap! (get-badge-definition badge-id) err-badge-not-found))
          (eligible (unwrap! (check-badge-eligibility user badge-id) err-requirements-not-met)))
        (asserts! (get active badge-def) err-badge-not-found)
        (asserts! eligible err-requirements-not-met)
        
        (map-set user-badges {user: user, badge-id: badge-id} {
            earned-at: stacks-block-height,
            progress-value: (get requirement-value badge-def),
            tier: u1,
            visible: true
        })
        
        (let ((user-badge-ids (get-user-badges user)))
            (map-set user-badge-list user 
                (unwrap-panic (as-max-len? (append user-badge-ids badge-id) u50)))
        )
        
        (let ((holders (get-badge-holders badge-id)))
            (map-set badge-holders badge-id 
                (unwrap-panic (as-max-len? (append holders user) u100)))
        )
        
        (ok badge-id)
    )
)

(define-public (claim-badge (badge-id uint))
    (award-badge tx-sender badge-id)
)

(define-public (auto-check-and-award-badges (user principal))
    (let ((badge-ids (list u1 u2 u3 u4 u5 u6 u7 u8)))
        (fold check-and-award-single-badge badge-ids {user: user, badges-earned: (list)})
        (ok true)
    )
)

(define-private (check-and-award-single-badge 
    (badge-id uint) 
    (context {user: principal, badges-earned: (list 10 uint)}))
    (let ((user (get user context))
          (badges (get badges-earned context)))
        (match (check-badge-eligibility user badge-id)
            ok-result (if ok-result
                         (begin
                             (unwrap-panic (award-badge user badge-id))
                             {user: user, badges-earned: (unwrap-panic (as-max-len? (append badges badge-id) u10))}
                         )
                         context
                     )
            err-result context
        )
    )
)

(define-public (update-badge-visibility (badge-id uint) (visible bool))
    (let ((user-badge (unwrap! (get-user-badge tx-sender badge-id) err-badge-not-found)))
        (map-set user-badges {user: tx-sender, badge-id: badge-id} 
            (merge user-badge {visible: visible}))
        (ok true)
    )
)

(define-public (create-custom-badge
    (name (string-ascii 64))
    (description (string-ascii 256))
    (badge-type (string-ascii 32))
    (requirement-type (string-ascii 32))
    (requirement-value uint)
    (rarity (string-ascii 20)))
    (let ((badge-id (+ (var-get last-badge-id) u1)))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> requirement-value u0) err-requirements-not-met)
        
        (map-set badge-definitions badge-id {
            name: name,
            description: description,
            badge-type: badge-type,
            requirement-type: requirement-type,
            requirement-value: requirement-value,
            rarity: rarity,
            active: true,
            created-at: stacks-block-height
        })
        
        (var-set last-badge-id badge-id)
        (ok badge-id)
    )
)

(define-public (deactivate-badge (badge-id uint))
    (let ((badge (unwrap! (get-badge-definition badge-id) err-badge-not-found)))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set badge-definitions badge-id (merge badge {active: false}))
        (ok true)
    )
)

(define-read-only (get-user-badge-showcase (user principal))
    (let ((all-badges (get-user-badges user)))
        {
            total-badges: (len all-badges),
            visible-badges: (filter-visible-badges user all-badges),
            badge-count-by-rarity: (count-badges-by-rarity user all-badges),
            latest-badge: (get-latest-badge user all-badges)
        }
    )
)

(define-private (filter-visible-badges (user principal) (badge-ids (list 50 uint)))
    (fold collect-visible-badges badge-ids {user: user, visible: (list)})
)

(define-private (collect-visible-badges (badge-id uint) (acc {user: principal, visible: (list 50 uint)}))
    (let ((user (get user acc))
          (visible-list (get visible acc)))
        {user: user, 
         visible: (if (is-badge-visible user badge-id)
                     (unwrap-panic (as-max-len? (append visible-list badge-id) u50))
                     visible-list)}
    )
)

(define-private (is-badge-visible (user principal) (badge-id uint))
    (match (get-user-badge user badge-id)
        badge (get visible badge)
        false
    )
)

(define-private (count-badges-by-rarity (user principal) (badge-ids (list 50 uint)))
    (fold accumulate-rarity badge-ids {user: user, common: u0, rare: u0, epic: u0, legendary: u0})
)

(define-private (accumulate-rarity 
    (badge-id uint) 
    (acc {user: principal, common: uint, rare: uint, epic: uint, legendary: uint}))
    (match (get-user-badge (get user acc) badge-id)
        user-badge (match (get-badge-definition badge-id)
                       badge-def (let ((rarity (get rarity badge-def)))
                                     (if (is-eq rarity "common")
                                         (merge acc {common: (+ (get common acc) u1)})
                                         (if (is-eq rarity "rare")
                                             (merge acc {rare: (+ (get rare acc) u1)})
                                             (if (is-eq rarity "epic")
                                                 (merge acc {epic: (+ (get epic acc) u1)})
                                                 (if (is-eq rarity "legendary")
                                                     (merge acc {legendary: (+ (get legendary acc) u1)})
                                                     acc
                                                 )
                                             )
                                         )
                                     )
                                 )
                       acc
                   )
        acc
    )
)

(define-private (get-latest-badge (user principal) (badge-ids (list 50 uint)))
    (fold find-latest-badge badge-ids {user: user, latest-id: u0, latest-height: u0})
)

(define-private (find-latest-badge 
    (badge-id uint) 
    (acc {user: principal, latest-id: uint, latest-height: uint}))
    (match (get-user-badge (get user acc) badge-id)
        badge (if (> (get earned-at badge) (get latest-height acc))
                  {user: (get user acc), latest-id: badge-id, latest-height: (get earned-at badge)}
                  acc
              )
        acc
    )
)
