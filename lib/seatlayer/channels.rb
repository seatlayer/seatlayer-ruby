# frozen_string_literal: true

module SeatLayer
  # Private allocations, reporting, and origin-bound buyer access.
  class Channels < Resource
    def list_channels(event_key, include_archived: false)
      query = include_archived ? { "includeArchived" => "1" } : nil
      @client.get(path(event_key), query)
    end

    def create_channel(event_key, name:, color: nil, marker: nil, external_ref: nil,
                       access_intent: nil, reason: nil, idempotency_key: nil)
      body = compact({ "name" => name, "color" => color, "marker" => marker,
                       "externalRef" => external_ref, "accessIntent" => access_intent,
                       "reason" => reason })
      @client.post(path(event_key), body, idempotency_key: idempotency_key)
    end

    def update_channel(event_key, channel_id, name: nil, access_intent: nil,
                       acknowledge_live_access: nil, reason: nil)
      body = compact({ "name" => name, "accessIntent" => access_intent,
                       "acknowledgeLiveAccess" => acknowledge_live_access, "reason" => reason })
      @client.patch(path(event_key, "/#{encode(channel_id)}"), body)
    end

    def update_assignments(event_key, labels:, assignment_version:, target_channel_id: nil,
                           reason: nil, idempotency_key: nil)
      body = compact({ "targetChannelId" => target_channel_id, "labels" => labels,
                       "assignmentVersion" => assignment_version, "reason" => reason })
      body["targetChannelId"] = nil if target_channel_id.nil?
      @client.post(path(event_key, "/assignments"), body, idempotency_key: idempotency_key)
    end

    def list_allocation(event_key, after_label: nil, limit: nil)
      @client.get(path(event_key, "/allocation"), compact({ "afterLabel" => after_label, "limit" => limit }))
    end

    def retrieve_access_preview(event_key, channel_ids: nil, include_public: nil)
      include_public_value = if include_public.nil?
                               nil
                             else
                               include_public ? "1" : "0"
                             end
      query = compact({ "channelIds" => channel_ids&.join(","),
                        "includePublic" => include_public_value })
      @client.get(path(event_key, "/preview"), query)
    end

    def retrieve_report(event_key) = @client.get(path(event_key, "/report"))

    def pause(event_key, channel_id, reason: nil)
      @client.post(path(event_key, "/#{encode(channel_id)}/pause"), compact({ "reason" => reason }))
    end

    def unpause(event_key, channel_id, reason: nil)
      @client.post(path(event_key, "/#{encode(channel_id)}/unpause"), compact({ "reason" => reason }))
    end

    def archive(event_key, channel_id, destination:, reason: nil)
      body = compact({ "reason" => reason })
      body["destination"] = destination
      @client.post(path(event_key, "/#{encode(channel_id)}/archive"), body)
    end

    # Explicit keywords document each security boundary carried by the token.
    # rubocop:disable-next Metrics/ParameterLists
    def create_buyer_access_session(event_key, include_public:, allowed_origin:, channel_ids: nil,
                                    expires_in_seconds: nil, max_quantity: UNSET, buyer_ref: UNSET,
                                    partner_ref: UNSET, client_request_id: UNSET, idempotency_key: nil)
      body = compact({ "channelIds" => channel_ids, "includePublic" => include_public,
                       "allowedOrigin" => allowed_origin, "expiresInSeconds" => expires_in_seconds })
      body.merge!(supplied({ "maxQuantity" => max_quantity, "buyerRef" => buyer_ref,
                             "partnerRef" => partner_ref,
                             "clientRequestId" => client_request_id }))
      @client.post("/v1/events/#{encode(event_key)}/buyer-access-sessions", body,
                   idempotency_key: idempotency_key)
    end

    def list_buyer_access_sessions(event_key, limit: nil)
      @client.get("/v1/events/#{encode(event_key)}/buyer-access-sessions",
                  compact({ "limit" => limit }))
    end

    def revoke_buyer_access_session(event_key, session_id)
      @client.delete("/v1/events/#{encode(event_key)}/buyer-access-sessions/#{encode(session_id)}")
    end

    # The URL and capability in this response are revealed once. Persist them
    # immediately; this mutation is deliberately never retried automatically.
    # rubocop:disable-next Metrics/ParameterLists
    def create_access_link(event_key, channel_id, label: UNSET, expires_at: nil,
                           max_redemptions: nil, max_quantity: nil,
                           session_ttl_seconds: nil, include_public: nil, reason: nil,
                           idempotency_key: nil)
      body = compact({ "expiresAt" => expires_at, "maxRedemptions" => max_redemptions,
                       "maxQuantity" => max_quantity,
                       "sessionTtlSeconds" => session_ttl_seconds,
                       "includePublic" => include_public, "reason" => reason })
      body.merge!(supplied({ "label" => label }))
      @client.post(path(event_key, "/#{encode(channel_id)}/access-links"), body,
                   idempotency_key: idempotency_key)
    end

    # Status only: the API never returns a previously revealed capability.
    def list_access_links(event_key, channel_id)
      @client.get(path(event_key, "/#{encode(channel_id)}/access-links"))
    end

    def rotate_access_link(event_key, channel_id, link_id, end_active_sessions:, reason: nil)
      body = compact({ "endActiveSessions" => end_active_sessions, "reason" => reason })
      @client.post(
        path(event_key, "/#{encode(channel_id)}/access-links/#{encode(link_id)}/rotate"), body
      )
    end

    def revoke_access_link(event_key, channel_id, link_id, end_active_sessions: false, reason: nil)
      query = compact({ "endActiveSessions" => end_active_sessions ? "1" : nil,
                        "reason" => reason })
      @client.delete(
        path(event_key, "/#{encode(channel_id)}/access-links/#{encode(link_id)}"), query
      )
    end

    private

    def path(event_key, suffix = "") = "/v1/events/#{encode(event_key)}/channels#{suffix}"
  end
end
