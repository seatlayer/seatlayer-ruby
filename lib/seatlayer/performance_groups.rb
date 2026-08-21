# frozen_string_literal: true

module SeatLayer
  # Fixed multi-performance runs. This is a secret-key surface: mint the
  # browser token here, then give that token (never this client) to the
  # PerformanceGroupPicker in the browser SDK.
  class PerformanceGroups < Resource
    # One page of fixed runs.
    def list(workspace_id: nil, external_ref: nil, state: nil, limit: nil, cursor: nil)
      @client.get("/v1/performance-groups", compact({ "workspaceId" => workspace_id,
                                                      "externalRef" => external_ref,
                                                      "state" => state, "limit" => limit,
                                                      "cursor" => cursor }))
    end

    # Create a draft from two to eight compatible assigned-seat events. The
    # server validates compatibility and exactly replays a request with the
    # same idempotency key.
    def create(name:, event_keys:, external_ref: UNSET, idempotency_key: nil)
      body = { "name" => name, "eventKeys" => event_keys }
      body.merge!(supplied({ "externalRef" => external_ref }))
      @client.post("/v1/performance-groups", body, idempotency_key: idempotency_key,
                                                   retry_policy: :header_replay)
    end

    def retrieve(performance_group_key)
      @client.get(path(performance_group_key))
    end

    # Only a draft can be deleted. Activated runs retain their audit identity.
    def delete(performance_group_key)
      @client.delete(path(performance_group_key))
    end

    # Starts lifecycle coordination. When its response contains a non-terminal
    # lifecycle operation, poll +retrieve_lifecycle+ until it completes.
    def activate(performance_group_key, expected_revision:)
      @client.post(path(performance_group_key, "/activate"),
                   { "expectedRevision" => expected_revision })
    end

    # Stops new group sales. Poll +retrieve_lifecycle+ while the close remains pending.
    def close(performance_group_key, expected_revision:)
      @client.post(path(performance_group_key, "/close"),
                   { "expectedRevision" => expected_revision })
    end

    def retrieve_lifecycle(performance_group_key, operation_id)
      @client.get(path(performance_group_key, "/lifecycle/#{encode(operation_id)}"))
    end

    # Reveals a one-time, origin-bound browser bearer. It intentionally remains
    # single-attempt: a retry could create a token whose only reveal is lost.
    def create_buyer_access_session(performance_group_key, allowed_origin:, include_public:,
                                    channel_ids_by_event: nil, expires_in_seconds: nil,
                                    max_quantity: UNSET, buyer_ref: UNSET, partner_ref: UNSET)
      body = compact({ "allowedOrigin" => allowed_origin, "includePublic" => include_public,
                       "channelIdsByEvent" => channel_ids_by_event,
                       "expiresInSeconds" => expires_in_seconds })
      body.merge!(supplied({ "maxQuantity" => max_quantity, "buyerRef" => buyer_ref,
                             "partnerRef" => partner_ref }))
      @client.post(path(performance_group_key, "/buyer-access-sessions"), body)
    end

    # Token records only: the bearer value is never returned again.
    def list_buyer_access_sessions(performance_group_key, limit: nil)
      @client.get(path(performance_group_key, "/buyer-access-sessions"), { "limit" => limit })
    end

    def revoke_buyer_access_session(performance_group_key, session_id)
      @client.delete(path(performance_group_key, "/buyer-access-sessions/#{encode(session_id)}"))
    end

    # Read the trusted server projection before charging; do not price from
    # client input or the picker state.
    def retrieve_hold(performance_group_key, operation_id)
      @client.get(path(performance_group_key, "/holds/#{encode(operation_id)}"))
    end

    # Confirm external payment for a committed hold. Keep both identifiers
    # stable, and poll +retrieve_booking+ if the response is +book_pending+.
    def book_hold(performance_group_key, operation_id, book_action_id:, booking_ref:)
      @client.post(path(performance_group_key, "/holds/#{encode(operation_id)}/book"),
                   { "bookActionId" => book_action_id,
                     "bookingRef" => normalise_booking_ref(booking_ref) })
    end

    def retrieve_booking(performance_group_key, action_id)
      @client.get(path(performance_group_key, "/bookings/#{encode(action_id)}"))
    end

    private

    def path(performance_group_key, suffix = "")
      "/v1/performance-groups/#{encode(performance_group_key)}#{suffix}"
    end

    def normalise_booking_ref(booking_ref)
      value = booking_ref&.strip
      return value unless value.nil? || value.empty?

      raise ArgumentError, "booking_ref is required and must be a non-empty stable reference"
    end
  end
end
