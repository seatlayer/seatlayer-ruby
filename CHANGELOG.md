# Changelog

## Unreleased

- Added the 38 remaining Fixed Renewable Season operations to `client.seasons` (86 in all):
  performances, package edits and prices, publishing, checkout tests, occurrence returns and
  reclaims, holders, Season order refunds and cancellations, hosted renewals, renewal quotes,
  intents and checkouts, the sales,
  seats and seat-count reports, and bulk refunds with their jobs.
- Added three resources: `client.holders` (holders, customers, holder tickets and ticket
  transfers), `client.orders` (account and event orders, refunds, cancellations and ticket
  resends) and `client.event_series` (plan, read, extend and update an event series).
- Added `holders.create_holder_return`: give back a holder's seat on one date, one per ticket.
- Added the event sales settings to `client.events`: buyer checkout, payment gateway, sales
  readiness, preflight and transition, booking fee, and discount codes.
- `export_season_holders_csv`, `export_season_orders_csv` and `orders.export_event_orders_csv`
  return the raw CSV text. `delete_season_plan` and `events.delete_event_discount_code` return
  an empty Hash (the API answers 204).
- 26 of the new operations use exact header replay (40 in the SDK now) and retry with one
  `Idempotency-Key`; every other new mutation is single-attempt.
- `Webhooks::EVENT_NAMES` adds `series.created`, `series.dates_added`, `order.paid`,
  `order.refunded`, `order.cancelled`, `customer.created`, `customer.email_changed`,
  `season.ticket.transfer_sent`, `season.ticket.transferred` and
  `season.ticket.transfer_cancelled`.
- Added `seasons.refund_season_performance` (refund every order of a cancelled date as a job,
  with header replay), `seasons.list_season_bulk_jobs`, and `seasons.retrieve_season_bulk_job`.
- `create_season_amendment` takes `refund:` and `reason:`, for the new `postpone` and `cancel`
  kinds.
- `update_season` takes `checkout_mode:`, `transfer_cutoff_hours:`, and `return_cutoff_hours:`
  (`nil` sends an explicit null).
- `replace_season_package_prices` documents `"priceTypeKey"` on each price, and
  `create_season_holder_import` documents `"holderEmail"` and `"holderName"` on each row.
- `Webhooks::EVENT_NAMES` lists all 56 public event names, adding `object.resale.*`,
  `season.occurrence.*`, `season.performance.*` (including `postponed`, `cancelled`, and
  `rescheduled`), `season.bulk_action.completed`, `season.order.*`, `season.ticket.issued`,
  `season.ticket.voided`, and the Season lifecycle, hold, booking, renewal, operation and
  amendment events.
- `events.list` and `events.list_all` take `series_key:` to list one event series' dates.
- Added `seasons.retrieve_season_renewal_quote`: what renewing an offer costs, and whether SeatLayer checkout can take it now.
- Added `seasons.create_season_renewal_intent`: record a holder's intent for a renewal taken by phone or at the box office, so your own checkout can commit.
- Added `seasons.create_season_renewal_checkout`: a SeatLayer checkout that renews an offer with no hosted page, with header replay.
- Added `holders.create_holder_renewal_checkout`: the same checkout for one of a holder's offers, with header replay.
- Added `holders.decline_holder_renewal_offer`: decline one of a holder's offers, with an optional `reason:`.
- `seasons.decline_season_renewal_offer` takes an optional `reason:`, kept on the offer as `declineReason`.

## 0.8.0 (2026-09-10)

- Added Event hosting regions: `region:` on event create, `default_region:` on workspace create and update, and `EVENT_HOSTING_REGIONS` to check a value before it is sent. Events created without a region run in Western Europe.

## 0.7.0 — 2026-08-30

- Added coverage for all 48 Fixed Renewable Season server
  operations under `client.seasons`, with exact path encoding and
  operation-specific retry/idempotency behavior.
- Season allocations are identity-only and the API response declares host
  pricing authority. Buyer rehearsal validation sends no evidence body because
  SeatLayer discovers the retained hold, booking, cancellation, and delivered
  webhook chain automatically.

## 0.6.1

- Documentation only. Refreshes the README, adds frequently asked
  questions, and aligns package metadata. No API or behaviour changes.

## 0.6.0 — 2026-08-23

- Added exact immutable Event configuration binding reads and compare-and-set
  attach/detach through `events.retrieve_configuration_binding` and
  `events.update_configuration_binding`. Updates remain deliberately single-attempt.

## 0.5.0 — 2026-08-21

- Added `performance_groups`, the trusted server resource for fixed two-to-eight
  performance runs. It creates and activates groups, mints one-time browser
  access, retrieves authoritative group holds, and confirms bookings with
  stable action and order references. Browser-only group routes remain outside
  this secret-key SDK.

- Added `templates.instantiate_template` and the ticket-release lifecycle on
  `events` (`list_ticket_releases`, `update_ticket_releases`, and
  `close_ticket_release`). Template instantiation sends `{}` when no overrides
  are supplied, URI-escapes identifiers, and uses exact-response replay;
  ticket-release writes remain single-attempt.

- **Security/reliability:** Mutations now default to a single attempt. Automatic header-replay
  retries are limited to chart create/copy, template instantiation, event create, and workspace create, preventing
  transient failures from duplicating holds or best-available results and from issuing extra
  show-once credentials.
- Aligned event, inventory, webhook, manage-session, and Designer requests with the generated
  public contract: event metadata, chart-update acknowledgement, trusted hold extension,
  scheduled block release, hold-TTL reset, webhook envelopes and delivery filters, and Designer
  safe-mode/feature-policy fields are now represented directly.
- Removed unsupported `state` and `cursor` keywords from buyer-access-session listing; the route
  supports only `limit`.
- Added deterministic transport-contract coverage for stable error-code fallback, HTTP status,
  decoded body and `X-Request-ID` exposure, typed 429 `Retry-After` precedence, non-JSON gateway
  failures, and single-attempt unsafe mutations.
- Reached all 71 public operation wrappers with raw event-poster upload/removal and the complete
  hosted access-link lifecycle. One-time capability reveals remain single-attempt.
- Added chart copy/metadata overrides, event-log pagination filters, and explicit-null support for
  buyer-session and workspace fields.

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
