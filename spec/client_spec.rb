# frozen_string_literal: true

RSpec.describe SeatLayer::Client do
  describe "construction" do
    it "rejects a publishable key by name" do
      # The pk_/sk_ mix-up is the most common first-run failure; a 401 three
      # round-trips later teaches nothing.
      expect { described_class.new("pk_test_abc") }
        .to raise_error(ArgumentError, /publishable key/)
    end

    it "rejects anything that is not a secret key" do
      expect { described_class.new("nonsense") }.to raise_error(ArgumentError, /sk_live_ or sk_test_/)
      expect { described_class.new("") }.to raise_error(ArgumentError, /required/)
    end

    it "reports the key mode" do
      expect(described_class.new("sk_test_abc").mode).to eq("test")
      expect(described_class.new("sk_live_abc").mode).to eq("live")
    end
  end

  describe "requests" do
    it "sends bearer auth and parses the body" do
      client, transport = build_client([{ status: 200, body: '{"meta":{"key":"ev_1"}}' }])

      result = client.events.retrieve("ev_1")

      expect(result.dig("meta", "key")).to eq("ev_1")
      expect(transport.calls[0].headers["Authorization"]).to eq("Bearer sk_test_abc")
      expect(transport.calls[0].url).to eq("https://api.seatlayer.io/v1/events/ev_1")
    end

    it "percent-encodes path parameters" do
      client, transport = build_client([{ status: 200 }])
      client.events.retrieve("ev/../admin")
      expect(transport.calls[0].url).to eq("https://api.seatlayer.io/v1/events/ev%2F..%2Fadmin")
    end

    it "only generates an Idempotency-Key for header-replay mutations" do
      client, transport = build_client([
                                         { status: 200, body: '{"events":[]}' },
                                         { status: 201 },
                                         { status: 201 }
                                       ])

      client.events.list
      client.events.create(chart_id: "c_1")
      client.inventory.hold("ev_1", labels: ["A-1"])

      expect(transport.calls[0].headers).not_to have_key("Idempotency-Key")
      expect(transport.calls[1].headers["Idempotency-Key"]).to match(/\A[A-Za-z0-9._:-]{1,128}\z/)
      expect(transport.calls[2].headers).not_to have_key("Idempotency-Key")
    end

    it "honours a caller-supplied idempotency key" do
      client, transport = build_client([{ status: 201 }])
      client.events.create(chart_id: "c_1", idempotency_key: "order-42")
      expect(transport.calls[0].headers["Idempotency-Key"]).to eq("order-42")
    end

    it "rejects an idempotency key the API would reject" do
      client, = build_client([])
      expect { client.events.create(chart_id: "c_1", idempotency_key: "has spaces") }
        .to raise_error(ArgumentError, /Invalid Idempotency-Key/)
    end

    it "drops nil query parameters instead of sending them" do
      client, transport = build_client([{ status: 200, body: '{"charts":[]}' }])
      client.charts.list(workspace_id: "ws_1")
      expect(transport.calls[0].url).to eq("https://api.seatlayer.io/v1/charts?workspaceId=ws_1")
    end

    it "omits empty optional fields rather than sending null" do
      # Sending "name": null is not the same as omitting it; some fields treat an
      # explicit null as "clear this".
      client, transport = build_client([{ status: 201 }])
      client.events.create(chart_id: "c_1")

      body = JSON.parse(transport.calls[0].body)
      expect(body.keys).to eq(["chartId"])
    end
  end

  describe "errors" do
    [
      [{ "code" => "stable_code", "error" => "legacy_error" }, "stable_code"],
      [{ "error" => "legacy_error" }, "legacy_error"]
    ].each do |body, expected_code|
      it "uses #{expected_code} with complete response evidence" do
        response_body = body.merge("details" => { "field" => "slug" })
        client, = build_client([{
                                 status: 400,
                                 body: response_body.to_json,
                                 headers: { "X-Request-ID" => "req_contract_1" }
                               }])

        expect do
          client.request("POST", "/v1/contract-fixture", body: { "value" => 1 })
        end.to raise_error(SeatLayer::APIError) { |error|
          expect(error.class).to eq(SeatLayer::APIError)
          expect(error.status).to eq(400)
          expect(error.code).to eq(expected_code)
          expect(error.body).to eq(response_body)
          expect(error.request_id).to eq("req_contract_1")
        }
      end
    end

    it "maps 403 mode_mismatch to a typed, self-explaining error" do
      client, = build_client([{ status: 403, body: '{"error":"mode_mismatch"}' }])

      expect { client.events.retrieve("ev_1") }.to raise_error(SeatLayer::AuthError) { |error|
        expect(error).to be_mode_mismatch
      }
    end

    it "exposes conflicts on a 409 so callers can branch per seat" do
      client, = build_client([{
                               status: 409,
                               body: '{"error":"conflict","conflicts":[{"label":"A-1","status":"booked"}]}'
                             }])

      expect { client.inventory.hold("ev_1", labels: ["A-1"]) }
        .to raise_error(SeatLayer::ConflictError) { |error|
          expect(error.conflicts).to eq([{ "label" => "A-1", "status" => "booked" }])
        }
    end

    it "flags a sold-out best-available result as a business outcome" do
      client, = build_client([{ status: 409, body: '{"error":"conflict","reason":"sold_out"}' }])

      expect { client.inventory.hold_best_available("ev_1", qty: 4) }
        .to raise_error(SeatLayer::ConflictError) { |error| expect(error).to be_sold_out }
    end

    it "surfaces the request id for support" do
      client, = build_client(
        [{ status: 500, body: '{"error":"internal"}', headers: { "X-Request-ID" => "req_9" } }],
        max_retries: 1
      )

      expect { client.events.retrieve("ev_1") }.to raise_error(SeatLayer::APIError) { |error|
        expect(error.request_id).to eq("req_9")
      }
    end

    it "survives an error body that is not JSON" do
      # A proxy or WAF can answer with HTML; that must not become a parse crash
      # that hides the real status from the caller.
      client, = build_client([{
                               status: 502,
                               body: "<html>bad gateway</html>",
                               headers: { "X-Request-ID" => "req_proxy_1" }
                             }], max_retries: 1)

      expect { client.events.retrieve("ev_1") }.to raise_error(SeatLayer::APIError) { |error|
        expect(error.class).to eq(SeatLayer::APIError)
        expect(error.status).to eq(502)
        expect(error.code).to eq("unknown_error")
        expect(error.body).to eq({})
        expect(error.request_id).to eq("req_proxy_1")
      }
    end
  end

  describe "retry" do
    it "retries only header-replay mutations and reuses their idempotency key" do
      operations = {
        "create chart" => ->(client) { client.charts.create(name: "Main") },
        "copy chart" => ->(client) { client.charts.copy("c_1") },
        "create event" => ->(client) { client.events.create(chart_id: "c_1") },
        "create workspace" => ->(client) { client.workspaces.create(name: "Tenant") }
      }

      operations.each do |name, operation|
        client, transport = build_client([
                                           { status: 429, body: '{"error":"rate_limited"}',
                                             headers: { "Retry-After" => "0" } },
                                           { status: 201, body: '{"ok":true}' }
                                         ])

        operation.call(client)

        expect(transport.calls.length).to eq(2), name
        expect(transport.calls[0].headers["Idempotency-Key"])
          .to eq(transport.calls[1].headers["Idempotency-Key"]), name
      end
    end

    it "keeps booking single-attempt even when the caller supplies a key" do
      client, transport = build_client([{
                                         status: 429,
                                         headers: { "Retry-After" => "0" }
                                       }])

      expect do
        client.inventory.book(
          "ev_1", labels: ["A-1"], booking_ref: "order-42", idempotency_key: "request-42"
        )
      end.to raise_error(SeatLayer::RateLimitError)

      expect(transport.calls.length).to eq(1)
      expect(transport.calls[0].headers["Idempotency-Key"]).to eq("request-42")
    end

    it "fails closed for raw mutation retries" do
      client, transport = build_client([{
                                         status: 429,
                                         headers: { "Retry-After" => "0" }
                                       }])

      expect do
        client.request(
          "POST", "/v1/events", body: { "chartId" => "c_1" }, idempotency_key: "raw-42"
        )
      end.to raise_error(SeatLayer::RateLimitError)

      expect(transport.calls.length).to eq(1)
    end

    it "never retries an access-link one-time reveal" do
      client, transport = build_client([
                                         { status: 500, body: '{"code":"internal"}' },
                                         { status: 201, body: "{}" }
                                       ], max_retries: 2)

      expect { client.channels.create_access_link("ev_1", "ch_1") }
        .to raise_error(SeatLayer::APIError)
      expect(transport.calls.length).to eq(1)
    end

    it "retains retries for reads" do
      client, transport = build_client([
                                         { status: 429, headers: { "Retry-After" => "0" } },
                                         { status: 200, body: '{"meta":{"key":"ev_1"}}' }
                                       ])

      client.events.retrieve("ev_1")

      expect(transport.calls.length).to eq(2)
    end

    it "does not retry a 4xx that will never succeed" do
      client, transport = build_client([{ status: 422, body: '{"error":"invalid_slug"}' }])

      expect { client.events.create(chart_id: "c_1") }.to raise_error(SeatLayer::ValidationError)
      expect(transport.calls.length).to eq(1)
    end

    it "gives up after max_retries and raises the last error" do
      client, transport = build_client([
                                         { status: 429, headers: { "Retry-After" => "0" } },
                                         { status: 429, headers: { "Retry-After" => "0" } }
                                       ], max_retries: 2)

      expect { client.events.create(chart_id: "c_1") }.to raise_error(SeatLayer::RateLimitError)
      expect(transport.calls.length).to eq(2)
    end

    it "prefers Retry-After over the JSON field" do
      client, = build_client([{
                               status: 429,
                               body: '{"code":"rate_budget_exhausted",' \
                                     '"error":"rate_limited","retryAfterSeconds":99}',
                               headers: { "Retry-After" => "7", "X-Request-ID" => "req_rate_1" }
                             }], max_retries: 1)

      expect { client.events.retrieve("ev_1") }.to raise_error(SeatLayer::RateLimitError) { |error|
        expect(error.retry_after).to eq(7.0)
        expect(error.status).to eq(429)
        expect(error.code).to eq("rate_budget_exhausted")
        expect(error.body["retryAfterSeconds"]).to eq(99)
        expect(error.request_id).to eq("req_rate_1")
      }
    end
  end

  describe "pagination" do
    it "walks every page with list_all and stops when the cursor runs out" do
      client, transport = build_client([
                                         { status: 200, body: '{"charts":[{"id":"c_1"},' \
                                                              '{"id":"c_2"}],"nextCursor":"cur_1"}' },
                                         { status: 200, body: '{"charts":[{"id":"c_3"}]}' }
                                       ])

      seen = client.charts.list_all.map { |chart| chart["id"] }

      expect(seen).to eq(%w[c_1 c_2 c_3])
      expect(transport.calls.length).to eq(2)
      # Absent nextCursor terminates — a caller looping cannot spin forever.
      expect(transport.calls[1].url).to include("cursor=cur_1")
    end

    it "returns a lazy Enumerator when no block is given" do
      # The point of paginating was to not hold an unbounded result set in
      # memory; .lazy.first(1) must not fetch every page.
      client, transport = build_client([
                                         { status: 200,
                                           body: '{"charts":[{"id":"c_1"}],"nextCursor":"cur_1"}' }
                                       ])

      expect(client.charts.list_all).to be_a(Enumerator)
      expect(client.charts.list_all.lazy.first(1).map { |c| c["id"] }).to eq(["c_1"])
      expect(transport.calls.length).to eq(1)
    end

    it "drops the per-event counts fanout when walking every event" do
      # Counts cost a server round-trip PER EVENT, which is exactly the cost
      # pagination was added to avoid.
      client, transport = build_client([{ status: 200, body: '{"events":[]}' }])
      client.events.list_all.to_a
      expect(transport.calls[0].url).to include("counts=0")
    end

    it "keeps counts on a single explicit page" do
      client, transport = build_client([{ status: 200, body: '{"events":[]}' }])
      client.events.list(limit: 10)
      expect(transport.calls[0].url).not_to include("counts=0")
    end
  end

  describe "guards" do
    it "refuses to mint a manage session without explicit capabilities" do
      client, = build_client([])
      # The API would default this to all four including event:cancel — the
      # ability to reverse paid bookings should never arrive by omission.
      expect do
        client.sessions.create_manage_session("ev_1", allowed_origin: "https://box.example",
                                                      capabilities: [])
      end.to raise_error(ArgumentError, /capabilities is required/)
    end

    it "mints with the capabilities it was given" do
      client, transport = build_client([{ status: 201, body: '{"token":"mse_x"}' }])
      client.sessions.create_manage_session("ev_1", allowed_origin: "https://box.example",
                                                    capabilities: ["event:view"])

      expect(JSON.parse(transport.calls[0].body)["capabilities"]).to eq(["event:view"])
    end

    it "sends expectedUpdatedAt on a chart update" do
      client, transport = build_client([{ status: 200, body: '{"meta":{}}' }])
      client.charts.update("c_1", doc: { "version" => 1 }, expected_updated_at: 1234)

      expect(JSON.parse(transport.calls[0].body)["expectedUpdatedAt"]).to eq(1234)
    end

    it "supports chart-copy overrides and metadata-only updates" do
      client, transport = build_client([{ status: 201 }, { status: 200 }])
      client.charts.copy("c/1", name: "Balcony", external_ref: nil, workspace_id: "ws_2")
      client.charts.update("c/1", name: "Arena", issues: 2, external_ref: nil)

      expect(JSON.parse(transport.calls[0].body)).to eq(
        "name" => "Balcony", "externalRef" => nil, "workspaceId" => "ws_2"
      )
      expect(JSON.parse(transport.calls[1].body)).to eq(
        "name" => "Arena", "issues" => 2, "externalRef" => nil
      )
    end

    it "posts the hold id to the extend route" do
      client, transport = build_client([{ status: 200, body: '{"ok":true,"expiresAt":123}' }])
      client.inventory.extend_hold("ev_1", "h_9", ttl_ms: 600_000)

      expect(transport.calls[0].url).to eq("https://api.seatlayer.io/v1/events/ev_1/extend")
      expect(JSON.parse(transport.calls[0].body))
        .to eq({ "holdId" => "h_9", "ttlMs" => 600_000 })
    end

    it "surfaces a spent hold as a conflict, not a generic failure" do
      client, = build_client([{ status: 409, body: '{"error":"cannot_extend","reason":"expired"}' }])

      expect { client.inventory.extend_hold("ev_1", "h_9") }
        .to raise_error(SeatLayer::ConflictError) { |error| expect(error.code).to eq("cannot_extend") }
    end

    it "requires a stable booking reference and sends it when unbooking" do
      client, transport = build_client([{ status: 200, body: '{"ok":true}' }])

      expect { client.inventory.book("ev_1", hold_id: "h_1", booking_ref: "  ") }
        .to raise_error(ArgumentError, /booking_ref is required/)

      client.inventory.unbook("ev_1", labels: ["A-1"], booking_ref: " order-42 ")
      expect(JSON.parse(transport.calls[0].body))
        .to eq({ "labels" => ["A-1"], "bookingRef" => "order-42" })
    end
  end

  describe "channels and booking lifecycle" do
    it "creates a channel using the API's camel-case contract" do
      client, transport = build_client([{ status: 201, body: '{"ok":true}' }])
      client.channels.create_channel("ev/1", name: "Partners", external_ref: "partner-a",
                                             access_intent: "server")

      expect(transport.calls[0].url).to eq("https://api.seatlayer.io/v1/events/ev%2F1/channels")
      expected = { "name" => "Partners", "externalRef" => "partner-a",
                   "accessIntent" => "server" }
      expect(JSON.parse(transport.calls[0].body)).to eq(expected)
    end

    it "mints origin-bound buyer access for explicit allocations" do
      client, transport = build_client([{ status: 201, body: '{"token":"bse_x"}' }])
      client.channels.create_buyer_access_session(
        "ev_1", include_public: false, allowed_origin: "https://tickets.example",
                channel_ids: ["chn_partner"]
      )

      expected = { "channelIds" => ["chn_partner"], "includePublic" => false,
                   "allowedOrigin" => "https://tickets.example" }
      expect(JSON.parse(transport.calls[0].body)).to eq(expected)
    end

    it "passes channel authority fields through inventory holds" do
      client, transport = build_client([{ status: 201, body: '{"holdId":"h_1"}' }])
      client.inventory.hold("ev_1", labels: ["A-1"], channel_ids: ["chn_partner"],
                                    ignore_channel_restrictions: false, reason: "partner order")

      expected = { "labels" => ["A-1"], "channelIds" => ["chn_partner"],
                   "ignoreChannelRestrictions" => false, "reason" => "partner order" }
      expect(JSON.parse(transport.calls[0].body)).to eq(expected)
    end

    it "reads a booking by a normalised and encoded reference" do
      client, transport = build_client([{ status: 200, body: "{}" }])
      client.inventory.retrieve_booking("ev_1", " order/42 ")
      expect(transport.calls[0].url)
        .to eq("https://api.seatlayer.io/v1/events/ev_1/bookings/order%2F42")
    end
  end

  describe "generated public wire contract" do
    it "instantiates templates with an empty object and exact-response replay" do
      client, transport = build_client([
                                         { status: 429, body: '{"error":"rate_limited"}',
                                           headers: { "retry-after" => "0" } },
                                         { status: 201, body: '{"meta":{"id":"c_1"}}' }
                                       ])
      client.templates.instantiate_template("arena/standard")

      expect(transport.calls).to have_attributes(length: 2)
      expect(transport.calls[0].url).to end_with("/v1/templates/arena%2Fstandard/instantiate")
      expect(transport.calls[0].body).to eq("{}")
      expect(transport.calls[0].headers["Idempotency-Key"])
        .to eq(transport.calls[1].headers["Idempotency-Key"])
    end

    it "wraps ticket release routes with replacement bodies and single-attempt writes" do
      client, transport = build_client([
                                         { status: 200, body: '{"releases":[]}' },
                                         { status: 200, body: '{"releases":[]}' },
                                         { status: 429, body: '{"error":"rate_limited"}',
                                           headers: { "retry-after" => "0" } }
                                       ])
      client.events.list_ticket_releases("ev/1")
      client.events.update_ticket_releases(
        "ev/1", releases: [{ "id" => "rel_1", "name" => "Early", "price" => 2500, "action" => "buy" }]
      )

      expect { client.events.close_ticket_release("ev/1", "rel/1") }
        .to raise_error(SeatLayer::RateLimitError)

      expect(transport.calls).to have_attributes(length: 3)
      expect(transport.calls[0].http_method).to eq("GET")
      expect(transport.calls[0].url).to end_with("/v1/events/ev%2F1/releases")
      expect(JSON.parse(transport.calls[1].body)).to eq(
        "releases" => [{ "id" => "rel_1", "name" => "Early", "price" => 2500, "action" => "buy" }]
      )
      expect(transport.calls[2].url).to end_with("/v1/events/ev%2F1/releases/rel%2F1/close")
      expect(transport.calls[2].headers).not_to have_key("Idempotency-Key")
    end

    it "reads, attaches, and explicitly detaches an Event configuration" do
      binding = {
        "configuration" => { "id" => "ec_touring", "version" => 3 },
        "revision" => 7, "changedBy" => "api-key:key_1", "changedAt" => 123,
        "audit" => [{ "id" => "eca_1", "from" => nil,
                      "to" => { "id" => "ec_touring", "version" => 3 },
                      "revision" => 7, "actor" => "api-key:key_1", "createdAt" => 123 }]
      }
      detached_body = '{"configuration":null,"revision":8,' \
                      '"changedBy":null,"changedAt":null,"audit":[]}'
      client, transport = build_client([
                                         { status: 200, body: JSON.generate(binding) },
                                         { status: 200, body: JSON.generate(binding) },
                                         { status: 200, body: detached_body }
                                       ])

      retrieved = client.events.retrieve_configuration_binding("ev / main")
      attached = client.events.update_configuration_binding(
        "ev / main", expected_revision: 6,
                     configuration: { "id" => "ec_touring", "version" => 3 }
      )
      detached = client.events.update_configuration_binding(
        "ev / main", expected_revision: 7, configuration: nil
      )

      expect(retrieved.fetch("audit").first.fetch("from")).to be_nil
      expect(attached.dig("configuration", "id")).to eq("ec_touring")
      expect(detached.fetch("configuration")).to be_nil
      expect(transport.calls.map(&:url)).to all(
        end_with("/v1/events/ev%20%2F%20main/event-configuration")
      )
      expect(transport.calls.map(&:http_method)).to eq(%w[GET PUT PUT])
      expect(JSON.parse(transport.calls[1].body)).to eq(
        "expectedRevision" => 6,
        "configuration" => { "id" => "ec_touring", "version" => 3 }
      )
      expect(JSON.parse(transport.calls[2].body)).to eq(
        "expectedRevision" => 7, "configuration" => nil
      )
      expect(transport.calls[1].headers).not_to have_key("Idempotency-Key")
      expect(transport.calls[2].headers).not_to have_key("Idempotency-Key")

      retry_client, retry_transport = build_client([
                                                     { status: 429,
                                                       body: '{"error":"rate_limited"}',
                                                       headers: { "retry-after" => "0" } }
                                                   ])
      expect do
        retry_client.events.update_configuration_binding(
          "ev_1", expected_revision: 1, configuration: nil
        )
      end.to raise_error(SeatLayer::RateLimitError)
      expect(retry_transport.calls.length).to eq(1)
    end

    it "sends the expanded event, hold, and block fields" do
      client, transport = build_client([
                                         { status: 201, body: '{"meta":{"key":"ev_1"}}' },
                                         { status: 200, body: '{"ok":true,"updated":true,"meta":{}}' },
                                         { status: 200, body: '{"ok":true,"holdTtlMs":null}' },
                                         { status: 200, body: '{"ok":true,"blocked":["A-1"]}' },
                                         { status: 200, body: '{"ok":true,"extends":1}' }
                                       ])

      client.events.create(chart_id: "c_1", venue: nil, description: "Matinee", ends_at: 1800,
                           timezone: "Asia/Kolkata", locale: "en-IN", poster_asset_id: "ast_1")
      client.events.update_chart("ev_1", acknowledge_dropped_assignments: true,
                                         reason: "approved migration")
      client.events.update_hold_ttl("ev_1", nil)
      client.inventory.block("ev_1", labels: ["A-1"], release_at: 2000)
      client.inventory.extend_hold("ev_1", "h_1", channel_ids: ["ch_partner"],
                                                  ignore_channel_restrictions: true,
                                                  reason: "staff override")

      expect(JSON.parse(transport.calls[0].body)).to include(
        "venue" => nil, "description" => "Matinee", "endsAt" => 1800,
        "posterAssetId" => "ast_1"
      )
      expect(JSON.parse(transport.calls[1].body)).to eq(
        "acknowledgeDroppedAssignments" => true, "reason" => "approved migration"
      )
      expect(JSON.parse(transport.calls[2].body)).to eq("holdTtlMs" => nil)
      expect(JSON.parse(transport.calls[3].body)).to eq("labels" => ["A-1"], "releaseAt" => 2000)
      expect(JSON.parse(transport.calls[4].body)).to include(
        "channelIds" => ["ch_partner"], "ignoreChannelRestrictions" => true,
        "reason" => "staff override"
      )
    end

    it "uploads raw event posters and forwards event-log cursors" do
      image = "\x89PNG\r\n\x1A\nposter".b
      client, transport = build_client([
                                         { status: 200, body: '{"meta":{"key":"ev_1"}}' },
                                         { status: 200, body: '{"meta":{"key":"ev_1"}}' },
                                         { status: 200, body: '{"entries":[],"nextBefore":null}' }
                                       ])
      client.events.update_poster("ev/1", image, content_type: "image/png")
      client.events.delete_poster("ev/1")
      client.events.retrieve_log("ev/1", limit: 50, before: 123)

      expect(transport.calls[0].url).to end_with("/v1/events/ev%2F1/poster")
      expect(transport.calls[0].body).to eq(image)
      expect(transport.calls[0].headers["Content-Type"]).to eq("image/png")
      expect(transport.calls[1].http_method).to eq("DELETE")
      expect(transport.calls[2].url).to end_with("/log?limit=50&before=123")
    end

    it "wraps the complete hosted access-link lifecycle" do
      link = {
        "id" => "alk_1", "channelId" => "chn/1", "label" => nil,
        "includePublic" => false, "expiresAt" => 2000, "maxRedemptions" => 10,
        "redemptions" => 0, "maxQuantity" => 4, "sessionTtlSeconds" => 1800,
        "state" => "active", "status" => "active", "createdAt" => 1000,
        "createdBy" => nil, "revokedAt" => nil, "lastRedeemedAt" => nil,
        "rotatedFrom" => nil, "rotatedTo" => nil
      }
      client, transport = build_client([
                                         { status: 201, body: {
                                           "link" => link,
                                           "url" => "https://app.seatlayer.io/a#once",
                                           "capability" => "alc_once", "revealedOnce" => true
                                         }.to_json },
                                         { status: 200,
                                           body: { "links" => [link.merge("activeSessions" => 0)] }.to_json },
                                         { status: 201, body: {
                                           "link" => link,
                                           "url" => "https://app.seatlayer.io/a#next",
                                           "capability" => "alc_next", "revealedOnce" => true,
                                           "previous" => link, "endedSessions" => 2
                                         }.to_json },
                                         { status: 200, body: {
                                           "ok" => true, "link" => link, "endedSessions" => 2
                                         }.to_json }
                                       ])

      created = client.channels.create_access_link(
        "ev/1", "chn/1", label: nil, expires_at: 2000, include_public: false,
                         idempotency_key: "access-1"
      )
      listed = client.channels.list_access_links("ev/1", "chn/1")
      rotated = client.channels.rotate_access_link(
        "ev/1", "chn/1", "alk/1", end_active_sessions: false, reason: "misplaced"
      )
      revoked = client.channels.revoke_access_link(
        "ev/1", "chn/1", "alk/1", end_active_sessions: true, reason: "leaked URL"
      )

      expect(created.fetch("capability")).to eq("alc_once")
      expect(listed.dig("links", 0, "activeSessions")).to eq(0)
      expect(rotated.fetch("endedSessions")).to eq(2)
      expect(revoked.fetch("ok")).to be(true)
      expect(JSON.parse(transport.calls[0].body)).to eq(
        "label" => nil, "expiresAt" => 2000, "includePublic" => false
      )
      expect(transport.calls[0].headers["Idempotency-Key"]).to eq("access-1")
      expect(JSON.parse(transport.calls[2].body)).to eq(
        "endActiveSessions" => false, "reason" => "misplaced"
      )
      expect(transport.calls[3].url).to end_with(
        "/channels/chn%2F1/access-links/alk%2F1?endActiveSessions=1&reason=leaked+URL"
      )
    end

    it "preserves explicit nulls for buyer and workspace fields" do
      client, transport = build_client([{ status: 201 }, { status: 201 }])
      client.channels.create_buyer_access_session(
        "ev_1", include_public: false, allowed_origin: "https://tickets.example",
                max_quantity: nil, buyer_ref: nil, partner_ref: nil, client_request_id: nil
      )
      client.workspaces.create(name: "Promoter", external_ref: nil)

      expect(JSON.parse(transport.calls[0].body)).to eq(
        "includePublic" => false, "allowedOrigin" => "https://tickets.example",
        "maxQuantity" => nil, "buyerRef" => nil, "partnerRef" => nil,
        "clientRequestId" => nil
      )
      expect(JSON.parse(transport.calls[1].body)).to eq(
        "name" => "Promoter", "externalRef" => nil
      )
    end

    it "preserves webhook envelopes and sends delivery filters" do
      sub = { "id" => "wh_1", "url" => "https://hooks.example/seatlayer",
              "events" => ["seat.booked"], "disabled" => false }
      client, transport = build_client([
                                         { status: 200, body: { "subs" => [sub] }.to_json },
                                         { status: 201,
                                           body: { "sub" => sub, "secret" => "whsec_once" }.to_json },
                                         { status: 200,
                                           body: { "sub" => sub.merge("disabled" => true) }.to_json },
                                         { status: 200,
                                           body: { "deliveries" => [], "nextBefore" => 100 }.to_json }
                                       ])

      expect(client.webhooks.list.fetch("subs").first.fetch("events")).to eq(["seat.booked"])
      expect(client.webhooks.create(url: sub.fetch("url"), events: ["seat.booked"])
                   .fetch("secret")).to eq("whsec_once")
      expect(client.webhooks.update("wh_1", disabled: true).dig("sub", "disabled")).to be(true)
      expect(client.webhooks.list_deliveries("wh_1", limit: 10, status: "failed", before: 200)
                   .fetch("nextBefore")).to eq(100)

      expect(JSON.parse(transport.calls[2].body)).to eq("disabled" => true)
      expect(transport.calls[3].url)
        .to end_with("/v1/webhooks/wh_1/deliveries?limit=10&status=failed&before=200")
    end

    it "returns the hold and Designer envelopes without flattening them" do
      client, transport = build_client([
                                         { status: 200,
                                           body: '{"holdId":"h_1","status":"active",' \
                                                 '"eventKey":"ev_1","workspaceId":"ws_1",' \
                                                 '"bookingRef":null,"items":[]}' },
                                         { status: 201,
                                           body: '{"session":{"id":"dsess_1","mode":"safe"}}' },
                                         { status: 200, body: '{"sessions":[]}' }
                                       ])

      hold = client.inventory.retrieve_hold("ev_1", "h_1")
      expect(hold.slice("holdId", "status", "eventKey", "workspaceId")).to eq(
        "holdId" => "h_1", "status" => "active", "eventKey" => "ev_1", "workspaceId" => "ws_1"
      )
      designer = client.sessions.create_designer_session(
        workspace_id: "ws_1", chart_id: "c_1", allowed_origin: "https://app.example",
        mode: "safe", safe_mode_options: { "allowDeletingObjects" => false },
        features: { "images" => false }
      )
      expect(designer.dig("session", "id")).to eq("dsess_1")
      expect(JSON.parse(transport.calls[1].body)).to include(
        "safeModeOptions" => { "allowDeletingObjects" => false },
        "features" => { "images" => false }
      )

      client.channels.list_buyer_access_sessions("ev_1", limit: 25)
      expect(transport.calls[2].url).to end_with("/buyer-access-sessions?limit=25")
    end

    it "rejects unknown webhook events before transport" do
      client, = build_client([])
      expect { client.webhooks.create(url: "https://hooks.example", events: ["booking.created"]) }
        .to raise_error(ArgumentError, /supported SeatLayer webhook event names/)
    end
  end
end
