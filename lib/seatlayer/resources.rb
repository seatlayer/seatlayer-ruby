# frozen_string_literal: true

module SeatLayer
  # Shared plumbing for the resource namespaces.
  class Resource
    UNSET = Object.new.freeze

    def initialize(client)
      @client = client
    end

    private

    # Build a request body, dropping nils so optional arguments stay optional
    # rather than being sent as explicit JSON null.
    def compact(hash)
      hash.compact
    end

    # Drop only the private sentinel, preserving nil as explicit JSON null.
    def supplied(hash)
      hash.reject { |_key, value| value.equal?(UNSET) }
    end

    def encode(segment)
      HTTPClient.encode(segment)
    end
  end

  # Seat-map definitions that events are created from.
  #
  # Even when organisers draw their own venues in the embedded Designer you need
  # this: +create_designer_session+ requires a chart id that already exists, so
  # the usual platform flow is copy a template here, then hand over a session.
  class Charts < Resource
    # One page of charts. Pass +cursor+ from the previous page's "nextCursor".
    def list(workspace_id: nil, external_ref: nil, archived: false, limit: nil, cursor: nil)
      query = compact({ "workspaceId" => workspace_id, "externalRef" => external_ref,
                        "limit" => limit, "cursor" => cursor })
      query["archived"] = "1" if archived
      @client.get("/v1/charts", query)
    end

    # Every chart, paging transparently.
    #
    # Returns an Enumerator when no block is given, so it stays lazy — the point
    # of paginating was to not hold an unbounded result set in memory, and
    # returning an Array would hand that problem straight back.
    #
    #   client.charts.list_all { |chart| ... }
    #   client.charts.list_all.lazy.first(5)
    def list_all(**options, &block)
      return enum_for(:list_all, **options) unless block_given?

      cursor = nil
      loop do
        page = list(**options, cursor: cursor)
        Array(page["charts"]).each(&block)
        cursor = page["nextCursor"]
        # An absent cursor terminates, so a caller looping cannot spin forever.
        break if cursor.nil? || cursor.empty?
      end
    end

    def create(name:, doc: nil, external_ref: nil, workspace_id: nil, idempotency_key: nil)
      body = compact({ "name" => name, "doc" => doc,
                       "externalRef" => external_ref, "workspaceId" => workspace_id })
      @client.post(
        "/v1/charts", body, idempotency_key: idempotency_key, retry_policy: :header_replay
      )
    end

    def retrieve(chart_id)
      @client.get("/v1/charts/#{encode(chart_id)}")
    end

    # Replace a chart document or update metadata only.
    #
    # +expected_updated_at+ is required for optimistic concurrency and is not
    # optional here either: without it two concurrent writers silently overwrite
    # each other, and a seat map is exactly the document where that loses work.
    # Read it from +retrieve+ immediately before writing.
    #
    # The Designer is the authoring surface. Use this for bulk programmatic edits
    # and migrations, not for drawing.
    def update(chart_id, doc: UNSET, expected_updated_at: UNSET, name: nil, issues: nil,
               external_ref: UNSET)
      doc_supplied = !doc.equal?(UNSET)
      expected_supplied = !expected_updated_at.equal?(UNSET)
      unless doc_supplied == expected_supplied
        raise ArgumentError, "doc and expected_updated_at must be supplied together"
      end

      body = compact({ "name" => name, "issues" => issues })
      if doc_supplied
        body["doc"] = doc
        body["expectedUpdatedAt"] = expected_updated_at
      end
      body.merge!(supplied({ "externalRef" => external_ref }))
      @client.put("/v1/charts/#{encode(chart_id)}", body)
    end

    def delete(chart_id)
      @client.delete("/v1/charts/#{encode(chart_id)}")
    end

    # Copy a chart — the usual way to provision a venue from a template.
    def copy(chart_id, idempotency_key: nil, name: nil, external_ref: UNSET,
             workspace_id: nil)
      body = compact({ "name" => name, "workspaceId" => workspace_id })
      body.merge!(supplied({ "externalRef" => external_ref }))
      @client.post(
        "/v1/charts/#{encode(chart_id)}/duplicate", body.empty? ? nil : body,
        idempotency_key: idempotency_key, retry_policy: :header_replay
      )
    end

    def archive(chart_id)
      @client.post("/v1/charts/#{encode(chart_id)}/archive")
    end

    def unarchive(chart_id)
      @client.post("/v1/charts/#{encode(chart_id)}/unarchive")
    end

    # Publish the draft. Events can only be created from a published chart.
    def publish(chart_id)
      @client.post("/v1/charts/#{encode(chart_id)}/publish")
    end
  end

  # Published SeatLayer catalogue templates.
  #
  # Instantiation creates an independent draft chart. Publish that returned
  # chart before creating an event from it.
  class Templates < Resource
    # Instantiate a public template into a new draft chart.
    #
    # +fields+ intentionally defaults to an empty Hash: the API requires a JSON
    # object even when there are no overrides, and JSON.generate({}) is `{}`.
    def instantiate_template(template_id, fields: {}, idempotency_key: nil)
      @client.post(
        "/v1/templates/#{encode(template_id)}/instantiate", fields,
        idempotency_key: idempotency_key, retry_policy: :header_replay
      )
    end
  end

  # Event lifecycle, metadata and reports.
  class Events < Resource
    # One page of events.
    #
    # Live availability counts cost one round-trip per event server-side. They
    # are on by default because most callers of a single page want them; pass
    # <tt>counts: false</tt> when paging a whole catalogue.
    def list(workspace_id: nil, external_ref: nil, limit: nil, cursor: nil, counts: true)
      query = compact({ "workspaceId" => workspace_id, "externalRef" => external_ref,
                        "limit" => limit, "cursor" => cursor })
      query["counts"] = "0" unless counts
      @client.get("/v1/events", query)
    end

    # Every event, paging transparently. Counts default off here — you are
    # walking the whole list, so per-event availability is rarely what you want
    # and always what it costs.
    def list_all(counts: false, **options, &block)
      return enum_for(:list_all, counts: counts, **options) unless block_given?

      cursor = nil
      loop do
        page = list(**options, counts: counts, cursor: cursor)
        Array(page["events"]).each(&block)
        cursor = page["nextCursor"]
        break if cursor.nil? || cursor.empty?
      end
    end

    # rubocop:disable Metrics/ParameterLists
    def create(chart_id:, name: nil, slug: nil, starts_at: UNSET, venue: UNSET,
               external_ref: UNSET, currency: UNSET, idempotency_key: nil,
               description: UNSET, ends_at: UNSET, timezone: UNSET, locale: UNSET,
               poster_asset_id: UNSET, mode: nil)
      body = compact({ "chartId" => chart_id, "name" => name, "slug" => slug, "mode" => mode })
      body.merge!(supplied({ "startsAt" => starts_at, "venue" => venue,
                             "externalRef" => external_ref, "currency" => currency,
                             "description" => description, "endsAt" => ends_at,
                             "timezone" => timezone, "locale" => locale,
                             "posterAssetId" => poster_asset_id }))
      @client.post(
        "/v1/events", body, idempotency_key: idempotency_key, retry_policy: :header_replay
      )
    end
    # rubocop:enable Metrics/ParameterLists

    def retrieve(event_key)
      @client.get("/v1/events/#{encode(event_key)}")
    end

    # Read the Event's exact immutable configuration selection and audit trail.
    def retrieve_configuration_binding(event_key)
      @client.get("/v1/events/#{encode(event_key)}/event-configuration")
    end

    # Attach an exact published configuration version, or pass +nil+ to detach.
    # The expected revision prevents one administrator from silently overwriting
    # another, and the mutation remains deliberately single-attempt.
    def update_configuration_binding(event_key, expected_revision:, configuration:)
      @client.put(
        "/v1/events/#{encode(event_key)}/event-configuration",
        { "expectedRevision" => expected_revision, "configuration" => configuration }
      )
    end

    def update(event_key, fields)
      @client.patch("/v1/events/#{encode(event_key)}", fields)
    end

    def delete(event_key)
      @client.delete("/v1/events/#{encode(event_key)}")
    end

    # Upload raw PNG, JPEG, or WebP bytes (maximum 5 MiB).
    def update_poster(event_key, image, content_type: "application/octet-stream")
      @client.put_raw("/v1/events/#{encode(event_key)}/poster", image, content_type: content_type)
    end

    def delete_poster(event_key)
      @client.delete("/v1/events/#{encode(event_key)}/poster")
    end

    # Move a live event onto the latest published version of its chart.
    def update_chart(event_key, acknowledge_dropped_assignments: nil, reason: nil)
      body = compact({ "acknowledgeDroppedAssignments" => acknowledge_dropped_assignments,
                       "reason" => reason })
      @client.post("/v1/events/#{encode(event_key)}/update-chart", body)
    end

    # Stop buyer sales. Existing holds keep their TTL.
    def close(event_key)
      @client.post("/v1/events/#{encode(event_key)}/close")
    end

    def reopen(event_key)
      @client.post("/v1/events/#{encode(event_key)}/reopen")
    end

    def archive(event_key)
      @client.post("/v1/events/#{encode(event_key)}/archive")
    end

    def retrieve_hold_ttl(event_key)
      @client.get("/v1/events/#{encode(event_key)}/hold-ttl")
    end

    def update_hold_ttl(event_key, hold_ttl_ms)
      # +nil+ restores the event default and must remain an explicit JSON null.
      @client.post("/v1/events/#{encode(event_key)}/hold-ttl", { "holdTtlMs" => hold_ttl_ms })
    end

    def list_ticket_releases(event_key)
      @client.get("/v1/events/#{encode(event_key)}/releases")
    end

    # Replace every ticket release for an event. This stays single-attempt: the
    # route does not promise exact idempotent-response replay.
    def update_ticket_releases(event_key, releases:)
      @client.put("/v1/events/#{encode(event_key)}/releases", { "releases" => releases })
    end

    # Close one release while preserving its audit provenance.
    def close_ticket_release(event_key, release_id)
      @client.post("/v1/events/#{encode(event_key)}/releases/#{encode(release_id)}/close")
    end

    def retrieve_report(event_key)
      @client.get("/v1/events/#{encode(event_key)}/report")
    end

    def retrieve_log(event_key, limit: nil, before: nil)
      @client.get("/v1/events/#{encode(event_key)}/log",
                  compact({ "limit" => limit, "before" => before }))
    end
  end
end
