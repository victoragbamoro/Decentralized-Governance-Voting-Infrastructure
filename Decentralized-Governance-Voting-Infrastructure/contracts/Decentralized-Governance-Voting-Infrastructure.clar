
;; title: Decentralized-Governance-Voting-Infrastructure
;; Constants and Error Codes
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u1))
(define-constant ERR-INVALID-PROPOSAL (err u2))
(define-constant ERR-INSUFFICIENT-TOKENS (err u3))
(define-constant ERR-ALREADY-VOTED (err u4))
(define-constant ERR-PROPOSAL-CLOSED (err u5))
(define-constant ERR-INVALID-DELEGATION (err u6))
(define-constant ERR-EXCEEDED-DELEGATION-DEPTH (err u7))
(define-constant ERR-PROPOSAL-EXECUTION-FAILED (err u8))
(define-constant ERR-COOLDOWN-PERIOD (err u9))
(define-constant ERR-INVALID-TIMELOCK (err u10))
(define-constant ERR-VOTE-QUORUM-NOT-REACHED (err u11))
(define-constant ERR-TREASURY-LIMIT-EXCEEDED (err u12))


;; Governance Token - SBT (Semi-Bound Token) for Voting Power
(define-fungible-token governance-token u10000000)

;; Proposal Types Enum (using string for flexibility)
(define-constant PROPOSAL-TYPES 
  {
    GOVERNANCE: "governance",
    TREASURY: "treasury",
    PARAMETER-UPDATE: "parameter-update",
    ECOSYSTEM: "ecosystem"
  }
)

;; Proposal Struct Map
(define-map proposals 
  {proposal-id: uint}
  {
    title: (string-utf8 100),
    description: (string-utf8 500),
    proposed-by: principal,
    start-block: uint,
    end-block: uint,
    proposal-type: (string-ascii 20),
    vote-for: uint,
    vote-against: uint,
    executed: bool,
    execution-result: (optional bool),
    quorum-threshold: uint,
    pass-threshold: uint
  }
)

;; Voting Records
(define-map votes 
  {proposal-id: uint, voter: principal}
  {
    voting-power: uint,
    vote-type: bool,
    quadratic-weight: uint,
    timestamp: uint
  }
)

;; Delegation Mapping
(define-map delegations 
  principal 
  {
    delegated-to: principal,
    delegation-depth: uint,
    max-delegation-depth: uint,
    delegated-at: uint
  }
)

;; Proposal Tracking
(define-data-var next-proposal-id uint u0)
(define-data-var total-governance-tokens uint u0)

;; Emergency Pause Mechanism
(define-data-var contract-paused bool false)

;; Token Distribution and Management
(define-public (mint-governance-token (amount uint) (recipient principal))
  (begin
    (try! (ft-mint? governance-token amount recipient))
    (var-set total-governance-tokens 
      (+ (var-get total-governance-tokens) amount)
    )
    (ok true)
  )
)

;; Create a New Proposal
(define-public (create-proposal 
  (title (string-utf8 100)) 
  (description (string-utf8 500))
  (proposal-type (string-ascii 20))
  (duration uint)
  (quorum-threshold uint)
  (pass-threshold uint)
)
  (let 
    (
      (proposal-id (var-get next-proposal-id))
      (current-block stacks-block-height)
    )
    ;; Validation Checks
    (asserts! (> (ft-get-balance governance-token tx-sender) u0) ERR-INSUFFICIENT-TOKENS)
    (asserts! (or 
      (is-eq proposal-type (get GOVERNANCE PROPOSAL-TYPES))
      (is-eq proposal-type (get TREASURY PROPOSAL-TYPES))
      (is-eq proposal-type (get PARAMETER-UPDATE PROPOSAL-TYPES))
      (is-eq proposal-type (get ECOSYSTEM PROPOSAL-TYPES))
    ) ERR-INVALID-PROPOSAL)
    
    ;; Store Proposal
    (map-set proposals 
      {proposal-id: proposal-id}
      {
        title: title,
        description: description,
        proposed-by: tx-sender,
        start-block: current-block,
        end-block: (+ current-block duration),
        proposal-type: proposal-type,
        vote-for: u0,
        vote-against: u0,
        executed: false,
        execution-result: none,
        quorum-threshold: quorum-threshold,
        pass-threshold: pass-threshold
      }
    )
    
    ;; Increment Proposal ID
    (var-set next-proposal-id (+ proposal-id u1))
    
    (ok proposal-id)
  )
)

