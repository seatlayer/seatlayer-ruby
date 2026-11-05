# frozen_string_literal: true

RSpec.describe SeatLayer::Seasons do
  it "maps all 86 Season operations and their exact replay classes" do
    client, transport = build_client(Array.new(86) { { status: 200 } })
    seasons = client.seasons
    key = "sea/a"

    seasons.list_seasons(workspace_id: "ws 1", structure_state: "draft", limit: 20, cursor: "c/1")
    seasons.validate_season(source_performance_group_keys: ["pg_1"])
    seasons.create_season(name: "Series", event_keys: %w[ev_1 ev_2], idempotency_key: "create-1")
    seasons.retrieve_season(key)
    seasons.update_season(key, expected_revision: 1, name: "Series 2", idempotency_key: "update-1")
    seasons.delete_season(key, idempotency_key: "delete-1")
    seasons.activate_season(key, expected_revision: 1)
    seasons.close_season(key, expected_revision: 2)
    seasons.archive_season(key, expected_revision: 3)
    seasons.retrieve_season_lifecycle(key, "life/1")
    seasons.create_season_plan(key, name: "Plan", event_keys: %w[ev_1 ev_2], idempotency_key: "plan-1")
    seasons.retrieve_season_plan(key, "plan/1")
    seasons.publish_season_plan(key, "plan/1", expected_revision: 2)
    seasons.supersede_season_plan(key, "plan/1", expected_revision: 3)
    seasons.open_season_sales(key, expected_revision: 3)
    seasons.pause_season_sales(key, expected_revision: 4)
    seasons.resume_season_sales(key, expected_revision: 5)
    seasons.end_season_sales(key, expected_revision: 6)
    seasons.duplicate_season_to_live(key, event_keys: %w[live_1 live_2], idempotency_key: "live-1")
    seasons.create_season_buyer_access_session(
      key, allowed_origin: "https://tickets.example", include_public: true
    )
    seasons.list_season_buyer_access_sessions(key, limit: 10)
    seasons.revoke_season_buyer_access_session(key, "session/1")
    seasons.retrieve_season_hold(key, "hold/1")
    seasons.book_season_hold(key, "hold/1", book_action_id: "book_1", booking_ref: "order_1")
    seasons.retrieve_season_booking(key, "book/1")
    seasons.cancel_season_booking(
      key, "book/1", cancel_action_id: "cancel_1", booking_ref: "order_1",
                     plan_activation_id: "pa_1", right_disposition: "release"
    )
    seasons.validate_season_buyer_rehearsal(key)
    seasons.create_season_holder_import(
      key, successor_plan_activation_id: "pa_1", rows: [], idempotency_key: "import-1"
    )
    seasons.retrieve_season_holder_import(key, "import/1")
    seasons.create_season_renewal_offers(key, deadline_at: 123, idempotency_key: "offers-1")
    seasons.list_season_renewal_offers(key)
    seasons.retrieve_season_renewal_offer(key, "offer/1")
    seasons.extend_season_renewal_offer(key, "offer/1", deadline_at: 456)
    seasons.inspect_season_renewal_offer(key, "offer/1")
    seasons.commit_season_renewal_offer(
      key, "offer/1", commit_action_id: "commit_1", order_ref: "order_1",
                      booking_ref: "book_1", plan_activation_id: "pa_1"
    )
    seasons.decline_season_renewal_offer(key, "offer/1")
    seasons.release_season_renewal_offer(key, "offer/1")
    seasons.list_season_occurrences(key)
    seasons.create_season_amendment(
      key, event_key: "ev_1", kind: "reschedule", idempotency_key: "amend-1"
    )
    seasons.list_season_amendments(key)
    seasons.retrieve_season_amendment(key, "amend/1")
    seasons.retrieve_season_report(key)
    seasons.list_season_operations(key)
    seasons.retrieve_season_support_lookup(key, holder_ref: "holder a/b")
    seasons.list_season_outbox(key)
    seasons.replay_season_outbox(key, "occurrence/1")
    seasons.list_season_audit(key)
    seasons.export_season_support_snapshot(key)
    seasons.create_season_holder_import_from_season(
      key, source_season_id: "sea_old", successor_plan_activation_id: "pa_2", dry_run: true,
           idempotency_key: "from-1"
    )
    seasons.list_season_performances(key)
    seasons.create_season_performances(
      key, title_pattern: "Hamlet", timezone: "Europe/London", repeat: "weekly", count: 3,
           venue: nil, idempotency_key: "perf-1"
    )
    seasons.attach_season_performances(key, event_keys: ["ev_3"], idempotency_key: "attach-1")
    seasons.delete_season_performance(key, "ev/3")
    seasons.update_season_plan(key, "plan/1", name: "Gold")
    seasons.delete_season_plan(key, "plan/1")
    seasons.publish_season(key)
    seasons.create_season_checkout_test(key, plan_key: "plan/1", quantity: 2)
    seasons.list_season_checkout_tests(key)
    seasons.replace_season_package_prices(
      key, "plan/1", prices: [{ "categoryKey" => "stalls", "unitPrice" => 9000 }], currency: "GBP"
    )
    seasons.list_season_prices(key)
    seasons.attach_season_plan_performance(key, "plan/1", event_key: "ev/3")
    seasons.delete_season_plan_performance(key, "plan/1", "ev/3")
    seasons.mark_season_performance_past(key, "ev/3", force: true)
    seasons.return_season_occurrence_inventory(
      key, "ev/3", action_id: "ret_1", booking_ref: "order_1", plan_activation_id: "pa_1",
                   labels: ["A-1"], source: { "bookingActionId" => "book_1" }
    )
    seasons.reclaim_season_occurrence_inventory(
      key, "ev/3", action_id: "rec_1", return_action_id: "ret_1", booking_ref: "order_1",
                   plan_activation_id: "pa_1", labels: ["A-1"], source: { "renewalOfferId" => "o_1" }
    )
    seasons.list_season_holders(key, search: "ann lee", status: "active", limit: 50)
    seasons.refund_season_order(key, "ord/1", amount_minor: 500)
    seasons.cancel_season_order(key, "ord/1", reason: "other", note: "Duplicate", notify_buyer: false)
    seasons.cancel_season_order_date(key, "ord/1", "ev/3", action_id: "date_1")
    seasons.resend_season_order_tickets(key, "ord/1", email: "ann@example.com")
    seasons.retrieve_season_hosted_renewals(key)
    seasons.rotate_season_renewal_offer_link(key, "offer/1")
    seasons.update_season_renewal_offer_contact(key, "offer/1", email: "ann@example.com", name: nil)
    seasons.create_season_renewal_notices(key, offer_ids: ["offer/1"])
    seasons.resend_season_renewal_offer(key, "offer/1")
    seasons.retrieve_season_sales_report(key)
    seasons.retrieve_season_seats_report(key)
    seasons.export_season_holders_csv(key, search: "ann", status: "renewal")
    seasons.export_season_orders_csv(key)
    seasons.retrieve_season_seat_counts(key)
    seasons.refund_season_performance(key, "ev/3", amount: "per_date", reason: "Storm",
                                                   idempotency_key: "refund-date-1")
    seasons.list_season_bulk_jobs(key)
    seasons.retrieve_season_bulk_job(key, "job/1")
    seasons.retrieve_season_renewal_quote(key, "offer/1")
    seasons.create_season_renewal_intent(key, "offer/1")
    seasons.create_season_renewal_checkout(
      key, "offer/1", return_url: "https://tickets.example/renewed", buyer_email: "ana@example.com",
                      buyer_name: "Ana Silva", provider: "stripe", idempotency_key: "renew-1"
    )

    expected = [
      "GET /v1/seasons?workspaceId=ws+1&structureState=draft&limit=20&cursor=c%2F1",
      "POST /v1/seasons/validate", "POST /v1/seasons", "GET /v1/seasons/sea%2Fa",
      "PATCH /v1/seasons/sea%2Fa", "DELETE /v1/seasons/sea%2Fa",
      "POST /v1/seasons/sea%2Fa/activate", "POST /v1/seasons/sea%2Fa/close",
      "POST /v1/seasons/sea%2Fa/archive", "GET /v1/seasons/sea%2Fa/lifecycle/life%2F1",
      "POST /v1/seasons/sea%2Fa/plans", "GET /v1/seasons/sea%2Fa/plans/plan%2F1",
      "POST /v1/seasons/sea%2Fa/plans/plan%2F1/publish",
      "POST /v1/seasons/sea%2Fa/plans/plan%2F1/supersede",
      "POST /v1/seasons/sea%2Fa/sales/open", "POST /v1/seasons/sea%2Fa/sales/pause",
      "POST /v1/seasons/sea%2Fa/sales/resume", "POST /v1/seasons/sea%2Fa/sales/end",
      "POST /v1/seasons/sea%2Fa/duplicate-to-live",
      "POST /v1/seasons/sea%2Fa/buyer-access-sessions",
      "GET /v1/seasons/sea%2Fa/buyer-access-sessions?limit=10",
      "DELETE /v1/seasons/sea%2Fa/buyer-access-sessions/session%2F1",
      "GET /v1/seasons/sea%2Fa/holds/hold%2F1", "POST /v1/seasons/sea%2Fa/holds/hold%2F1/book",
      "GET /v1/seasons/sea%2Fa/bookings/book%2F1", "POST /v1/seasons/sea%2Fa/bookings/book%2F1/cancel",
      "POST /v1/seasons/sea%2Fa/buyer-rehearsals/validate", "POST /v1/seasons/sea%2Fa/imports",
      "GET /v1/seasons/sea%2Fa/imports/import%2F1", "POST /v1/seasons/sea%2Fa/renewal-offers",
      "GET /v1/seasons/sea%2Fa/renewal-offers", "GET /v1/seasons/sea%2Fa/renewal-offers/offer%2F1",
      "POST /v1/seasons/sea%2Fa/renewal-offers/offer%2F1/extend",
      "GET /v1/seasons/sea%2Fa/renewal-offers/offer%2F1/inspect",
      "POST /v1/seasons/sea%2Fa/renewal-offers/offer%2F1/commit",
      "POST /v1/seasons/sea%2Fa/renewal-offers/offer%2F1/decline",
      "POST /v1/seasons/sea%2Fa/renewal-offers/offer%2F1/release",
      "GET /v1/seasons/sea%2Fa/occurrences", "POST /v1/seasons/sea%2Fa/amendments",
      "GET /v1/seasons/sea%2Fa/amendments", "GET /v1/seasons/sea%2Fa/amendments/amend%2F1",
      "GET /v1/seasons/sea%2Fa/reports", "GET /v1/seasons/sea%2Fa/operations",
      "GET /v1/seasons/sea%2Fa/support-lookups?holderRef=holder+a%2Fb",
      "GET /v1/seasons/sea%2Fa/outbox", "POST /v1/seasons/sea%2Fa/outbox/occurrence%2F1/replay",
      "GET /v1/seasons/sea%2Fa/audit", "GET /v1/seasons/sea%2Fa/export",
      "POST /v1/seasons/sea%2Fa/imports/from-season", "GET /v1/seasons/sea%2Fa/performances",
      "POST /v1/seasons/sea%2Fa/performances", "POST /v1/seasons/sea%2Fa/performances/attach",
      "DELETE /v1/seasons/sea%2Fa/performances/ev%2F3", "PATCH /v1/seasons/sea%2Fa/plans/plan%2F1",
      "DELETE /v1/seasons/sea%2Fa/plans/plan%2F1", "POST /v1/seasons/sea%2Fa/publish",
      "POST /v1/seasons/sea%2Fa/checkout-tests", "GET /v1/seasons/sea%2Fa/checkout-tests",
      "PUT /v1/seasons/sea%2Fa/plans/plan%2F1/prices", "GET /v1/seasons/sea%2Fa/prices",
      "POST /v1/seasons/sea%2Fa/plans/plan%2F1/performances",
      "DELETE /v1/seasons/sea%2Fa/plans/plan%2F1/performances/ev%2F3",
      "POST /v1/seasons/sea%2Fa/performances/ev%2F3/past",
      "POST /v1/seasons/sea%2Fa/occurrences/ev%2F3/returns",
      "POST /v1/seasons/sea%2Fa/occurrences/ev%2F3/reclaims",
      "GET /v1/seasons/sea%2Fa/holders?q=ann+lee&status=active&limit=50",
      "POST /v1/seasons/sea%2Fa/orders/ord%2F1/refund", "POST /v1/seasons/sea%2Fa/orders/ord%2F1/cancel",
      "POST /v1/seasons/sea%2Fa/orders/ord%2F1/dates/ev%2F3/cancel",
      "POST /v1/seasons/sea%2Fa/orders/ord%2F1/resend", "GET /v1/seasons/sea%2Fa/renewal-hosted",
      "POST /v1/seasons/sea%2Fa/renewal-offers/offer%2F1/link",
      "POST /v1/seasons/sea%2Fa/renewal-offers/offer%2F1/contact",
      "POST /v1/seasons/sea%2Fa/renewal-notices",
      "POST /v1/seasons/sea%2Fa/renewal-offers/offer%2F1/resend",
      "GET /v1/seasons/sea%2Fa/reports/sales", "GET /v1/seasons/sea%2Fa/reports/seats",
      "GET /v1/seasons/sea%2Fa/reports/holders.csv?q=ann&status=renewal",
      "GET /v1/seasons/sea%2Fa/reports/orders.csv", "GET /v1/seasons/sea%2Fa/seat-counts",
      "POST /v1/seasons/sea%2Fa/performances/ev%2F3/refunds", "GET /v1/seasons/sea%2Fa/jobs",
      "GET /v1/seasons/sea%2Fa/jobs/job%2F1",
      "GET /v1/seasons/sea%2Fa/renewal-offers/offer%2F1/quote",
      "POST /v1/seasons/sea%2Fa/renewal-offers/offer%2F1/intent",
      "POST /v1/seasons/sea%2Fa/renewal-offers/offer%2F1/checkout"
    ]
    actual = transport.calls.map do |call|
      "#{call.http_method} #{call.url.delete_prefix("https://api.seatlayer.io")}"
    end
    expect(actual).to eq(expected)
    expect(transport.calls[26].body).to be_nil

    expect(transport.calls.drop(48).map { |call| call.body && JSON.parse(call.body) }).to eq(
      [
        { "sourceSeasonId" => "sea_old", "successorPlanActivationId" => "pa_2", "dryRun" => true },
        nil,
        { "titlePattern" => "Hamlet", "timezone" => "Europe/London", "repeat" => "weekly",
          "count" => 3, "venue" => nil },
        { "eventKeys" => ["ev_3"] }, nil, { "name" => "Gold" }, nil, nil,
        { "planKey" => "plan/1", "quantity" => 2 }, nil,
        { "prices" => [{ "categoryKey" => "stalls", "unitPrice" => 9000 }], "currency" => "GBP" },
        nil, { "eventKey" => "ev/3" }, nil, { "force" => true },
        { "actionId" => "ret_1", "bookingRef" => "order_1", "planActivationId" => "pa_1",
          "labels" => ["A-1"], "source" => { "bookingActionId" => "book_1" } },
        { "actionId" => "rec_1", "returnActionId" => "ret_1", "bookingRef" => "order_1",
          "planActivationId" => "pa_1", "labels" => ["A-1"], "source" => { "renewalOfferId" => "o_1" } },
        nil, { "amountMinor" => 500 },
        { "reason" => "other", "note" => "Duplicate", "notifyBuyer" => false },
        { "actionId" => "date_1" }, { "email" => "ann@example.com" }, nil, nil,
        { "email" => "ann@example.com", "name" => nil }, { "offerIds" => ["offer/1"] },
        nil, nil, nil, nil, nil, nil,
        { "amount" => "per_date", "reason" => "Storm" }, nil, nil,
        nil, nil,
        { "returnUrl" => "https://tickets.example/renewed", "buyerEmail" => "ana@example.com",
          "buyerName" => "Ana Silva", "provider" => "stripe" }
      ]
    )

    replay_indexes = [2, 4, 5, 10, 18, 27, 29, 38, 48, 50, 51, 52, 53, 54, 55, 56, 58, 60, 61, 62,
                      66, 67, 68, 80, 85]
    transport.calls.each_with_index do |call, index|
      if replay_indexes.include?(index)
        expect(call.headers).to have_key("Idempotency-Key")
      else
        expect(call.headers).not_to have_key("Idempotency-Key")
      end
    end
    expect(transport.calls[80].headers["Idempotency-Key"]).to eq("refund-date-1")
    expect(transport.calls[85].headers["Idempotency-Key"]).to eq("renew-1")
  end

  it "sends the decline reason, and retries a renewal checkout with one key but not the intent" do
    responses = [
      { status: 200 }, { status: 200 },
      { status: 429, headers: { "Retry-After" => "0" } }, { status: 201, body: '{"orderId":"ord_1"}' },
      { status: 429, headers: { "Retry-After" => "0" } }
    ]
    client, transport = build_client(responses)
    seasons = client.seasons

    seasons.decline_season_renewal_offer("sea/a", "offer/1", reason: "Moving away")
    seasons.decline_season_renewal_offer("sea_1", "offer_1")
    started = seasons.create_season_renewal_checkout("sea_1", "offer_1",
                                                     return_url: "https://tickets.example/r")
    expect { seasons.create_season_renewal_intent("sea_1", "offer_1") }
      .to raise_error(SeatLayer::RateLimitError)

    expect(started).to eq({ "orderId" => "ord_1" })
    checkout = ["POST /v1/seasons/sea_1/renewal-offers/offer_1/checkout",
                { "returnUrl" => "https://tickets.example/r" }, true]
    expect(transport.calls.map { |call| request_summary(call) }).to eq(
      [
        ["POST /v1/seasons/sea%2Fa/renewal-offers/offer%2F1/decline", { "reason" => "Moving away" }, false],
        ["POST /v1/seasons/sea_1/renewal-offers/offer_1/decline", {}, false],
        checkout, checkout,
        ["POST /v1/seasons/sea_1/renewal-offers/offer_1/intent", nil, false]
      ]
    )
    expect(transport.calls[2].headers["Idempotency-Key"])
      .to eq(transport.calls[3].headers["Idempotency-Key"])
  end

  it "sends price types, sale settings, holder contacts and date cancels on the wire" do
    client, transport = build_client(Array.new(6) { { status: 200 } })
    seasons = client.seasons

    seasons.replace_season_package_prices(
      "sea_1", "plan_1", prices: [{ "categoryKey" => "stalls", "unitPrice" => 18_000 },
                                  { "categoryKey" => "stalls", "priceTypeKey" => "child",
                                    "unitPrice" => 9_000 }]
    )
    seasons.update_season("sea_1", expected_revision: 3, checkout_mode: "seatlayer",
                                   transfer_cutoff_hours: 24, return_cutoff_hours: nil)
    seasons.update_season("sea_1", expected_revision: 4, name: "Renamed")
    seasons.create_season_holder_import(
      "sea_1", successor_plan_activation_id: "pa_1",
               rows: [{ "rowId" => "r1", "holderRef" => "h1", "priorPlanActivationId" => "pa_0",
                        "priorContractRef" => "c1", "labels" => ["A-1"],
                        "holderEmail" => "ana@example.com", "holderName" => "Ana Silva" }]
    )
    seasons.create_season_amendment("sea_1", event_key: "ev_night_3", kind: "cancel", refund: "per_date",
                                             reason: "Storm", idempotency_key: "night-3-storm")
    seasons.create_season_amendment("sea_1", event_key: "ev_1", kind: "postpone")

    expect(transport.calls.map { |call| JSON.parse(call.body) }).to eq(
      [
        { "prices" => [{ "categoryKey" => "stalls", "unitPrice" => 18_000 },
                       { "categoryKey" => "stalls", "priceTypeKey" => "child", "unitPrice" => 9_000 }] },
        { "expectedRevision" => 3, "checkoutMode" => "seatlayer", "transferCutoffHours" => 24,
          "returnCutoffHours" => nil },
        { "expectedRevision" => 4, "name" => "Renamed" },
        { "successorPlanActivationId" => "pa_1",
          "rows" => [{ "rowId" => "r1", "holderRef" => "h1", "priorPlanActivationId" => "pa_0",
                       "priorContractRef" => "c1", "labels" => ["A-1"],
                       "holderEmail" => "ana@example.com", "holderName" => "Ana Silva" }] },
        { "eventKey" => "ev_night_3", "kind" => "cancel", "refund" => "per_date", "reason" => "Storm" },
        { "eventKey" => "ev_1", "kind" => "postpone" }
      ]
    )
    expect(transport.calls[1].body).to include('"returnCutoffHours":null')
    expect(transport.calls[4].headers["Idempotency-Key"]).to eq("night-3-storm")
  end

  it "retries a bulk refund of a date with one key" do
    client, transport = build_client([{ status: 429, headers: { "Retry-After" => "0" } },
                                      { status: 202, body: '{"job":{"jobId":"sbj_1"}}' }])

    result = client.seasons.refund_season_performance("sea_1", "ev_1", amount: "full")

    expect(result).to eq({ "job" => { "jobId" => "sbj_1" } })
    expect(transport.calls.length).to eq(2)
    expect(transport.calls.map { |call| JSON.parse(call.body) }).to all(eq({ "amount" => "full" }))
    expect(transport.calls[0].headers["Idempotency-Key"])
      .to eq(transport.calls[1].headers["Idempotency-Key"])
  end

  it "returns the Season CSV exports as raw text" do
    csv = "holderRef,email\nh_1,ann@example.com\n"
    responses = [
      { status: 200, body: csv, headers: { "Content-Type" => "text/csv" } },
      { status: 200, body: "orderId\n", headers: { "Content-Type" => "text/csv" } }
    ]
    client, transport = build_client(responses)

    expect(client.seasons.export_season_holders_csv("sea/a", search: "ann")).to eq(csv)
    expect(client.seasons.export_season_orders_csv("sea/a")).to eq("orderId\n")
    expect(transport.calls[0].url).to end_with("/v1/seasons/sea%2Fa/reports/holders.csv?q=ann")
    expect(transport.calls.map { |call| call.headers["Accept"] }).to eq(%w[text/csv text/csv])
  end

  it "returns an empty result when a draft package is deleted (204)" do
    client, transport = build_client([{ status: 204, body: "" }])

    expect(client.seasons.delete_season_plan("sea/a", "plan/1")).to eq({})
    expect(transport.calls[0].headers).to have_key("Idempotency-Key")
  end

  it "retries header-replay Season writes with one key and never retries unsupported ones" do
    responses = [
      { status: 429, headers: { "Retry-After" => "0" } }, { status: 201 },
      { status: 500, body: '{"code":"internal"}' }, { status: 500, body: '{"code":"internal"}' }
    ]
    client, transport = build_client(responses)

    client.seasons.create_season_performances(
      "sea/a", title_pattern: "Hamlet", timezone: "UTC", repeat: "none"
    )
    expect(transport.calls.length).to eq(2)
    expect(transport.calls[0].headers["Idempotency-Key"])
      .to eq(transport.calls[1].headers["Idempotency-Key"])

    expect { client.seasons.resend_season_renewal_offer("sea/a", "offer/1") }
      .to raise_error(SeatLayer::APIError)
    expect { client.seasons.rotate_season_renewal_offer_link("sea/a", "offer/1") }
      .to raise_error(SeatLayer::APIError)
    expect(transport.calls.length).to eq(4)
  end
end
