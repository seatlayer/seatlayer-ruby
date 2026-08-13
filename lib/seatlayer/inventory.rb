# frozen_string_literal: true

module SeatLayer
  # Holds, booking, blocking and availability.
  #
  # Two complete flows, both first-class:
  #
  #   browser holds → retrieve_hold for authoritative pricing → charge → book(hold_id:)
  #   backend books labels directly — box office, phone sales, comps
  #
  # Never price from what the browser tells you. +retrieve_hold+ is the
  # authoritative answer, which is why it is a separate call.
  class Inventory < Resource
    # Explicit keywords keep allocation authority visible at every sale call.
    # rubocop:disable Metrics/ParameterLists
    def hold(event_key, labels: nil, selections: nil, ttl_ms: nil,
             replace_hold_id: nil, channel_ids: nil, ignore_channel_restrictions: nil,
             reason: nil, idempotency_key: nil)
      body = compact({ "labels" => labels, "selections" => selections,
                       "ttlMs" => ttl_ms, "replaceHoldId" => replace_hold_id,
                       "channelIds" => channel_ids,
                       "ignoreChannelRestrictions" => ignore_channel_restrictions,
                       "reason" => reason })
      @client.post(path(event_key, "/hold"), body, idempotency_key: idempotency_key)
    end

    # Ask us to pick the best free objects and hold them.
    #
    # The picker is the one the buyer widget uses, so a phone order and a web
    # order get the same answer for the same inventory. A +qty+ above the server
    # cap is clamped, not rejected.
    def hold_best_available(event_key, qty:, category_key: nil, zone_id: nil,
                            ttl_ms: nil, channel_ids: nil, ignore_channel_restrictions: nil,
                            reason: nil, idempotency_key: nil)
      body = compact({ "qty" => qty, "categoryKey" => category_key,
                       "zoneId" => zone_id, "ttlMs" => ttl_ms,
                       "channelIds" => channel_ids,
                       "ignoreChannelRestrictions" => ignore_channel_restrictions,
                       "reason" => reason })
      @client.post(path(event_key, "/best-available"), body, idempotency_key: idempotency_key)
    end

    # Pick and book in one call — the box-office shape.
    #
    # Prefer this over hold-then-book when payment is already taken: a failure
    # between two calls would strand inventory until the TTL expired.
    def book_best_available(event_key, qty:, booking_ref:, category_key: nil,
                            zone_id: nil, channel_ids: nil, ignore_channel_restrictions: nil,
                            reason: nil, idempotency_key: nil)
      body = compact({ "qty" => qty, "bookingRef" => normalise_booking_ref(booking_ref),
                       "categoryKey" => category_key, "zoneId" => zone_id,
                       "channelIds" => channel_ids,
                       "ignoreChannelRestrictions" => ignore_channel_restrictions,
                       "reason" => reason })
      @client.post(path(event_key, "/best-available-book"), body, idempotency_key: idempotency_key)
    end
    # rubocop:enable Metrics/ParameterLists

    # Push an active hold's expiry out by a fresh window before it lapses.
    #
    # Use this rather than release-and-re-hold when an order takes longer than
    # the checkout window — invoiced sales, a phone order on hold. Releasing
    # first hands the seats to whoever is racing for them in between. A hold that
    # is gone, expired, or at its renewal cap answers 409 +cannot_extend+.
    def extend_hold(event_key, hold_id, ttl_ms: nil, channel_ids: nil,
                    ignore_channel_restrictions: nil, reason: nil)
      body = compact({ "holdId" => hold_id, "ttlMs" => ttl_ms,
                       "channelIds" => channel_ids,
                       "ignoreChannelRestrictions" => ignore_channel_restrictions,
                       "reason" => reason })
      @client.post(path(event_key, "/extend"), body)
    end

    # Authoritative items and prices. Charge from this, not the browser.
    def retrieve_hold(event_key, hold_id)
      @client.get(path(event_key, "/holds/#{encode(hold_id)}"))
    end

    def release(event_key, labels:, hold_id:)
      @client.post(path(event_key, "/release"), { "labels" => labels, "holdId" => hold_id })
    end

    def book(event_key, hold_id: nil, labels: nil, booking_ref: nil, channel_ids: nil,
             ignore_channel_restrictions: nil, reason: nil, idempotency_key: nil)
      body = compact({ "holdId" => hold_id, "labels" => labels,
                       "bookingRef" => normalise_booking_ref(booking_ref),
                       "channelIds" => channel_ids,
                       "ignoreChannelRestrictions" => ignore_channel_restrictions,
                       "reason" => reason })
      @client.post(path(event_key, "/book"), body, idempotency_key: idempotency_key)
    end

    def box_office_book(event_key, labels:, booking_ref:, idempotency_key: nil)
      @client.post(path(event_key, "/box-book"),
                   { "labels" => labels, "bookingRef" => normalise_booking_ref(booking_ref) },
                   idempotency_key: idempotency_key)
    end

    # Reverse a booking. Requires a key with cancel authority.
    def unbook(event_key, labels:, booking_ref:)
      @client.post(path(event_key, "/unbook"),
                   { "labels" => labels, "bookingRef" => normalise_booking_ref(booking_ref) })
    end

    # Hold inventory back from sale (house seats, production holds).
    def block(event_key, labels:, release_at: nil)
      @client.post(path(event_key, "/block"),
                   compact({ "labels" => labels, "releaseAt" => release_at }))
    end

    def unblock(event_key, labels:)
      @client.post(path(event_key, "/unblock"), { "labels" => labels })
    end

    def unblock_all(event_key)
      @client.post(path(event_key, "/unblock-all"))
    end

    def retrieve_availability(event_key)
      @client.get(path(event_key, "/availability"))
    end

    def update_availability(event_key, fields)
      @client.post(path(event_key, "/availability"), fields)
    end

    # One page of inventory booking lifecycles, newest first.
    def list_bookings(event_key, query: nil, state: nil, limit: nil, cursor: nil)
      @client.get(path(event_key, "/bookings"),
                  compact({ "q" => query, "state" => state, "limit" => limit, "cursor" => cursor }))
    end

    def retrieve_booking(event_key, booking_ref)
      @client.get(path(event_key, "/bookings/#{encode(normalise_booking_ref(booking_ref))}"))
    end

    private

    def path(event_key, suffix)
      "/v1/events/#{encode(event_key)}#{suffix}"
    end

    def normalise_booking_ref(booking_ref)
      value = booking_ref&.strip
      return value unless value.nil? || value.empty?

      raise ArgumentError, "booking_ref is required and must be a non-empty stable reference"
    end
  end

  # Short-lived, origin-bound browser tokens.
  #
  # The governing rule: the SDK mints tokens, widgets consume them. Your secret
  # key never reaches a browser.
  class Sessions < Resource
    CAPABILITIES = [
      "event:view", "event:block", "event:cancel", "event:reports",
      "event:channels:view", "event:channels:manage", "event:orders:read",
      "event:refund", "event:tickets:send", "event:door:view",
      "event:door:checkin", "event:boxoffice"
    ].freeze

    # Mint a manage-session token for the control room.
    #
    # The raw API defaults an omitted list to view-only (+event:view+). This SDK
    # still requires an explicit set so browser authority is visible at each call.
    def create_manage_session(event_key, allowed_origin:, capabilities:, expires_in_seconds: nil,
                              workspace_id: nil)
      if capabilities.nil? || capabilities.empty?
        raise ArgumentError,
              'capabilities is required: pass the smallest set the page needs, e.g. ["event:view"].'
      end
      unknown = capabilities - CAPABILITIES
      raise ArgumentError, "unsupported manage capabilities: #{unknown.join(", ")}" unless unknown.empty?

      body = compact({ "allowedOrigin" => allowed_origin, "capabilities" => capabilities,
                       "expiresInSeconds" => expires_in_seconds,
                       "workspaceId" => workspace_id })
      @client.post("/v1/events/#{encode(event_key)}/manage-sessions", body)
    end

    def revoke_manage_session(event_key, session_id)
      @client.delete("/v1/events/#{encode(event_key)}/manage-sessions/#{encode(session_id)}")
    end

    # Mint a designer token so an organiser can edit a chart inside your own UI.
    # Requires a chart id that already exists — create or copy one first.
    # Explicit keywords keep each security and feature-policy boundary visible.
    # rubocop:disable Metrics/ParameterLists
    def create_designer_session(workspace_id:, chart_id:, allowed_origin:,
                                authority: nil, can_publish: nil, mode: nil,
                                safe_mode_options: nil, features: nil, expires_in_seconds: nil)
      body = compact({ "workspaceId" => workspace_id, "chartId" => chart_id,
                       "allowedOrigin" => allowed_origin, "authority" => authority,
                       "canPublish" => can_publish, "mode" => mode,
                       "safeModeOptions" => safe_mode_options, "features" => features,
                       "expiresInSeconds" => expires_in_seconds })
      @client.post("/v1/designer/sessions", body)
    end
    # rubocop:enable Metrics/ParameterLists

    def revoke_designer_session(session_id)
      @client.delete("/v1/designer/sessions/#{encode(session_id)}")
    end
  end

  # Manage webhook subscriptions. To VERIFY a delivery, see SeatLayer::Webhook.
  class Webhooks < Resource
    EVENT_NAMES = [
      "seat.booked", "seat.released", "seat.blocked", "hold.expired",
      "hold.created", "hold.extended", "event.created", "event.soldout"
    ].freeze

    def list
      @client.get("/v1/webhooks")
    end

    def create(url:, events:)
      validate_events!(events)
      @client.post("/v1/webhooks", { "url" => url, "events" => events })
    end

    def update(webhook_id, url: nil, events: nil, disabled: nil)
      validate_events!(events) unless events.nil?
      fields = compact({ "url" => url, "events" => events, "disabled" => disabled })
      @client.patch("/v1/webhooks/#{encode(webhook_id)}", fields)
    end

    def delete(webhook_id)
      @client.delete("/v1/webhooks/#{encode(webhook_id)}")
    end

    def list_deliveries(webhook_id, limit: nil, status: nil, before: nil)
      raise ArgumentError, "status must be ok or failed" unless status.nil? || %w[ok failed].include?(status)

      query = compact({ "limit" => limit, "status" => status, "before" => before })
      @client.get("/v1/webhooks/#{encode(webhook_id)}/deliveries", query)
    end

    private

    def validate_events!(events)
      unknown = Array(events) - EVENT_NAMES
      return if !Array(events).empty? && unknown.empty?

      raise ArgumentError, "events must contain only supported SeatLayer webhook event names"
    end
  end

  # Workspaces isolate one tenant's charts and events from another's.
  class Workspaces < Resource
    def list
      @client.get("/v1/workspaces")
    end

    def create(name:, external_ref: UNSET, idempotency_key: nil)
      body = { "name" => name }
      body.merge!(supplied({ "externalRef" => external_ref }))
      @client.post(
        "/v1/workspaces", body, idempotency_key: idempotency_key, retry_policy: :header_replay
      )
    end

    def retrieve(workspace_id)
      @client.get("/v1/workspaces/#{encode(workspace_id)}")
    end

    # Rename, re-reference, or disable a workspace.
    #
    # The organisation's default workspace cannot be disabled — the API answers
    # 409 +default_workspace_required+. Promote another one first.
    def update(workspace_id, fields)
      @client.patch("/v1/workspaces/#{encode(workspace_id)}", fields)
    end
  end
end
