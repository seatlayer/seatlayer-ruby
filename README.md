# SeatLayer Ruby SDK

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

# 1. Provision a venue for a new organiser from one of your templates.
chart = client.charts.copy("c_template_arena")["meta"]
client.charts.publish(chart["id"])

# 2. Create an event on it.
event = client.events.create(chart_id: chart["id"], name: "Spring Gala")["meta"]

# 3. Sell four seats over the phone.
held = client.inventory.hold_best_available(event["key"], qty: 4)
# … take payment against held["items"], which carry authoritative prices …
client.inventory.book(event["key"], hold_id: held["holdId"], booking_ref: "order-8842")
```

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

`capabilities` is **required** by this SDK even though the API defaults it. Omit it at the API level
and you get `event:view`, `event:block`, `event:cancel` and `event:reports` — including
`event:cancel`, which unbooks paid seats **and authorises refunds against the organiser's connected
payment gateway**. That is real money, moved by a token you handed to a browser; it should not
arrive by forgetting an argument. Grant the smallest set the page needs.

The full set, all opt-in:

| Capability | Grants |
|---|---|
| `event:view` | Read the seat map and its live states |
| `event:block` | Block and unblock seats |
| `event:cancel` | Unbook paid seats and issue gateway refunds — destructive, moves money |
| `event:reports` | Read sales and availability reports |
| `event:channels:view` | Read sales channels and their allocations |
| `event:channels:manage` | Create, pause and archive channels; rotate access links |

The two `event:channels:*` capabilities are **not** in the default — a token minted before sales
channels existed must not silently acquire channel authority — so ask for them explicitly if the
page manages channels.

## Webhooks

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

**Retries.** 429, 408 and 5xx are retried with exponential backoff and full jitter; `Retry-After`
wins when the server sends it. 4xx is never retried — it will not start succeeding.

**Idempotency.** Every mutating request carries an `Idempotency-Key`, generated if you do not supply
one, and **reused across retries** so a retried booking cannot become two bookings. Pass your own
order id for end-to-end deduplication:

```ruby
client.inventory.book(event_key, hold_id: hold_id, idempotency_key: "order-#{order_id}")
```

```ruby
SeatLayer::Client.new(
  ENV.fetch("SEATLAYER_SECRET_KEY"),
  max_retries: 3,   # total attempts
  timeout: 30.0     # seconds, per attempt
)
```

## Escape hatch

For surface this SDK does not wrap yet — same auth, retries, idempotency and error mapping:

```ruby
client.request("POST", "/v1/events/ev_1/some-new-route", body: { "qty" => 2 })
```

## API surface

| Resource | Methods |
| --- | --- |
| `charts` | `list` `list_all` `create` `retrieve` `update` `delete` `copy` `archive` `unarchive` `publish` |
| `events` | `list` `list_all` `create` `retrieve` `update` `delete` `update_chart` `close` `reopen` `archive` `retrieve_hold_ttl` `update_hold_ttl` `retrieve_report` `retrieve_log` |
| `inventory` | `hold` `hold_best_available` `book_best_available` `extend_hold` `retrieve_hold` `release` `book` `box_office_book` `unbook` `block` `unblock` `unblock_all` `retrieve_availability` `update_availability` |
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
- [SeatLayer GitHub organization](https://github.com/seatlayer)

### Other SeatLayer SDKs

| Surface | Package |
|---|---|
| Browser (vanilla) | [`@seatlayer/js`](https://github.com/seatlayer/seatlayer-sdk) |
| React | [`@seatlayer/react`](https://github.com/seatlayer/seatlayer-sdk) |
| React Native | [`@seatlayer/react-native`](https://github.com/seatlayer/seatlayer-react-native) |
| iOS | [`seatlayer-ios`](https://github.com/seatlayer/seatlayer-ios) |
| Android | [`seatlayer-android`](https://github.com/seatlayer/seatlayer-android) |
| Flutter | [`seatlayer_flutter`](https://github.com/seatlayer/seatlayer-flutter) |
| Node.js (server) | [`@seatlayer/server`](https://github.com/seatlayer/seatlayer-node) |
| Python (server) | [`seatlayer`](https://github.com/seatlayer/seatlayer-python) |
| PHP (server) | [`seatlayer/seatlayer-php`](https://github.com/seatlayer/seatlayer-php) |
| Java (server) | [`io.seatlayer:seatlayer-java`](https://github.com/seatlayer/seatlayer-java) |
| Go (server) | [`github.com/seatlayer/seatlayer-go`](https://github.com/seatlayer/seatlayer-go) |
| .NET (server) | [`SeatLayer`](https://github.com/seatlayer/seatlayer-dotnet) |

## Development

```bash
bundle install
bundle exec rubocop
bundle exec rspec
```

## License

MIT
