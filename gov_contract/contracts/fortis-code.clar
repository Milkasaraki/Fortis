;; Governance Token Lockbox
;; Version 3.0: Secure token storage with delegated emergency access
;; This contract implements a secure lockbox for governance tokens with delegation capabilities.
;; The lockbox allows designating "delegates" who can collectively authorize emergency access.

;; Define fungible token trait
(define-trait ft-trait
  (
    ;; Transfer from the caller to a new principal
    (transfer (uint principal principal (optional (buff 34))) (response bool uint))
    ;; Get the token balance of the specified principal
    (get-balance (principal) (response uint uint))
  )
)

;; Error codes
(define-constant ERR_ACCESS_DENIED (err u100))
(define-constant ERR_LOCKBOX_ALREADY_SEALED (err u101))
(define-constant ERR_LOCKBOX_NOT_SEALED (err u102))
(define-constant ERR_DELEGATE_ALREADY_ADDED (err u103))
(define-constant ERR_DELEGATE_NOT_FOUND (err u104))
(define-constant ERR_EMERGENCY_ACCESS_ACTIVE (err u105))
(define-constant ERR_NO_EMERGENCY_ACCESS_ACTIVE (err u106))
(define-constant ERR_ALREADY_ENDORSED (err u107))
(define-constant ERR_NOT_ENOUGH_ENDORSEMENTS (err u108))
(define-constant ERR_ACCESS_REQUEST_EXPIRED (err u109))
(define-constant ERR_INADEQUATE_FUNDS (err u110))
(define-constant ERR_INVALID_CONSENSUS_LEVEL (err u111))
(define-constant ERR_ZERO_PRINCIPAL (err u112))
(define-constant ERR_INVALID_WITHDRAWAL (err u113))
(define-constant ERR_INVALID_TOKEN (err u114))

;; Data variables

;; Primary holder of the lockbox
(define-data-var primary-holder principal tx-sender)

;; Whether the lockbox has been sealed
(define-data-var is-sealed bool false)

;; List of authorized delegates
(define-map authorized-delegates principal bool)

;; Total number of delegates
(define-data-var delegate-total uint u0)

;; Consensus level required for emergency access (percentage 1-100)
(define-data-var consensus-level uint u51)

;; Emergency access state
(define-data-var emergency-access-active bool false)
(define-data-var access-requester (optional principal) none)
(define-data-var temporary-access-recipient (optional principal) none)
(define-data-var access-expiration uint u0)
(define-map access-endorsements principal bool)
(define-data-var endorsement-count uint u0)

