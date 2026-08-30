# frozen_string_literal: true

RSpec.describe SeatLayer::Seasons do
  it "maps all 48 Season operations and their exact replay classes" do
    client, transport = build_client(Array.new(48) { { status: 200 } })
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
      "GET /v1/seasons/sea%2Fa/audit", "GET /v1/seasons/sea%2Fa/export"
    ]
    actual = transport.calls.map do |call|
      "#{call.http_method} #{call.url.delete_prefix("https://api.seatlayer.io")}"
    end
    expect(actual).to eq(expected)
    expect(transport.calls[26].body).to be_nil

    replay_indexes = [2, 4, 5, 10, 18, 27, 29, 38]
    transport.calls.each_with_index do |call, index|
      if replay_indexes.include?(index)
        expect(call.headers).to have_key("Idempotency-Key")
      else
        expect(call.headers).not_to have_key("Idempotency-Key")
      end
    end
  end
end
