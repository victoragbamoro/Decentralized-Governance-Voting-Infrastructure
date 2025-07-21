
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