;; Constants
(define-constant SECONDS_IN_DAY u86400)
(define-constant ACCESS_WINDOW_DAYS u4)
(define-constant ZERO_PRINCIPAL 'SP000000000000000000002Q6VF78)

;; Read-only functions

;; Check if caller is the primary holder
(define-read-only (is-primary-holder)
  (is-eq tx-sender (var-get primary-holder)))

;; Check if caller is an authorized delegate
(define-read-only (is-authorized-delegate (delegate principal))
  (default-to false (map-get? authorized-delegates delegate)))

;; Get consensus level requirement
(define-read-only (get-consensus-level)
  (var-get consensus-level))

;; Check if emergency access is active
(define-read-only (emergency-access-status)
  {
    active: (var-get emergency-access-active),
    requester: (var-get access-requester),
    temporary-recipient: (var-get temporary-access-recipient),
    expiration: (var-get access-expiration),
    endorsements: (var-get endorsement-count),
    required-endorsements: (calculate-required-endorsements)
  })

;; Calculate required number of endorsements based on consensus level
(define-read-only (calculate-required-endorsements)
  (let 
    (
      (total-delegates (var-get delegate-total))
      (required-level (var-get consensus-level))
    )
    (if (is-eq total-delegates u0)
      u0
      (let
        (
          (required-raw (/ (* total-delegates required-level) u100))
          ;; Round up if there's a remainder
          (has-remainder (> (* required-raw u100) (* total-delegates required-level)))
        )
        (if has-remainder
          (+ required-raw u1)
          required-raw
        )
      )
    )
  ))

;; Get the number of all authorized delegates
(define-read-only (get-delegate-total)
  (ok (var-get delegate-total)))

;; Check if a delegate has endorsed emergency access
(define-read-only (has-endorsed-access (delegate principal))
  (default-to false (map-get? access-endorsements delegate)))

;; Public functions

;; Seal the lockbox
(define-public (seal-lockbox (holder principal) (initial-level uint))
  (begin
    ;; Check if already sealed
    (asserts! (not (var-get is-sealed)) ERR_LOCKBOX_ALREADY_SEALED)
    
    ;; Validate consensus level
    (asserts! (and (>= initial-level u1) (<= initial-level u100)) ERR_INVALID_CONSENSUS_LEVEL)
    
    ;; Validate holder address
    (asserts! (not (is-eq holder ZERO_PRINCIPAL)) ERR_ZERO_PRINCIPAL)
    
    ;; Set holder and mark as sealed
    (var-set primary-holder holder)
    (var-set consensus-level initial-level)
    (var-set is-sealed true)
    
    (ok true)))

;; Add a delegate - only primary holder can add delegates
(define-public (add-delegate (delegate principal))
  (begin
    ;; Check if lockbox is sealed
    (asserts! (var-get is-sealed) ERR_LOCKBOX_NOT_SEALED)
    
    ;; Only primary holder can add delegates
    (asserts! (is-primary-holder) ERR_ACCESS_DENIED)
    
    ;; Validate delegate address
    (asserts! (not (is-eq delegate ZERO_PRINCIPAL)) ERR_ZERO_PRINCIPAL)
    
    ;; Check if delegate already exists
    (asserts! (not (is-authorized-delegate delegate)) ERR_DELEGATE_ALREADY_ADDED)
    
    ;; Add delegate and increment count
    (map-set authorized-delegates delegate true)
    (var-set delegate-total (+ (var-get delegate-total) u1))
    
    (ok true)))

;; Remove a delegate - only primary holder can remove delegates
(define-public (remove-delegate (delegate principal))
  (begin
    ;; Check if lockbox is sealed
    (asserts! (var-get is-sealed) ERR_LOCKBOX_NOT_SEALED)
    
    ;; Only primary holder can remove delegates
    (asserts! (is-primary-holder) ERR_ACCESS_DENIED)
    
    ;; Check that no emergency access is active
    (asserts! (not (var-get emergency-access-active)) ERR_EMERGENCY_ACCESS_ACTIVE)
    
    ;; Check if delegate exists
    (asserts! (is-authorized-delegate delegate) ERR_DELEGATE_NOT_FOUND)
    
    ;; Remove delegate and decrement count
    (map-delete authorized-delegates delegate)
    (var-set delegate-total (- (var-get delegate-total) u1))
    
    (ok true)))

;; Adjust consensus level - only primary holder can change
(define-public (adjust-consensus-level (new-level uint))
  (begin
    ;; Check if lockbox is sealed
    (asserts! (var-get is-sealed) ERR_LOCKBOX_NOT_SEALED)
    
    ;; Only primary holder can change level
    (asserts! (is-primary-holder) ERR_ACCESS_DENIED)
    
    ;; Validate level
    (asserts! (and (>= new-level u1) (<= new-level u100)) ERR_INVALID_CONSENSUS_LEVEL)
    
    ;; Set new level
    (var-set consensus-level new-level)
    
    (ok true)))

;; Request emergency access - only delegates can request
(define-public (request-emergency-access (recipient principal))
  (begin
    ;; Check if lockbox is sealed
    (asserts! (var-get is-sealed) ERR_LOCKBOX_NOT_SEALED)
    
    ;; Only delegates can request emergency access
    (asserts! (is-authorized-delegate tx-sender) ERR_ACCESS_DENIED)
    
    ;; Check that no emergency access is active
    (asserts! (not (var-get emergency-access-active)) ERR_EMERGENCY_ACCESS_ACTIVE)
    
    ;; Validate recipient address
    (asserts! (not (is-eq recipient ZERO_PRINCIPAL)) ERR_ZERO_PRINCIPAL)
    
    ;; Set emergency access state
    (var-set emergency-access-active true)
    (var-set access-requester (some tx-sender))
    (var-set temporary-access-recipient (some recipient))
    (var-set access-expiration (+ block-height (* ACCESS_WINDOW_DAYS SECONDS_IN_DAY)))
    
    ;; Clear previous endorsements
    (var-set endorsement-count u0)
    
    ;; Add first endorsement
    (map-set access-endorsements tx-sender true)
    (var-set endorsement-count (+ (var-get endorsement-count) u1))
    
    (ok true)))

;; Endorse emergency access - only delegates can endorse
(define-public (endorse-emergency-access)
  (begin
    ;; Check if lockbox is sealed
    (asserts! (var-get is-sealed) ERR_LOCKBOX_NOT_SEALED)
    
    ;; Only delegates can endorse emergency access
    (asserts! (is-authorized-delegate tx-sender) ERR_ACCESS_DENIED)
    
    ;; Check that emergency access is active
    (asserts! (var-get emergency-access-active) ERR_NO_EMERGENCY_ACCESS_ACTIVE)
    
    ;; Check if delegate already endorsed
    (asserts! (not (has-endorsed-access tx-sender)) ERR_ALREADY_ENDORSED)
    
    ;; Check if access window is still valid
    (asserts! (<= block-height (var-get access-expiration)) ERR_ACCESS_REQUEST_EXPIRED)
    
    ;; Add endorsement
    (map-set access-endorsements tx-sender true)
    (var-set endorsement-count (+ (var-get endorsement-count) u1))
    
    (ok true)))

;; Grant emergency access if consensus level is met
(define-public (grant-emergency-access)
  (begin
    ;; Check if lockbox is sealed
    (asserts! (var-get is-sealed) ERR_LOCKBOX_NOT_SEALED)
    
    ;; Check that emergency access is active
    (asserts! (var-get emergency-access-active) ERR_NO_EMERGENCY_ACCESS_ACTIVE)
    
    ;; Check if access window is still valid
    (asserts! (<= block-height (var-get access-expiration)) ERR_ACCESS_REQUEST_EXPIRED)
    
    ;; Check if enough endorsements
    (asserts! (>= (var-get endorsement-count) (calculate-required-endorsements)) ERR_NOT_ENOUGH_ENDORSEMENTS)
    
    ;; Get the temporary recipient and validate
    (let ((recipient (unwrap! (var-get temporary-access-recipient) ERR_LOCKBOX_NOT_SEALED)))
      ;; Double-check the recipient is valid (extra safety)
      (asserts! (not (is-eq recipient ZERO_PRINCIPAL)) ERR_ZERO_PRINCIPAL)
      
      ;; Update primary holder
      (var-set primary-holder recipient)
      
      ;; Reset emergency access state
      (var-set emergency-access-active false)
      (var-set access-requester none)
      (var-set temporary-access-recipient none)
      (var-set endorsement-count u0)
    )
    
    (ok true)))

;; Cancel emergency access - only primary holder can cancel
(define-public (cancel-emergency-access)
  (begin
    ;; Check if lockbox is sealed
    (asserts! (var-get is-sealed) ERR_LOCKBOX_NOT_SEALED)
    
    ;; Only primary holder can cancel emergency access
    (asserts! (is-primary-holder) ERR_ACCESS_DENIED)
    
    ;; Check that emergency access is active
    (asserts! (var-get emergency-access-active) ERR_NO_EMERGENCY_ACCESS_ACTIVE)
    
    ;; Reset emergency access state
    (var-set emergency-access-active false)
    (var-set access-requester none)
    (var-set temporary-access-recipient none)
    (var-set endorsement-count u0)
    
    (ok true)))

;; Withdraw tokens from lockbox - only primary holder can withdraw
(define-public (withdraw-tokens (token <ft-trait>) (destination principal) (amount uint))
  (begin
    ;; Check if lockbox is sealed
    (asserts! (var-get is-sealed) ERR_LOCKBOX_NOT_SEALED)
    
    ;; Only primary holder can withdraw
    (asserts! (is-primary-holder) ERR_ACCESS_DENIED)
    
    ;; Validate destination and amount
    (asserts! (not (is-eq destination ZERO_PRINCIPAL)) ERR_ZERO_PRINCIPAL)
    (asserts! (> amount u0) ERR_INVALID_WITHDRAWAL)
    
    ;; Transfer tokens
    (contract-call? token transfer amount tx-sender destination none)
  ))

;; Withdraw STX from lockbox - only primary holder can withdraw
(define-public (withdraw-stx (destination principal) (amount uint))
  (begin
    ;; Check if lockbox is sealed
    (asserts! (var-get is-sealed) ERR_LOCKBOX_NOT_SEALED)
    
    ;; Only primary holder can withdraw
    (asserts! (is-primary-holder) ERR_ACCESS_DENIED)
    
    ;; Validate destination and amount
    (asserts! (not (is-eq destination ZERO_PRINCIPAL)) ERR_ZERO_PRINCIPAL)
    (asserts! (> amount u0) ERR_INVALID_WITHDRAWAL)
    
    ;; Check if enough balance
    (asserts! (>= (stx-get-balance tx-sender) amount) ERR_INADEQUATE_FUNDS)
    
    ;; Transfer STX
    (stx-transfer? amount tx-sender destination)
  ))

;; Get current primary holder
(define-read-only (get-primary-holder)
  (ok (var-get primary-holder)))