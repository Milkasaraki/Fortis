;; Governance Token Lockbox
;; Version 2.0: Token storage with delegation
;; This contract implements a lockbox for governance tokens with basic delegation capabilities.

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
(define-constant ERR_INVALID_CONSENSUS_LEVEL (err u111))
(define-constant ERR_ZERO_PRINCIPAL (err u112))
(define-constant ERR_INVALID_WITHDRAWAL (err u113))
(define-constant ERR_INADEQUATE_FUNDS (err u110))

;; Data variables

;; Primary holder of the lockbox
(define-data-var primary-holder principal tx-sender)

;; Whether the lockbox has been sealed
(define-data-var is-sealed bool false)

;; List of authorized delegates
(define-map authorized-delegates principal bool)

;; Total number of delegates
(define-data-var delegate-total uint u0)

;; Consensus level required for actions (percentage 1-100)
(define-data-var consensus-level uint u51)

;; Constants
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

;; Get the number of all authorized delegates
(define-read-only (get-delegate-total)
  (ok (var-get delegate-total)))

;; Get current primary holder
(define-read-only (get-primary-holder)
  (ok (var-get primary-holder)))

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