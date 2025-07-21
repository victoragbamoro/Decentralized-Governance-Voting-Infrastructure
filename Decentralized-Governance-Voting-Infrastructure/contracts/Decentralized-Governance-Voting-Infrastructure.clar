
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
