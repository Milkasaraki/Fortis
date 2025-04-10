;; Governance Token Fortis
;; This contract implements a simple Lockbox for governance tokens.

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
(define-constant ERR_ZERO_PRINCIPAL (err u112))
(define-constant ERR_INVALID_WITHDRAWAL (err u113))
(define-constant ERR_INADEQUATE_FUNDS (err u110))

;; Data variables

;; Primary holder of the lockbox
(define-data-var primary-holder principal tx-sender)

;; Whether the lockbox has been sealed
(define-data-var is-sealed bool false)

;; Constants
(define-constant ZERO_PRINCIPAL 'SP000000000000000000002Q6VF78)

;; Read-only functions

;; Check if caller is the primary holder
(define-read-only (is-primary-holder)
  (is-eq tx-sender (var-get primary-holder)))

;; Get current primary holder
(define-read-only (get-primary-holder)
  (ok (var-get primary-holder)))

;; Public functions

;; Seal the lockbox
(define-public (seal-lockbox (holder principal))
  (begin
    ;; Check if already sealed
    (asserts! (not (var-get is-sealed)) ERR_LOCKBOX_ALREADY_SEALED)
    
    ;; Validate holder address
    (asserts! (not (is-eq holder ZERO_PRINCIPAL)) ERR_ZERO_PRINCIPAL)
    
    ;; Set holder and mark as sealed
    (var-set primary-holder holder)
    (var-set is-sealed true)
    
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