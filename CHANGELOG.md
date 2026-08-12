# Changelog

## 0.2.0 — 2026-08-12

- Added the `channels` resource for allocation management, access previews,
  channel reporting, and origin-bound buyer access sessions.
- Added inventory booking lifecycle reads and channel-aware hold/book options.
- Require a non-empty stable booking reference for booking, unbooking, and
  booking-detail reads.
- Expanded registry, documentation, and agent-discovery links in the README.

## 0.1.0 — 2026-08-04

First public release: RubyGems `seatlayer`.

Initial contents of the SeatLayer Ruby server SDK.

- `SeatLayer::Client` with secret-key auth, per-attempt timeouts, and an escape hatch.
- Resources: `charts`, `events`, `inventory`, `sessions`, `webhooks`, `workspaces`.
- Automatic `Idempotency-Key` on every mutation, reused across retries so a retried
  booking cannot become two bookings.
- Retries on 429/408/5xx with exponential backoff and full jitter; honours `Retry-After`.
  4xx is never retried.
- Typed errors: `AuthError` (with `mode_mismatch?`), `ConflictError` (with `conflicts`
  and `sold_out?`), `RateLimitError`, `ValidationError`, `NotFoundError`,
  `ConnectionError` — all under `SeatLayer::Error`.
- `SeatLayer::Webhook.verify` — raw-body HMAC-SHA256 via `OpenSSL.secure_compare`.
- `create_manage_session` requires explicit capabilities; the API's default grants
  `event:cancel`, which unbooks paid seats and authorises gateway refunds.
- Constructor rejects a `pk_` key by name rather than failing as a 401 later.
- `list_all` returns a lazy `Enumerator` when no block is given, so
  `.lazy.first(n)` does not walk every page.
- No runtime dependencies — `net/http`, `json` and `openssl` from the standard library.

Requires Ruby 3.0 or newer.
