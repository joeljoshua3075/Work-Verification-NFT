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
