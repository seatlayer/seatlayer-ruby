# frozen_string_literal: true

module SeatLayer
  # Fixed Renewable Season organizer operations for trusted backends.
  #
  # Browser selection belongs in the distinct SeasonPicker. Give it only the
  # show-once scoped token returned by +create_season_buyer_access_session+.
  class Seasons < Resource
    def list_seasons(workspace_id: nil, structure_state: nil, limit: nil, cursor: nil)
      @client.get("/v1/seasons", compact({ "workspaceId" => workspace_id,
                                           "structureState" => structure_state,
                                           "limit" => limit, "cursor" => cursor }))
    end

    # Read-only compatibility preflight.
    def validate_season(event_keys: nil, source_performance_group_keys: nil)
      @client.post("/v1/seasons/validate",
                   selection(event_keys, source_performance_group_keys))
    end

    def create_season(name:, event_keys: nil, source_performance_group_keys: nil,
                      edition: UNSET, idempotency_key: nil)
      body = selection(event_keys, source_performance_group_keys).merge("name" => name)
      body.merge!(supplied({ "edition" => edition }))
      @client.post("/v1/seasons", body, idempotency_key: idempotency_key,
                                        retry_policy: :header_replay)
    end

    def retrieve_season(season_key)
      @client.get(path(season_key))
    end

    def update_season(season_key, expected_revision:, name: nil, edition: UNSET,
                      idempotency_key: nil)
      body = compact({ "expectedRevision" => expected_revision, "name" => name })
      body.merge!(supplied({ "edition" => edition }))
      @client.mutation_with_header_replay(
        "PATCH", path(season_key), body, idempotency_key: idempotency_key
      )
    end

    def delete_season(season_key, idempotency_key: nil)
      @client.mutation_with_header_replay(
        "DELETE", path(season_key), idempotency_key: idempotency_key
      )
    end

    def activate_season(season_key, expected_revision:)
      lifecycle(season_key, "activate", expected_revision)
    end

    def close_season(season_key, expected_revision:)
      lifecycle(season_key, "close", expected_revision)
    end

    def archive_season(season_key, expected_revision:)
      lifecycle(season_key, "archive", expected_revision)
    end

    def retrieve_season_lifecycle(season_key, operation_id)
      @client.get(path(season_key, "/lifecycle/#{encode(operation_id)}"))
    end

    def create_season_plan(season_key, name:, event_keys: nil,
                           source_performance_group_keys: nil, idempotency_key: nil)
      body = selection(event_keys, source_performance_group_keys).merge("name" => name)
      @client.post(path(season_key, "/plans"), body, idempotency_key: idempotency_key,
                                                     retry_policy: :header_replay)
    end

    def retrieve_season_plan(season_key, plan_key)
      @client.get(path(season_key, "/plans/#{encode(plan_key)}"))
    end

    def publish_season_plan(season_key, plan_key, expected_revision:)
      @client.post(path(season_key, "/plans/#{encode(plan_key)}/publish"),
                   { "expectedRevision" => expected_revision })
    end

    def supersede_season_plan(season_key, plan_key, expected_revision:)
      @client.post(path(season_key, "/plans/#{encode(plan_key)}/supersede"),
                   { "expectedRevision" => expected_revision })
    end

    def open_season_sales(season_key, expected_revision:)
      sales(season_key, "open", expected_revision)
    end

    def pause_season_sales(season_key, expected_revision:)
      sales(season_key, "pause", expected_revision)
    end

    def resume_season_sales(season_key, expected_revision:)
      sales(season_key, "resume", expected_revision)
    end

    def end_season_sales(season_key, expected_revision:)
      sales(season_key, "end", expected_revision)
    end

    def duplicate_season_to_live(season_key, event_keys:, name: nil, idempotency_key: nil)
      @client.post(path(season_key, "/duplicate-to-live"),
                   compact({ "eventKeys" => event_keys, "name" => name }),
                   idempotency_key: idempotency_key, retry_policy: :header_replay)
    end

    # Reveal one show-once browser bearer. This call is deliberately single-attempt.
    def create_season_buyer_access_session(season_key, allowed_origin:, include_public:,
                                           expires_in_seconds: nil, max_quantity: UNSET,
                                           buyer_ref: UNSET)
      body = compact({ "allowedOrigin" => allowed_origin, "includePublic" => include_public,
                       "expiresInSeconds" => expires_in_seconds })
      body.merge!(supplied({ "maxQuantity" => max_quantity, "buyerRef" => buyer_ref }))
      @client.post(path(season_key, "/buyer-access-sessions"), body)
    end

    def list_season_buyer_access_sessions(season_key, limit: nil)
      @client.get(path(season_key, "/buyer-access-sessions"), compact({ "limit" => limit }))
    end

    def revoke_season_buyer_access_session(season_key, session_id)
      @client.delete(path(season_key, "/buyer-access-sessions/#{encode(session_id)}"))
    end

    def retrieve_season_hold(season_key, operation_id)
      @client.get(path(season_key, "/holds/#{encode(operation_id)}"))
    end

    def book_season_hold(season_key, operation_id, book_action_id:, booking_ref:)
      @client.post(path(season_key, "/holds/#{encode(operation_id)}/book"),
                   { "bookActionId" => book_action_id, "bookingRef" => booking_ref })
    end

    def retrieve_season_booking(season_key, action_id)
      @client.get(path(season_key, "/bookings/#{encode(action_id)}"))
    end

    def cancel_season_booking(season_key, action_id, cancel_action_id:, booking_ref:,
                              plan_activation_id:, right_disposition:)
      @client.post(path(season_key, "/bookings/#{encode(action_id)}/cancel"),
                   { "cancelActionId" => cancel_action_id, "bookingRef" => booking_ref,
                     "planActivationId" => plan_activation_id,
                     "rightDisposition" => right_disposition })
    end

    def validate_season_buyer_rehearsal(season_key)
      @client.post(path(season_key, "/buyer-rehearsals/validate"))
    end

    def create_season_holder_import(season_key, successor_plan_activation_id:, rows:,
                                    dry_run: UNSET, idempotency_key: nil)
      body = { "successorPlanActivationId" => successor_plan_activation_id, "rows" => rows }
      body.merge!(supplied({ "dryRun" => dry_run }))
      @client.post(path(season_key, "/imports"), body, idempotency_key: idempotency_key,
                                                       retry_policy: :header_replay)
    end

    def retrieve_season_holder_import(season_key, import_id)
      @client.get(path(season_key, "/imports/#{encode(import_id)}"))
    end

    def create_season_renewal_offers(season_key, deadline_at:,
                                     successor_plan_activation_id: nil, contract_ids: nil,
                                     idempotency_key: nil)
      body = compact({ "successorPlanActivationId" => successor_plan_activation_id,
                       "deadlineAt" => deadline_at, "contractIds" => contract_ids })
      @client.post(path(season_key, "/renewal-offers"), body,
                   idempotency_key: idempotency_key, retry_policy: :header_replay)
    end

    def list_season_renewal_offers(season_key)
      @client.get(path(season_key, "/renewal-offers"))
    end

    def retrieve_season_renewal_offer(season_key, offer_id)
      @client.get(path(season_key, "/renewal-offers/#{encode(offer_id)}"))
    end

    def extend_season_renewal_offer(season_key, offer_id, deadline_at:)
      @client.post(path(season_key, "/renewal-offers/#{encode(offer_id)}/extend"),
                   { "deadlineAt" => deadline_at })
    end

    def inspect_season_renewal_offer(season_key, offer_id)
      @client.get(path(season_key, "/renewal-offers/#{encode(offer_id)}/inspect"))
    end

    def commit_season_renewal_offer(season_key, offer_id, commit_action_id:, order_ref:,
                                    booking_ref:, plan_activation_id:)
      @client.post(path(season_key, "/renewal-offers/#{encode(offer_id)}/commit"),
                   { "commitActionId" => commit_action_id, "orderRef" => order_ref,
                     "bookingRef" => booking_ref, "planActivationId" => plan_activation_id })
    end

    def decline_season_renewal_offer(season_key, offer_id)
      @client.post(path(season_key, "/renewal-offers/#{encode(offer_id)}/decline"), {})
    end

    def release_season_renewal_offer(season_key, offer_id)
      @client.post(path(season_key, "/renewal-offers/#{encode(offer_id)}/release"), {})
    end

    def list_season_occurrences(season_key)
      @client.get(path(season_key, "/occurrences"))
    end

    def create_season_amendment(season_key, event_key:, kind:, starts_at: nil, name: nil,
                                idempotency_key: nil)
      @client.post(path(season_key, "/amendments"),
                   compact({ "eventKey" => event_key, "kind" => kind,
                             "startsAt" => starts_at, "name" => name }),
                   idempotency_key: idempotency_key, retry_policy: :header_replay)
    end

    def list_season_amendments(season_key)
      @client.get(path(season_key, "/amendments"))
    end

    def retrieve_season_amendment(season_key, amendment_id)
      @client.get(path(season_key, "/amendments/#{encode(amendment_id)}"))
    end

    def retrieve_season_report(season_key)
      @client.get(path(season_key, "/reports"))
    end

    def list_season_operations(season_key)
      @client.get(path(season_key, "/operations"))
    end

    def retrieve_season_support_lookup(season_key, booking_ref: nil, holder_ref: nil)
      @client.get(path(season_key, "/support-lookups"),
                  compact({ "bookingRef" => booking_ref, "holderRef" => holder_ref }))
    end

    def list_season_outbox(season_key)
      @client.get(path(season_key, "/outbox"))
    end

    def replay_season_outbox(season_key, occurrence_id)
      @client.post(path(season_key, "/outbox/#{encode(occurrence_id)}/replay"), {})
    end

    def list_season_audit(season_key)
      @client.get(path(season_key, "/audit"))
    end

    def export_season_support_snapshot(season_key)
      @client.get(path(season_key, "/export"))
    end

    private

    def path(season_key, suffix = "")
      "/v1/seasons/#{encode(season_key)}#{suffix}"
    end

    def selection(event_keys, source_performance_group_keys)
      compact({ "eventKeys" => event_keys,
                "sourcePerformanceGroupKeys" => source_performance_group_keys })
    end

    def lifecycle(season_key, action, expected_revision)
      @client.post(path(season_key, "/#{action}"), { "expectedRevision" => expected_revision })
    end

    def sales(season_key, action, expected_revision)
      @client.post(path(season_key, "/sales/#{action}"),
                   { "expectedRevision" => expected_revision })
    end
  end
end
