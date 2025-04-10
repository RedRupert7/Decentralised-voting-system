;; Clarity Decentralized Voting System
;; A secure and transparent voting system implemented in Clarity
test text
;; Error codes
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_ELECTION_NOT_FOUND (err u101))
(define-constant ERR_PROPOSAL_NOT_FOUND (err u102))
(define-constant ERR_INVALID_STATUS (err u103))
(define-constant ERR_ALREADY_VOTED (err u104))
(define-constant ERR_NOT_REGISTERED (err u105))
(define-constant ERR_INVALID_TIME (err u106))
(define-constant ERR_INVALID_SIGNATURE (err u107))
(define-constant ERR_SIGNATURE_USED (err u108))
(define-constant ERR_INSUFFICIENT_TOKENS (err u109))

;; Data variables - election status enum
(define-data-var admin principal tx-sender)

;; Roles mapping - who can manage elections
(define-map election-managers principal bool)

;; Election status enum values
;; 0: Created
;; 1: RegisteringVoters
;; 2: VotingOpen
;; 3: VotingClosed
;; 4: ResultsPublished

;; Verification method enum values
;; 0: Whitelist
;; 1: Signature
;; 2: TokenHolding
;; Define the elections map
(define-map elections
  { election-id: uint }
  {
    name: (string-ascii 100),
    description: (string-ascii 500),
    start-time: uint,
    end-time: uint,
    status: uint,
    creator: principal,
    verification-method: uint,
    minimum-token-holding: uint,
    token-address: (optional principal),
    private-voting: bool,
    proposal-count: uint,
    total-votes-cast: uint,
    results-published: bool
  }
)

;; Define the proposals map
(define-map proposals
  { election-id: uint, proposal-id: uint }
  {
    name: (string-ascii 100),
    description: (string-ascii 500),
    vote-count: uint
  }
)

;; Define the voters map
(define-map election-voters
  { election-id: uint, voter: principal }
  { registered: bool, has-voted: bool }
)

;; Define the voter-proposal-votes map
(define-map voter-proposal-votes
  { voter: principal, election-id: uint }
  { proposal-id: uint }
)

;; Define the used signatures map
(define-map used-signatures
  { signature-hash: (buff 32) }
  { used: bool }
)

;; Store the next election ID
(define-data-var next-election-id uint u1)

;; Read-only function to get the next election ID
(define-read-only (get-next-election-id)
  (var-get next-election-id)
)

;; Initialize contract with sender as admin and election manager
(define-public (initialize)
  (begin
    (var-set admin tx-sender)
    (map-set election-managers tx-sender true)
    (ok true)
  )
)