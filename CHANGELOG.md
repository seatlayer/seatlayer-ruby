# Changelog

## Unreleased

- Added the 39 remaining Fixed Renewable Season operations to `client.seasons` (87 in all):
  performances, package edits and prices, publishing, checkout tests, occurrence returns and
  reclaims, holders, Season order refunds and cancellations, hosted renewals, renewal quotes,
  intents and checkouts, the sales,
  seats and seat-count reports, and bulk refunds and lapsed-offer releases with their jobs.
- Added three resources: `client.holders` (holders, customers, holder tickets and ticket
  transfers), `client.orders` (account and event orders, refunds, cancellations and ticket
  resends) and `client.event_series` (plan, read, extend and update an event series).
- Added `holders.create_holder_return`: give back a holder's seat on one date, one per ticket.
- Added the event sales settings to `client.events`: buyer checkout, payment gateway, sales
  readiness, preflight and transition, booking fee, and discount codes.
- `export_season_holders_csv`, `export_season_orders_csv` and `orders.export_event_orders_csv`
  return the raw CSV text. `delete_season_plan` and `events.delete_event_discount_code` return
  an empty Hash (the API answers 204).
- 27 of the new operations use exact header replay (41 in the SDK now) and retry with one
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
- `update_season` takes `audience:` (`"embed_only"` or `"public"`).
- `open_season_sales` answers `warnings` (`checkout_test_missing` until a checkout test or rehearsal has passed) and can refuse with `409 plan_not_published` or `409 checkout_mode_not_chosen`.
- A cancelled date refunds per date only: an amendment's `refund:` is `"none"` or `"per_date"`, and `refund_season_performance` takes `amount: "per_date"` (`full` answers `422 date_refund_per_date_only`; refund a whole order with the order refund).
- `add_event_series_dates` takes `retry_failed: true` to make the failed dates again (`409 series_busy`, `422 nothing_to_retry`).
- `list_orders` takes `holder_ref:`; orders carry `holderRef` and `customerId`, and the buyer's email can be nil (a box office sale with no email).
- Season holds, give-backs and date cancels can refuse with `performance_cancelled`, `refund_not_started` (503), `missing_manage_capability` (403) or `invalid_refund`; a holder's status can be `reserved`; hosted renewal readiness carries `missingPrices`.
- `create_event_series` takes `from_event_key:`: an event you already set up becomes the first date under its own key, and every other date is a copy of it. `name:` and `chart_key:` are then left out. It refuses with `404 event_not_found`, or `422 event_has_no_date`, `event_in_season`, `event_in_performance_group`, `event_in_series` or `invalid_request`.
- Every date of an event series carries the series' plain name (`Hamlet`, not `Hamlet · 3 Nov`); tell dates apart by `startsAt`. `update_event_series` renames each date that carries the series name, and a series name cannot hold `{n}`, `{date}` or `{time}`.
- Added `seasons.release_season_lapsed_offers`: release the seats of every lapsed renewal offer as a job (`202 {"job"}`), with header replay. An offer extended before its turn is skipped and keeps its seat. It can refuse with `503 job_busy` or `season_not_configured`; send it again.
- `retrieve_season_hosted_renewals` and `list_season_renewal_offers` take `cursor:` and `limit:` (1 to 500 and 1 to 100) and answer one page, newest first, with `nextCursor` (nil on the last page); a bad cursor or limit is refused with `400 invalid_cursor` or `invalid_limit`.
- `create_season_renewal_offers` answers `201 {"offers"}` for 100 contracts or fewer, and `202 {"job", "batchId"}` above that: a `renewal_run` job makes the offers. Follow it with `retrieve_season_bulk_job`, then page the offers with `list_season_renewal_offers`.
- `create_season_holder_import_from_season` answers `202 {"job"}` when a commit brings across more than 100 holders: a `holder_import` job, whose `summary` has the same counts once it completes. It and `create_season_renewal_offers` can refuse with `409 job_mismatch` or `503 season_not_configured`, and the bring-across also with `503 job_busy`.
- `create_season_renewal_notices` takes up to 20,000 `offer_ids:`; more is refused with `422 too_many_offer_ids`.
- `create_season_renewal_notices` takes `batch_id:` instead of `offer_ids:`: email every open offer one `create_season_renewal_offers` batch made, such as the batch a `renewal_run` job made.
- Single tickets on a season: `create_season` and `update_season` take `single_tickets:` (default `false`, Season only; anything else is refused with `422 invalid_single_tickets`). Every season read carries `singleTickets`, and a season on sale may carry `singleTicketsNotOpen`. `update_season`, `open_season_sales` and `resume_season_sales` answer `singleTicketDates` (`direction`, `opened`, `closed`, `notOpened`, `jobId`) when they open or stop the dates' own sales; a `season_singles` job does it for more than 12 upcoming dates.

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
