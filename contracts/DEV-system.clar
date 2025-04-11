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
;; Vote in an election
(define-public (vote (election-id uint) (proposal-id uint))
  (let
    ((election (unwrap! (map-get? elections { election-id: election-id }) ERR_ELECTION_NOT_FOUND))
     (proposal (unwrap! (map-get? proposals { election-id: election-id, proposal-id: proposal-id }) ERR_PROPOSAL_NOT_FOUND))
     (voter-record (default-to { registered: false, has-voted: false } 
                    (map-get? election-voters { election-id: election-id, voter: tx-sender }))))
    
    ;; Check if election is in VotingOpen status
    (asserts! (is-eq (get status election) u2) ERR_INVALID_STATUS)
    
    ;; Check if proposal is valid
    (asserts! (and (> proposal-id u0) (<= proposal-id (get proposal-count election))) ERR_PROPOSAL_NOT_FOUND)
    
    ;; Check if voter hasn't already voted
    (asserts! (not (get has-voted voter-record)) ERR_ALREADY_VOTED)
    
    ;; Check voter eligibility based on verification method
    (asserts!
      (or
        ;; Whitelist verification
        (and
          (is-eq (get verification-method election) u0)
          (get registered voter-record)
        )
        ;; Token holding verification would need to be implemented
        ;; This would require checking token balance
        false
      )
      ERR_NOT_REGISTERED
    )
    
    ;; Record the vote by updating proposal vote count
    (map-set proposals
      { election-id: election-id, proposal-id: proposal-id }
      (merge proposal { vote-count: (+ (get vote-count proposal) u1) })
    )
    
    ;; Mark voter as having voted
    (map-set election-voters
      { election-id: election-id, voter: tx-sender }
      (merge voter-record { has-voted: true })
    )
    
    ;; Store the voter's choice
    (map-set voter-proposal-votes
      { voter: tx-sender, election-id: election-id }
      { proposal-id: proposal-id }
    )
    
    ;; Update total votes cast
    (map-set elections
      { election-id: election-id }
      (merge election { total-votes-cast: (+ (get total-votes-cast election) u1) })
    )
    
    (ok true)
  )
)

;; Get election details
(define-read-only (get-election-details (election-id uint))
  (map-get? elections { election-id: election-id })
)

;; Get proposal details
(define-read-only (get-proposal-details (election-id uint) (proposal-id uint))
  (map-get? proposals { election-id: election-id, proposal-id: proposal-id })
)

;; Get voter information for an election
(define-read-only (get-voter-info (election-id uint) (voter principal))
  (map-get? election-voters { election-id: election-id, voter: voter })
)

;; Get which proposal a voter voted for
(define-read-only (get-voter-choice (election-id uint) (voter principal))
  (let ((election (unwrap! (map-get? elections { election-id: election-id }) ERR_ELECTION_NOT_FOUND))
        (voter-record (unwrap! (map-get? election-voters { election-id: election-id, voter: voter }) ERR_NOT_REGISTERED)))
    
    ;; If election is private and results aren't published,
    ;; only the voter or an election manager can see their choice
    (if (and (get private-voting election) 
             (not (get results-published election))
             (not (or (is-eq tx-sender voter) (is-election-manager tx-sender))))
      (err ERR_UNAUTHORIZED)
      (map-get? voter-proposal-votes { voter: voter, election-id: election-id })
    )
  )
)

;; Batch register multiple voters
(define-public (batch-register-voters (election-id uint) (voters (list 10 principal)))
  (let
    ((election (unwrap! (map-get? elections { election-id: election-id }) ERR_ELECTION_NOT_FOUND)))
    
    ;; Check if caller is an election manager
    (asserts! (is-election-manager tx-sender) ERR_UNAUTHORIZED)
    
    ;; Check if election is in Created or RegisteringVoters status
    (asserts! (or (is-eq (get status election) u0) (is-eq (get status election) u1)) ERR_INVALID_STATUS)
    
    ;; Check if using whitelist verification
    (asserts! (is-eq (get verification-method election) u0) ERR_INVALID_STATUS)
    
    ;; Register all voters
    (ok (map register-voter-helper (map election-id-tuple voters)))
  )
)

;; Helper function for batch registration
(define-private (register-voter-helper (tuple-data {election-id: uint, voter: principal}))
  (let
    ((election-id (get election-id tuple-data))
     (voter (get voter tuple-data))
     (voter-record (default-to { registered: false, has-voted: false } 
                     (map-get? election-voters { election-id: election-id, voter: voter }))))
    
    ;; Register the voter if not already registered
    (if (not (get registered voter-record))
      (map-set election-voters
        { election-id: election-id, voter: voter }
        { registered: true, has-voted: false }
      )
      true
    )
  )
)

;; Helper for creating election-id tuples
(define-private (election-id-tuple (voter principal))
  {election-id: (var-get next-election-id), voter: voter}
)

;; Get all proposals for an election
(define-read-only (get-all-proposals (election-id uint))
  (let ((election (unwrap! (map-get? elections { election-id: election-id }) ERR_ELECTION_NOT_FOUND)))
    (generate-proposal-list election-id u1 (get proposal-count election))
  )
)

;; Helper function to generate a list of proposals
(define-private (generate-proposal-list (election-id uint) (current-id uint) (max-id uint))
  (if (> current-id max-id)
    (list)
    (let ((proposal (map-get? proposals { election-id: election-id, proposal-id: current-id })))
      (if (is-some proposal)
        (cons (unwrap-panic proposal) (generate-proposal-list election-id (+ current-id u1) max-id))
        (generate-proposal-list election-id (+ current-id u1) max-id)
      )
    )
  )
)