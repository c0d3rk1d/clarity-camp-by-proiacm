
;; dex

(use-trait sip-010-token .traits.ft-trait)

;; constants
;;
(define-constant CONTRACT_OWNER tx-sender)
(define-constant CONTRACT_ADDRESS (as-contract tx-sender))
(define-constant MAX_FEE_RATE u10)

;; errors
;;
(define-constant ERR_INVALID_VALUE (err u100))
(define-constant ERR_TOKEN_ALREADY_LISTED (err u101))
(define-constant ERR_LISTING_NOT_FOUND (err u102))
(define-constant ERR_UNAUTHORIZED (err u103))
(define-constant ERR_INVALID_TOKEN (err u104))
(define-constant ERR_NOT_ENOUGH_TOKENS (err u105))
(define-constant ERR_HIGH_SLIPPAGE (err u106))

;; data maps and vars
;;
(define-data-var lastListingId uint u2000)
(define-data-var feeRate uint u0)

(define-map TokenListing uint {
    token: principal,
    seller: principal,
    tokenAmount: uint,
    price: uint,
    tokensLeft: uint
  }
)

(define-map UserTokens principal principal)

;; read-only functions
(define-read-only (get-token-listing (listingId uint))
  (map-get? TokenListing listingId)
)

(define-read-only (get-fee (stxAmount uint))
  (/ (* stxAmount (var-get feeRate)) u10000)
)

;; public functions
;;
(define-public (list-sip10-token-for-sale (token <sip-010-token>) (tokenTotalAmount uint) (tokenPrice uint))
  (let
    (
      (newListingId (+ (var-get lastListingId) u1))
    )

    (asserts! (and (> tokenTotalAmount u0) (> tokenPrice u0)) ERR_INVALID_VALUE)
    (asserts! (is-none (map-get? UserTokens (contract-of token))) ERR_TOKEN_ALREADY_LISTED)

    ;; #[filter(tokenTotalAmount, tokenPrice, token)]
    (map-set TokenListing newListingId {
      token: (contract-of token),
      seller: tx-sender,
      tokenAmount: tokenTotalAmount,
      price: tokenPrice,
      tokensLeft: tokenTotalAmount
    })
    (map-set UserTokens (contract-of token) tx-sender)
    (var-set lastListingId newListingId)

    (try! (contract-call? token transfer tokenTotalAmount tx-sender CONTRACT_ADDRESS none))

    (ok newListingId)
  )
)

(define-public (add-tokens (listingId uint) (token <sip-010-token>) (amount uint))
  (let
    (
      (listing (unwrap! (map-get? TokenListing listingId) ERR_LISTING_NOT_FOUND))
    )

    (asserts! (> amount u0) ERR_INVALID_VALUE)
    (asserts! (is-eq (get seller listing) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get token listing) (contract-of token)) ERR_INVALID_TOKEN)

    (map-set TokenListing listingId 
      (merge listing {
        tokenAmount: (+ (get tokenAmount listing) amount), 
        tokensLeft: (+ (get tokensLeft listing) amount)
      })
    )

    (try! (contract-call? token transfer amount tx-sender CONTRACT_ADDRESS none))

    (ok true)
  )
)

(define-public (withdraw-tokens (listingId uint) (token <sip-010-token>) (amount uint))
  (let
    (
      (listing (unwrap! (map-get? TokenListing listingId) ERR_LISTING_NOT_FOUND))
    )

    (asserts! (and (> amount u0) (< amount (get tokensLeft listing))) ERR_INVALID_VALUE)
    (asserts! (is-eq (get seller listing) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get token listing) (contract-of token)) ERR_INVALID_TOKEN)

    (map-set TokenListing listingId 
      (merge listing {
        tokensLeft: (- (get tokensLeft listing) amount)
      })
    )

    (try! (as-contract (contract-call? token transfer amount CONTRACT_ADDRESS (get seller listing) none)))

    (ok true)
  )
)

(define-public (change-price (listingId uint) (token <sip-010-token>) (price uint))
  (let
    (
      (listing (unwrap! (map-get? TokenListing listingId) ERR_LISTING_NOT_FOUND))
    )

    (asserts! (> price u0) ERR_INVALID_VALUE)
    (asserts! (is-eq (get seller listing) tx-sender) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get token listing) (contract-of token)) ERR_INVALID_TOKEN)

    (map-set TokenListing listingId (merge listing { price: price } ))
    (ok true)
  )
)

(define-public (buy-tokens (listingId uint) (token <sip-010-token>) (minTokenQty uint) (maxStxCost uint))
  (let
    (
      (listing (unwrap! (map-get? TokenListing listingId) ERR_LISTING_NOT_FOUND))
      (buyQty (/ (- maxStxCost (get-fee maxStxCost)) (get price listing)))
      (buyCost (* buyQty (get price listing)))
      (buyFee (get-fee buyCost))
    )
    
    (asserts! (is-eq (get token listing) (contract-of token)) ERR_INVALID_TOKEN)
    (asserts! (>= (get tokensLeft listing) minTokenQty) ERR_NOT_ENOUGH_TOKENS)
    (asserts! (and (> minTokenQty u0) (> maxStxCost u0)) ERR_INVALID_VALUE)
    (asserts! (>= buyQty minTokenQty) ERR_HIGH_SLIPPAGE)

    (map-set TokenListing
      listingId
      (merge listing { tokensLeft: (- (get tokensLeft listing) buyQty) })
    )

    (try! (stx-transfer? (+ buyCost buyFee) tx-sender CONTRACT_ADDRESS)) ;; transfer all costs to contract
    (try! (as-contract (stx-transfer? buyCost CONTRACT_ADDRESS (get seller listing)))) ;; transfer total - fee from contract to seller
    (try! (as-contract (contract-call? token transfer buyQty CONTRACT_ADDRESS tx-sender none))) ;; transfer tokens to buyer
    (ok true)
  )
)

(define-public (set-fee-rate (newFeeRate uint))
  (begin
    (asserts! (<= newFeeRate MAX_FEE_RATE) ERR_INVALID_VALUE)
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set feeRate newFeeRate)
    (ok true)
  )
)

