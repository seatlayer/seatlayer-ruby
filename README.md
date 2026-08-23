# SeatLayer Ruby SDK

[![CI](https://github.com/seatlayer/seatlayer-ruby/actions/workflows/ci.yml/badge.svg)](https://github.com/seatlayer/seatlayer-ruby/actions/workflows/ci.yml)
[![Gem](https://img.shields.io/gem/v/seatlayer.svg)](https://rubygems.org/gems/seatlayer)
[![Ruby](https://img.shields.io/badge/Ruby-%E2%89%A53.0-CC342D.svg)](https://www.ruby-lang.org/)
[![License: MIT](https://img.shields.io/badge/license-MIT-111827.svg)](LICENSE)

Official Ruby server SDK for the [SeatLayer](https://seatlayer.io) reserved-seating API.

> **Server-side only.** This gem authenticates with your secret key. Never load it anywhere a
> ticket buyer can reach — browser surfaces get short-lived, origin-bound tokens that you mint here.

## Install

```ruby
gem "seatlayer"
```

```bash
gem install seatlayer
```

Requires Ruby 3.0 or newer. **No runtime dependencies** — `net/http`, `json` and `openssl` from the
standard library.

## Quick start

```ruby
require "seatlayer"

client = SeatLayer::Client.new(ENV.fetch("SEATLAYER_SECRET_KEY"))

# 1. Provision a venue for a new organiser from a public template.
chart = client.templates.instantiate_template("arena-standard")["meta"]
client.charts.publish(chart["id"])

# 2. Create an event on it.
event = client.events.create(chart_id: chart["id"], name: "Spring Gala")["meta"]

# 3. Sell four seats over the phone.
held = client.inventory.hold_best_available(event["key"], qty: 4)
# … take payment against held["items"], which carry authoritative prices …
client.inventory.book(event["key"], hold_id: held["holdId"], booking_ref: "order-8842")
```

Nullable event-create fields distinguish omission from an explicit reset: passing, for example,
`venue: nil` sends JSON `null`; leaving `venue` out sends no field.

## Test vs live

Keys carry their own mode. `sk_test_…` keys can only touch test-mode events and `sk_live_…` only
live ones; crossing them returns `403 mode_mismatch`, surfaced as `AuthError` with `mode_mismatch?`.

```ruby
client = SeatLayer::Client.new(ENV.fetch("SEATLAYER_SECRET_KEY"))
raise "Refusing to boot production against test-mode seating data." if
  ENV["RAILS_ENV"] == "production" && client.mode != "live"
```

A publishable `pk_` key is rejected at construction with a message naming the mistake, rather than
failing as a `401` three round-trips later.

## The two selling flows

**Buyer picks seats in the browser.** Your frontend holds them; your backend confirms the price and
books. Never price from what the browser sent you — `retrieve_hold` is authoritative.

```ruby
hold = client.inventory.retrieve_hold(event_key, hold_id)
total = hold["items"].sum { |item| item["unitPrice"] }
# … charge `total` in hold["currency"] …
client.inventory.book(event_key, hold_id: hold_id, booking_ref: charge.id)
```

**Your backend picks the seats.** Phone orders, box office, comps.

```ruby
# Payment already taken — book outright, so nothing is stranded if a second call fails.
client.inventory.book_best_available(event_key, qty: 2, booking_ref: "phone-1183")

# Or name the seats yourself.
client.inventory.box_office_book(event_key, labels: ["A-1", "A-2"], booking_ref: "comp-14")
```

## Private and partner sales

Channels split event inventory into explicit allocations. A channel id is
reporting/routing metadata, not browser authority. Authenticate the buyer in
your backend and mint a short-lived token restricted to the event, origin, and
allowed allocations:

```ruby
access = client.channels.create_buyer_access_session(
  event_key,
  channel_ids: ["chn_partner_a"],
  include_public: false,
  allowed_origin: "https://tickets.example"
)
# Return access["token"] to the in-memory buyerAccessTokenProvider only.
```

Never log or persist the returned `bse_…` bearer. Allocation setup, previews,
pause/archive controls, audit-safe session listing, and channel reports are on
`client.channels`.

## Listing and pagination

`list` returns one page plus a `nextCursor`. `list_all` pages for you and returns a lazy
`Enumerator` when no block is given — the point of paginating is to *not* hold an unbounded result
set in memory, so `.lazy.first(n)` stops fetching once it has enough.

```ruby
# One page, your own paging.
page = client.events.list(limit: 50)
page["events"]
page["nextCursor"]   # nil once exhausted

# Or let the SDK walk it.
client.events.list_all do |event|
  sync(event)
end

# Lazily — this fetches one page, not all of them.
client.charts.list_all.lazy.first(5)
```

Listing events includes live availability `counts` by default, which costs the server one
round-trip **per event**. `list_all` turns them off automatically — walking a whole catalogue is
exactly when you don't want that — and you can control it explicitly:

```ruby
client.events.list(limit: 50, counts: false)
```

## Keeping a hold alive

When an order takes longer than the checkout window — an invoice, a phone sale — extend rather than
release and re-hold. Releasing first hands the seats to whoever is racing for them in between.

```ruby
begin
  client.inventory.extend_hold(event_key, hold_id, ttl_ms: 10 * 60_000)
rescue SeatLayer::ConflictError
  # Gone, expired, or at its renewal cap — the buyer has to re-pick.
end
```

## Embedding the control room

Your secret key never reaches a browser. Mint a scoped token instead.

```ruby
session = client.sessions.create_manage_session(
  event_key,
  allowed_origin: "https://box-office.yourplatform.com",
  capabilities: ["event:view", "event:block"],
  expires_in_seconds: 3600
)
```

`capabilities` is **required** by this SDK even though the raw API safely defaults an omitted list
to view-only (`event:view`). Keeping the argument required makes browser authority visible at every
call site. Grant the smallest set the page needs.

The full set, all opt-in:

| Capability | Grants |
|---|---|
| `event:view` | Read the seat map and its live states |
| `event:block` | Block and unblock seats |
| `event:cancel` | Unbook paid seats and issue gateway refunds — destructive, moves money |
| `event:reports` | Read sales and availability reports |
| `event:channels:view` | Read sales channels and their allocations |
| `event:channels:manage` | Create, pause and archive channels; rotate access links |
| `event:orders:read` | Read SeatLayer-managed orders |
| `event:refund` | Refund a SeatLayer-managed order |
| `event:tickets:send` | Send SeatLayer-managed tickets |
| `event:door:view` | Read the door list |
| `event:door:checkin` | Check tickets in and out |
| `event:boxoffice` | Use the managed box-office surface |

The two `event:channels:*` capabilities are **not** in the default — a token minted before sales
channels existed must not silently acquire channel authority — so ask for them explicitly if the
page manages channels.

Designer minting returns the API envelope unchanged: read the token and effective safe-mode and
feature policy under `result["session"]`. Pass `safe_mode_options` only with `mode: "safe"`.

## Webhooks

Subscription responses use the wire envelopes exactly: `list` returns `{"subs" => [...]}`,
`create` returns `{"sub" => ..., "secret" => ...}` (the secret is shown once), and `update`
returns `{"sub" => ...}`. `SeatLayer::Webhooks::EVENT_NAMES` is the exact eight-name event set;
delivery history accepts `limit`, `status` (`"ok"` or `"failed"`), and `before`.

Verify every delivery against the **raw** body. Re-encoding a parsed Hash changes the bytes and
verification will fail.

```ruby
# Rails
class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token

  def seatlayer
    event = SeatLayer::Webhook.verify(
      request.raw_post,                          # raw body, never params
      request.headers["X-SeatLayer-Signature"],
      ENV.fetch("SEATLAYER_WEBHOOK_SECRET")
    )

    # The signed body carries `at`, but nothing enforces a freshness window, so a
    # captured delivery stays valid indefinitely. Deduplicate on occurrenceId —
    # this is your replay protection, not an optimisation.
    return head :ok if already_processed?(event["occurrenceId"])

    Handler.call(event)
    head :ok
  rescue SeatLayer::WebhookVerificationError
    head :bad_request
  end
end
```

## Errors

```ruby
begin
  client.inventory.hold_best_available(event_key, qty: 6)
rescue SeatLayer::ConflictError => e
  return show_alternative_dates if e.sold_out?   # a business outcome, not a bug
  raise
rescue SeatLayer::RateLimitError => e
  return retry_after(e.retry_after)
rescue SeatLayer::AuthError => e
  raise "Test key pointed at a live event, or the reverse." if e.mode_mismatch?
  raise
end
```

| Class | Status | Means |
|---|---|---|
| `AuthError` | 401, 403 | Bad, revoked, or wrong-mode key |
| `NotFoundError` | 404 | No such resource *for this organisation* |
| `ConflictError` | 409 | Inventory moved, or a guard rejected the change |
| `ValidationError` | 422 | Understood and rejected |
| `RateLimitError` | 429 | Over budget; carries `retry_after` |
| `ConnectionError` | — | No answer: DNS, TLS, socket, timeout |

All descend from `SeatLayer::Error`, so `rescue SeatLayer::Error` catches everything. Every API
error carries `status`, `code`, `body` and `request_id` — quote the request id in support requests.

## Reliability

**Retries.** Reads (`GET`/`HEAD`) retry 429, 408 and 5xx with exponential backoff and full jitter;
`Retry-After` wins when the server sends it. Automatic mutation retries are limited to the five
operations backed by exact response replay: `charts.create`, `charts.copy`,
`templates.instantiate_template`, `events.create`, and `workspaces.create`. Other 4xx responses
are never retried.

**Idempotency.** Those five replay-backed operations carry an `Idempotency-Key`, generated when you
do not supply one and reused across attempts. Other mutations are single-attempt and receive no
automatic key. A caller-supplied key is forwarded but does not enable retries. This includes
inventory holds and bookings, show-once credential or secret creation, unsupported operations, and
raw `request` mutations. Keep `booking_ref` in the booking body for reconciliation, but handle an
unknown network outcome explicitly instead of automatically repeating the sale.

```ruby
client.events.create(chart_id: chart_id, idempotency_key: "provision-event-#{event_id}")
```

```ruby
SeatLayer::Client.new(
  ENV.fetch("SEATLAYER_SECRET_KEY"),
  max_retries: 3,   # total attempts
  timeout: 30.0     # seconds, per attempt
)
```

## Escape hatch

For surface this SDK does not wrap yet, `request` keeps auth and error mapping. Raw reads retain the
read retry policy; raw mutations are always single-attempt because their replay contract is unknown:

```ruby
client.request("POST", "/v1/events/ev_1/some-new-route", body: { "qty" => 2 })
```

## API surface

| Resource | Methods |
| --- | --- |
| `charts` | `list` `list_all` `create` `retrieve` `update` `delete` `copy` `archive` `unarchive` `publish` |
| `templates` | `instantiate_template` |
| `events` | `list` `list_all` `create` `retrieve` `retrieve_configuration_binding` `update_configuration_binding` `update` `delete` `update_poster` `delete_poster` `update_chart` `close` `reopen` `archive` `retrieve_hold_ttl` `update_hold_ttl` `list_ticket_releases` `update_ticket_releases` `close_ticket_release` `retrieve_report` `retrieve_log` |
| `inventory` | `hold` `hold_best_available` `book_best_available` `extend_hold` `retrieve_hold` `release` `book` `box_office_book` `unbook` `list_bookings` `retrieve_booking` `block` `unblock` `unblock_all` `retrieve_availability` `update_availability` |
| `channels` | `list_channels` `create_channel` `update_channel` `update_assignments` `list_allocation` `retrieve_access_preview` `retrieve_report` `pause` `unpause` `archive` `create_buyer_access_session` `list_buyer_access_sessions` `revoke_buyer_access_session` `create_access_link` `list_access_links` `rotate_access_link` `revoke_access_link` |
| `sessions` | `create_manage_session` `revoke_manage_session` `create_designer_session` `revoke_designer_session` |
| `webhooks` | `list` `create` `update` `delete` `list_deliveries` |
| `workspaces` | `list` `create` `retrieve` `update` |

Full reference: [docs.seatlayer.io/server-sdk](https://docs.seatlayer.io/server-sdk/install/)

### Deliberately not in this SDK

Some API surface is intentionally unwrapped, not merely pending:

- **Hosted-checkout orders and refunds.** Reading or refunding a SeatLayer-hosted-checkout sale is
  not a server-SDK capability. Those records only exist for organisations using hosted checkout; if
  you run your own commerce store you refund in that store, through your own gateway.
- **Connecting or assigning payment gateways.** Connecting one is a dashboard flow, so shipping only
  the assignment half across seven SDKs would hand you a method that cannot yet succeed.
- **Realtime seat updates.** Live seat state reaches the *browser* through the widget's own socket.
  There is no server-side subscribe; a secret-key caller gets authoritative state from
  `events.retrieve_report` and `inventory.retrieve_availability`.

None of these are reachable through `request` as a supported path either — they are excluded from
the public manifest, not just from the wrapper.

## Related resources

- [Server SDK guide](https://docs.seatlayer.io/server-sdk/install/)
- [Errors, retries and idempotency](https://docs.seatlayer.io/server-sdk/reliability/)
- [Webhook verification](https://docs.seatlayer.io/server-sdk/webhooks/)
- [Server API reference](https://docs.seatlayer.io/server-api/events/)
- [OpenAPI description](https://docs.seatlayer.io/openapi.json)
- [Agent-readable documentation](https://docs.seatlayer.io/llms.txt)
- [SeatLayer GitHub organization](https://github.com/seatlayer)

### Other SeatLayer SDKs

| Surface | Package |
|---|---|
| Browser (vanilla) | [`@seatlayer/js`](https://www.npmjs.com/package/@seatlayer/js) |
| React | [`@seatlayer/react`](https://www.npmjs.com/package/@seatlayer/react) |
| React Native | [`@seatlayer/react-native`](https://www.npmjs.com/package/@seatlayer/react-native) |
| iOS | [`seatlayer-ios`](https://github.com/seatlayer/seatlayer-ios) |
| Android | [`seatlayer-android`](https://github.com/seatlayer/seatlayer-android) |
| Flutter | [`seatlayer`](https://pub.dev/packages/seatlayer) |
| Node.js (server) | [`@seatlayer/server`](https://www.npmjs.com/package/@seatlayer/server) |
| Python (server) | [`seatlayer`](https://pypi.org/project/seatlayer/) |
| PHP (server) | [`seatlayer/seatlayer-php`](https://packagist.org/packages/seatlayer/seatlayer-php) |
| Java (server) | [`io.seatlayer:seatlayer-java`](https://central.sonatype.com/artifact/io.seatlayer/seatlayer-java/0.3.0) |
| Go (server) | [`github.com/seatlayer/seatlayer-go`](https://pkg.go.dev/github.com/seatlayer/seatlayer-go) |
| .NET (server) | [`SeatLayer`](https://www.nuget.org/packages/SeatLayer) |

## Development

```bash
bundle install
bundle exec rubocop
bundle exec rspec
```

## License

MIT
