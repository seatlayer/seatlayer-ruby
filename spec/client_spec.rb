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

    it "attaches an Idempotency-Key to mutations but not to reads" do
      client, transport = build_client([{ status: 200, body: '{"events":[]}' }, { status: 201 }])

      client.events.list
      client.events.create(chart_id: "c_1")

      expect(transport.calls[0].headers).not_to have_key("Idempotency-Key")
      expect(transport.calls[1].headers["Idempotency-Key"]).to match(/\A[A-Za-z0-9._:-]{1,128}\z/)
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
      client, = build_client([{ status: 502, body: "<html>bad gateway</html>" }], max_retries: 1)

      expect { client.events.retrieve("ev_1") }.to raise_error(SeatLayer::APIError) { |error|
        expect(error.status).to eq(502)
      }
    end
  end

  describe "retry" do
    it "retries a 429 and reuses the same idempotency key" do
      client, transport = build_client([
                                         { status: 429, body: '{"error":"rate_limited"}',
                                           headers: { "Retry-After" => "0" } },
                                         { status: 201, body: '{"ok":true}' }
                                       ])

      client.events.create(chart_id: "c_1")

      expect(transport.calls.length).to eq(2)
      # Same key on the retry, or the server would create two events.
      expect(transport.calls[0].headers["Idempotency-Key"])
        .to eq(transport.calls[1].headers["Idempotency-Key"])
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
                               body: '{"error":"rate_limited","retryAfterSeconds":99}',
                               headers: { "Retry-After" => "0" }
                             }], max_retries: 1)

      expect { client.events.retrieve("ev_1") }.to raise_error(SeatLayer::RateLimitError) { |error|
        expect(error.retry_after).to eq(0.0)
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
  end
end
