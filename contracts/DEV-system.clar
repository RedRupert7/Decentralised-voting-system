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

;; Add or remove an election manager
(define-public (set-election-manager (manager principal) (is-manager bool))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) ERR_UNAUTHORIZED)
    (ok (map-set election-managers manager is-manager))
  )
)

;; Check if user is an election manager
(define-read-only (is-election-manager (manager principal))
  (default-to false (map-get? election-managers manager))
)

;; Create a new election
(define-public (create-election
    (name (string-ascii 100))
    (description (string-ascii 500))
    (start-time uint)
    (end-time uint)
    (verification-method uint)
    (minimum-token-holding uint)
    (token-address (optional principal))
    (private-voting bool)
  )
  (let 
    ((election-id (var-get next-election-id)))
    
    ;; Check if caller is an election manager
    (asserts! (is-election-manager tx-sender) ERR_UNAUTHORIZED)
    
    ;; Check timestamps
    (asserts! (> start-time block-height) ERR_INVALID_TIME)
    (asserts! (> end-time start-time) ERR_INVALID_TIME)
    
    ;; Create the election
    (map-set elections
      { election-id: election-id }
      {
        name: name,
        description: description,
        start-time: start-time,
        end-time: end-time,
        status: u0, ;; Created status
        creator: tx-sender,
        verification-method: verification-method,
        minimum-token-holding: minimum-token-holding,
        token-address: token-address,
        private-voting: private-voting,
        proposal-count: u0,
        total-votes-cast: u0,
        results-published: false
      }
    )
    
    ;; Increment the election ID counter
    (var-set next-election-id (+ election-id u1))
    
    ;; Return the new election ID
    (ok election-id)
  )
)

;; Add a proposal to an election
(define-public (add-proposal
    (election-id uint)
    (name (string-ascii 100))
    (description (string-ascii 500))
  )
  (let 
    ((election (unwrap! (map-get? elections { election-id: election-id }) ERR_ELECTION_NOT_FOUND))
     (proposal-id (+ (get proposal-count election) u1)))
    
    ;; Check if caller is an election manager
    (asserts! (is-election-manager tx-sender) ERR_UNAUTHORIZED)
    
    ;; Check if election is in Created status
    (asserts! (is-eq (get status election) u0) ERR_INVALID_STATUS)
    
    ;; Add the proposal
    (map-set proposals
      { election-id: election-id, proposal-id: proposal-id }
      {
        name: name,
        description: description,
        vote-count: u0
      }
    )
    
    ;; Update proposal count in election
    (map-set elections
      { election-id: election-id }
      (merge election { proposal-count: proposal-id })
    )
    ;; Return the new proposal ID
    (ok proposal-id)
  )
)

;; Set the status of an election
(define-public (set-election-status (election-id uint) (new-status uint))
  (let
    ((election (unwrap! (map-get? elections { election-id: election-id }) ERR_ELECTION_NOT_FOUND)))
    
    ;; Check if caller is an election manager
    (asserts! (is-election-manager tx-sender) ERR_UNAUTHORIZED)
    
    ;; Validate status transition
    (asserts!
      (or
        ;; For VotingOpen status
        (and
          (is-eq new-status u2)
          (> (get proposal-count election) u0)
          (>= block-height (get start-time election))
        )
        ;; For VotingClosed status
        (and
          (is-eq new-status u3)
          (or
            (>= block-height (get end-time election))
            (is-eq (get status election) u2)
          )
        )
        ;; For ResultsPublished status
        (and
          (is-eq new-status u4)
          (is-eq (get status election) u3)
        )
        ;; For other status changes, just allow election managers to update
        (and
          (is-election-manager tx-sender)
          (or (is-eq new-status u0) (is-eq new-status u1))
        )
      )
      ERR_INVALID_STATUS
    )
    
    ;; Update election status
    (map-set elections
      { election-id: election-id }
      (merge 
        election 
        { 
          status: new-status,
          results-published: (if (is-eq new-status u4) true (get results-published election))
        }
      )
    )
    
    (ok true)
  )
)

;; Register a voter for an election with whitelist verification
(define-public (register-voter (election-id uint) (voter principal))
  (let
    ((election (unwrap! (map-get? elections { election-id: election-id }) ERR_ELECTION_NOT_FOUND))
     (voter-record (default-to { registered: false, has-voted: false } 
                     (map-get? election-voters { election-id: election-id, voter: voter }))))
    
    ;; Check if caller is an election manager
    (asserts! (is-election-manager tx-sender) ERR_UNAUTHORIZED)
    
    ;; Check if election is in Created or RegisteringVoters status
    (asserts! (or (is-eq (get status election) u0) (is-eq (get status election) u1)) ERR_INVALID_STATUS)
    
    ;; Check if using whitelist verification
    (asserts! (is-eq (get verification-method election) u0) ERR_INVALID_STATUS)
    
    ;; Check if voter is not already registered
    (asserts! (not (get registered voter-record)) ERR_ALREADY_VOTED)
    
    ;; Register the voter
    (map-set election-voters
      { election-id: election-id, voter: voter }
      { registered: true, has-voted: false }
    )
    
    (ok true)
  )
)