;; Quadratic Voting Mechanism
(define-public (cast-quadratic-vote 
  (proposal-id uint) 
  (vote-type bool)
)
  (let 
    (
      (proposal (unwrap! (map-get? proposals {proposal-id: proposal-id}) ERR-INVALID-PROPOSAL))
      (voter-balance (ft-get-balance governance-token tx-sender))
      (quadratic-weight (sqrti voter-balance))
      (current-block stacks-block-height)
    )
    ;; Validation Checks
    (asserts! (not (var-get contract-paused)) ERR-UNAUTHORIZED)
    (asserts! (< current-block (get end-block proposal)) ERR-PROPOSAL-CLOSED)
    (asserts! (is-none (map-get? votes {proposal-id: proposal-id, voter: tx-sender})) ERR-ALREADY-VOTED)
    
    ;; Record Vote with Quadratic Weighting
    (map-set votes 
      {proposal-id: proposal-id, voter: tx-sender}
      {
        voting-power: voter-balance,
        vote-type: vote-type,
        quadratic-weight: quadratic-weight,
        timestamp: current-block
      }
    )
    
    ;; Update Proposal Vote Totals
    (if vote-type 
      (map-set proposals 
        {proposal-id: proposal-id}
        (merge proposal {vote-for: (+ (get vote-for proposal) quadratic-weight)})
      )
      (map-set proposals 
        {proposal-id: proposal-id}
        (merge proposal {vote-against: (+ (get vote-against proposal) quadratic-weight)})
      )
    )
    
    (ok true)
  )
)

;; Delegation System with Advanced Features
(define-public (delegate-voting-power 
  (delegate principal)
  (max-depth uint)
)
  (let 
    (
      (current-block stacks-block-height)
      (current-delegation (map-get? delegations tx-sender))
    )
    ;; Validation Checks
    (asserts! (not (is-eq tx-sender delegate)) ERR-INVALID-DELEGATION)
    (asserts! (or (is-none current-delegation) (< (unwrap-panic (get delegation-depth current-delegation)) max-depth)) ERR-EXCEEDED-DELEGATION-DEPTH)
    
    ;; Set Delegation
    (map-set delegations 
      tx-sender 
      {
        delegated-to: delegate,
        delegation-depth: u0,
        max-delegation-depth: max-depth,
        delegated-at: current-block
      }
    )
    
    (ok true)
  )
)

;; Execute Proposal with Advanced Validation
(define-public (execute-proposal (proposal-id uint))
  (let 
    (
      (proposal (unwrap! (map-get? proposals {proposal-id: proposal-id}) ERR-INVALID-PROPOSAL))
      (current-block stacks-block-height)
      (total-tokens (var-get total-governance-tokens))
    )
    ;; Validation Checks
    (asserts! (>= current-block (get end-block proposal)) ERR-PROPOSAL-CLOSED)
    (asserts! (not (get executed proposal)) ERR-UNAUTHORIZED)
    
    ;; Quorum and Threshold Validation
    (let 
      (
        (total-votes (+ (get vote-for proposal) (get vote-against proposal)))
        (quorum-percentage (/ (* total-votes u100) total-tokens))
        (vote-for-percentage (/ (* (get vote-for proposal) u100) total-votes))
      )
      ;; Check Quorum and Pass Thresholds
      (asserts! (>= quorum-percentage (get quorum-threshold proposal)) ERR-PROPOSAL-EXECUTION-FAILED)
      (asserts! (>= vote-for-percentage (get pass-threshold proposal)) ERR-PROPOSAL-EXECUTION-FAILED)
      
      ;; Determine Proposal Outcome
      (let 
        (
          (outcome (> (get vote-for proposal) (get vote-against proposal)))
        )
        ;; Update Proposal Status
        (map-set proposals 
          {proposal-id: proposal-id}
          (merge proposal 
            {
              executed: true,
              execution-result: (some outcome)
            }
          )
        )
        
        (ok outcome)
      )
    )
  )
)

;; Get Proposal Details
(define-read-only (get-proposal-details (proposal-id uint))
  (map-get? proposals {proposal-id: proposal-id})
)

;; Get Voting Power
(define-read-only (get-voting-power (voter principal))
  (ft-get-balance governance-token voter)
)

;; Revoke Delegation
(define-public (revoke-delegation)
  (begin
    (map-delete delegations tx-sender)
    (ok true)
  )
)

;; Admin Functions
;; Upgrade Governance Parameters (Controlled by Contract Owner)
(define-public (upgrade-governance-params 
  (new-max-delegation-depth uint)
)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    ;; Future expansion for upgrading governance parameters
    (ok true)
  )
)

;; Emergency Pause Mechanism
(define-public (toggle-contract-pause)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (var-set contract-paused (not (var-get contract-paused)))
    (ok (var-get contract-paused))
  )
)

;; Advanced Governance Metrics
(define-read-only (get-governance-metrics)
  {
    total-governance-tokens: (var-get total-governance-tokens),
    total-proposals: (var-get next-proposal-id),
    contract-paused: (var-get contract-paused)
  }
)

