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