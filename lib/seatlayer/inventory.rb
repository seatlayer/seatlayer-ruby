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
    def hold(event_key, labels: nil, selections: nil, ttl_ms: nil,
             replace_hold_id: nil, idempotency_key: nil)
      body = compact({ "labels" => labels, "selections" => selections,
                       "ttlMs" => ttl_ms, "replaceHoldId" => replace_hold_id })
      @client.post(path(event_key, "/hold"), body, idempotency_key: idempotency_key)
    end

    # Ask us to pick the best free objects and hold them.
    #
    # The picker is the one the buyer widget uses, so a phone order and a web
    # order get the same answer for the same inventory. A +qty+ above the server
    # cap is clamped, not rejected.
    def hold_best_available(event_key, qty:, category_key: nil, zone_id: nil,
                            ttl_ms: nil, idempotency_key: nil)
      body = compact({ "qty" => qty, "categoryKey" => category_key,
                       "zoneId" => zone_id, "ttlMs" => ttl_ms })
      @client.post(path(event_key, "/best-available"), body, idempotency_key: idempotency_key)
    end

    # Pick and book in one call — the box-office shape.
    #
    # Prefer this over hold-then-book when payment is already taken: a failure
    # between two calls would strand inventory until the TTL expired.
    def book_best_available(event_key, qty:, booking_ref:, category_key: nil,
                            zone_id: nil, idempotency_key: nil)
      body = compact({ "qty" => qty, "bookingRef" => booking_ref,
                       "categoryKey" => category_key, "zoneId" => zone_id })
      @client.post(path(event_key, "/best-available-book"), body, idempotency_key: idempotency_key)
    end

    # Push an active hold's expiry out by a fresh window before it lapses.
    #
    # Use this rather than release-and-re-hold when an order takes longer than
    # the checkout window — invoiced sales, a phone order on hold. Releasing
    # first hands the seats to whoever is racing for them in between. A hold that
    # is gone, expired, or at its renewal cap answers 409 +cannot_extend+.
    def extend_hold(event_key, hold_id, ttl_ms: nil)
      @client.post(path(event_key, "/extend"), compact({ "holdId" => hold_id, "ttlMs" => ttl_ms }))
    end

    # Authoritative items and prices. Charge from this, not the browser.
    def retrieve_hold(event_key, hold_id)
      @client.get(path(event_key, "/holds/#{encode(hold_id)}"))
    end

    def release(event_key, labels:, hold_id:)
      @client.post(path(event_key, "/release"), { "labels" => labels, "holdId" => hold_id })
    end

    def book(event_key, hold_id: nil, labels: nil, booking_ref: nil, idempotency_key: nil)
      body = compact({ "holdId" => hold_id, "labels" => labels, "bookingRef" => booking_ref })
      @client.post(path(event_key, "/book"), body, idempotency_key: idempotency_key)
    end

    def box_office_book(event_key, labels:, booking_ref:, idempotency_key: nil)
      @client.post(path(event_key, "/box-book"),
                   { "labels" => labels, "bookingRef" => booking_ref },
                   idempotency_key: idempotency_key)
    end

    # Reverse a booking. Requires a key with cancel authority.
    def unbook(event_key, labels:)
      @client.post(path(event_key, "/unbook"), { "labels" => labels })
    end

    # Hold inventory back from sale (house seats, production holds).
    def block(event_key, labels:)
      @client.post(path(event_key, "/block"), { "labels" => labels })
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

    private

    def path(event_key, suffix)
      "/v1/events/#{encode(event_key)}#{suffix}"
    end
  end

  # Short-lived, origin-bound browser tokens.
  #
  # The governing rule: the SDK mints tokens, widgets consume them. Your secret
  # key never reaches a browser.
  class Sessions < Resource
    CAPABILITIES = ["event:view", "event:block", "event:cancel", "event:reports"].freeze

    # Mint a manage-session token for the control room.
    #
    # +capabilities+ is required here even though the API defaults it. That
    # default grants all four — including event:cancel, which un-books paid
    # inventory. Granting the ability to reverse sales by forgetting an argument
    # is not a default worth inheriting.
    def create_manage_session(event_key, allowed_origin:, capabilities:, expires_in_seconds: nil)
      if capabilities.nil? || capabilities.empty?
        raise ArgumentError,
              "capabilities is required: pass the smallest set the page needs, e.g. " \
              '["event:view"]. Omitting it server-side grants event:cancel, ' \
              "which can reverse paid bookings."
      end

      body = compact({ "allowedOrigin" => allowed_origin, "capabilities" => capabilities,
                       "expiresInSeconds" => expires_in_seconds })
      @client.post("/v1/events/#{encode(event_key)}/manage-sessions", body)
    end

    def revoke_manage_session(event_key, session_id)
      @client.delete("/v1/events/#{encode(event_key)}/manage-sessions/#{encode(session_id)}")
    end

    # Mint a designer token so an organiser can edit a chart inside your own UI.
    # Requires a chart id that already exists — create or copy one first.
    def create_designer_session(workspace_id:, chart_id:, allowed_origin:,
                                authority: nil, mode: nil, expires_in_seconds: nil)
      body = compact({ "workspaceId" => workspace_id, "chartId" => chart_id,
                       "allowedOrigin" => allowed_origin, "authority" => authority,
                       "mode" => mode, "expiresInSeconds" => expires_in_seconds })
      @client.post("/v1/designer/sessions", body)
    end

    def revoke_designer_session(session_id)
      @client.delete("/v1/designer/sessions/#{encode(session_id)}")
    end
  end

  # Manage webhook subscriptions. To VERIFY a delivery, see SeatLayer::Webhook.
  class Webhooks < Resource
    def list
      @client.get("/v1/webhooks")
    end

    def create(url:, events:)
      @client.post("/v1/webhooks", { "url" => url, "events" => events })
    end

    def update(webhook_id, fields)
      @client.patch("/v1/webhooks/#{encode(webhook_id)}", fields)
    end

    def delete(webhook_id)
      @client.delete("/v1/webhooks/#{encode(webhook_id)}")
    end

    def list_deliveries(webhook_id)
      @client.get("/v1/webhooks/#{encode(webhook_id)}/deliveries")
    end
  end

  # Workspaces isolate one tenant's charts and events from another's.
  class Workspaces < Resource
    def list
      @client.get("/v1/workspaces")
    end

    def create(name:, external_ref: nil, idempotency_key: nil)
      body = compact({ "name" => name, "externalRef" => external_ref })
      @client.post("/v1/workspaces", body, idempotency_key: idempotency_key)
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