;; Token Burning Mechanism (Optional)
(define-public (burn-governance-tokens (amount uint))
  (begin
    (try! (ft-burn? governance-token amount tx-sender))
    (var-set total-governance-tokens 
      (- (var-get total-governance-tokens) amount)
    )
    (ok true)
  )
)

;; NEW FEATURE: Vote Types (beyond simple yes/no)
(define-constant VOTE-TYPES 
  {
    FOR: u1,
    AGAINST: u2,
    ABSTAIN: u3
  }
)

;; Governance configuration variables
(define-data-var min-proposal-duration uint u144) ;; Default: ~1 day at 10 min block times
(define-data-var max-proposal-duration uint u4320) ;; Default: ~30 days at 10 min block times
(define-data-var proposal-submission-min-tokens uint u100000) ;; Minimum tokens to submit proposal
(define-data-var treasury-max-per-proposal uint u100000000) ;; 10% of total token supply

;; Treasury management
(define-data-var treasury-balance uint u0)
(define-map treasury-allocations
  {allocation-id: uint}
  {
    proposal-id: uint,
    recipient: principal,
    amount: uint,
    executed: bool
  }
)

(define-data-var next-allocation-id uint u0)

;; Time-lock mechanism
(define-map time-locks
  {proposal-id: uint}
  {
    execution-block: uint,
    executed: bool
  }
)

;; Time-locked proposal execution 
(define-public (schedule-time-locked-execution (proposal-id uint) (delay-blocks uint))
  (let 
    (
      (proposal (unwrap! (map-get? proposals {proposal-id: proposal-id}) ERR-INVALID-PROPOSAL))
      (current-block stacks-block-height)
      (total-tokens (var-get total-governance-tokens))
    )
    ;; Validation Checks
    (asserts! (>= current-block (get end-block proposal)) ERR-PROPOSAL-CLOSED)
    (asserts! (not (get executed proposal)) ERR-UNAUTHORIZED)
    
    ;; Quorum and Threshold Validation
    (let 
      (
        (total-votes (+ (get vote-for proposal) (get vote-against proposal)))
        (quorum-percentage (/ (* total-votes u100) total-tokens))
        (vote-for-percentage (/ (* (get vote-for proposal) u100) total-votes))
      )
      ;; Check Quorum and Pass Thresholds
      (asserts! (>= quorum-percentage (get quorum-threshold proposal)) ERR-PROPOSAL-EXECUTION-FAILED)
      (asserts! (>= vote-for-percentage (get pass-threshold proposal)) ERR-PROPOSAL-EXECUTION-FAILED)
      
      ;; Schedule execution with time lock
      (map-set time-locks
        {proposal-id: proposal-id}
        {
          execution-block: (+ current-block delay-blocks),
          executed: false
        }
      )
      
      (ok true)
    )
  )
)

;; Execute time-locked proposal
(define-public (execute-time-locked-proposal (proposal-id uint))
  (let 
    (
      (proposal (unwrap! (map-get? proposals {proposal-id: proposal-id}) ERR-INVALID-PROPOSAL))
      (time-lock (unwrap! (map-get? time-locks {proposal-id: proposal-id}) ERR-INVALID-TIMELOCK))
      (current-block stacks-block-height)
    )
    ;; Validation Checks
    (asserts! (not (get executed proposal)) ERR-UNAUTHORIZED)
    (asserts! (not (get executed time-lock)) ERR-UNAUTHORIZED)
    (asserts! (>= current-block (get execution-block time-lock)) ERR-INVALID-TIMELOCK)
    
    ;; Update Time Lock Status
    (map-set time-locks
      {proposal-id: proposal-id}
      (merge time-lock {executed: true})
    )
    
    ;; Update Proposal Status
    (map-set proposals 
      {proposal-id: proposal-id}
      (merge proposal 
        {
          executed: true,
          execution-result: (some true)
        }
      )
    )
    
    (ok true)
  )
)

;; Treasury management functions
(define-public (deposit-to-treasury (amount uint))
  (begin
    (try! (ft-transfer? governance-token amount tx-sender (as-contract tx-sender)))
    (var-set treasury-balance (+ (var-get treasury-balance) amount))
    (ok true)
  )
)

;; Create treasury allocation proposal
(define-public (create-treasury-proposal 
  (title (string-utf8 100)) 
  (description (string-utf8 500))
  (duration uint)
  (quorum-threshold uint)
  (pass-threshold uint)
  (recipient principal)
  (amount uint)
)
  (let 
    (
      (proposal-id (var-get next-proposal-id))
      (current-block stacks-block-height)
      (user-token-balance (ft-get-balance governance-token tx-sender))
    )
    ;; Validation Checks
    (asserts! (>= user-token-balance (var-get proposal-submission-min-tokens)) ERR-INSUFFICIENT-TOKENS)
    (asserts! (<= amount (var-get treasury-max-per-proposal)) ERR-TREASURY-LIMIT-EXCEEDED)
    (asserts! (<= amount (var-get treasury-balance)) ERR-TREASURY-LIMIT-EXCEEDED)
    (asserts! (and (>= duration (var-get min-proposal-duration)) (<= duration (var-get max-proposal-duration))) ERR-INVALID-PROPOSAL)
    
    ;; Store Proposal
    (map-set proposals 
      {proposal-id: proposal-id}
      {
        title: title,
        description: description,
        proposed-by: tx-sender,
        start-block: current-block,
        end-block: (+ current-block duration),
        proposal-type: (get TREASURY PROPOSAL-TYPES),
        vote-for: u0,
        vote-against: u0,
        executed: false,
        execution-result: none,
        quorum-threshold: quorum-threshold,
        pass-threshold: pass-threshold
      }
    )
    
    ;; Create Treasury Allocation
    (map-set treasury-allocations
      {allocation-id: (var-get next-allocation-id)}
      {
        proposal-id: proposal-id,
        recipient: recipient,
        amount: amount,
        executed: false
      }
    )
    
    ;; Increment IDs
    (var-set next-proposal-id (+ proposal-id u1))
    (var-set next-allocation-id (+ (var-get next-allocation-id) u1))
    
    (ok proposal-id)
  )
)

;; Execute treasury allocation
(define-public (execute-treasury-allocation (allocation-id uint))
  (let 
    (
      (allocation (unwrap! (map-get? treasury-allocations {allocation-id: allocation-id}) ERR-INVALID-PROPOSAL))
      (proposal-id (get proposal-id allocation))
      (proposal (unwrap! (map-get? proposals {proposal-id: proposal-id}) ERR-INVALID-PROPOSAL))
    )
    ;; Validation Checks
    (asserts! (get executed proposal) ERR-UNAUTHORIZED)
    (asserts! (is-some (get execution-result proposal)) ERR-UNAUTHORIZED)
    (asserts! (unwrap-panic (get execution-result proposal)) ERR-UNAUTHORIZED)
    (asserts! (not (get executed allocation)) ERR-UNAUTHORIZED)
    
    ;; Execute Treasury Transfer
    (try! (as-contract (ft-transfer? governance-token 
                                    (get amount allocation) 
                                    tx-sender 
                                    (get recipient allocation))))
    
    ;; Update Treasury Balance
    (var-set treasury-balance (- (var-get treasury-balance) (get amount allocation)))
    
    ;; Update Allocation Status
    (map-set treasury-allocations
      {allocation-id: allocation-id}
      (merge allocation {executed: true})
    )
    
    (ok true)
  )
)

;; Comprehensive governance parameter update
(define-public (update-governance-parameters
  (new-min-proposal-duration (optional uint))
  (new-max-proposal-duration (optional uint))
  (new-proposal-submission-min-tokens (optional uint))
  (new-treasury-max-per-proposal (optional uint))
)
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    
    ;; Update parameters if provided
    (if (is-some new-min-proposal-duration)
      (var-set min-proposal-duration (unwrap-panic new-min-proposal-duration))
      true
    )
    
    (if (is-some new-max-proposal-duration)
      (var-set max-proposal-duration (unwrap-panic new-max-proposal-duration))
      true
    )
    
    (if (is-some new-proposal-submission-min-tokens)
      (var-set proposal-submission-min-tokens (unwrap-panic new-proposal-submission-min-tokens))
      true
    )
    
    (if (is-some new-treasury-max-per-proposal)
      (var-set treasury-max-per-proposal (unwrap-panic new-treasury-max-per-proposal))
      true
    )
    
    (ok true)
  )
)

;; Enhanced governance metrics
(define-read-only (get-enhanced-governance-metrics)
  {
    total-governance-tokens: (var-get total-governance-tokens),
    total-proposals: (var-get next-proposal-id),
    contract-paused: (var-get contract-paused),
    treasury-balance: (var-get treasury-balance),
    min-proposal-duration: (var-get min-proposal-duration),
    max-proposal-duration: (var-get max-proposal-duration),
    proposal-submission-min-tokens: (var-get proposal-submission-min-tokens),
    treasury-max-per-proposal: (var-get treasury-max-per-proposal)
  }
)

;; Vote by signature verification (future integration)
(define-read-only (verify-vote-signature 
  (signer principal) 
  (proposal-id uint) 
  (vote-type uint)
  (signature (buff 65))
  (message-hash (buff 32))
)
  
  (ok true)
)