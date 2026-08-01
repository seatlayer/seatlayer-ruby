# frozen_string_literal: true

module SeatLayer
  # Shared plumbing for the resource namespaces.
  class Resource
    def initialize(client)
      @client = client
    end

    private

    # Build a request body, dropping nils so optional arguments stay optional
    # rather than being sent as explicit JSON null.
    def compact(hash)
      hash.compact
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
      @client.post("/v1/charts", body, idempotency_key: idempotency_key)
    end

    def retrieve(chart_id)
      @client.get("/v1/charts/#{encode(chart_id)}")
    end

    # Replace a chart document.
    #
    # +expected_updated_at+ is required for optimistic concurrency and is not
    # optional here either: without it two concurrent writers silently overwrite
    # each other, and a seat map is exactly the document where that loses work.
    # Read it from +retrieve+ immediately before writing.
    #
    # The Designer is the authoring surface. Use this for bulk programmatic edits
    # and migrations, not for drawing.
    def update(chart_id, doc:, expected_updated_at:, name: nil)
      body = compact({ "doc" => doc, "expectedUpdatedAt" => expected_updated_at, "name" => name })
      @client.put("/v1/charts/#{encode(chart_id)}", body)
    end

    def delete(chart_id)
      @client.delete("/v1/charts/#{encode(chart_id)}")
    end

    # Copy a chart — the usual way to provision a venue from a template.
    def copy(chart_id, idempotency_key: nil)
      @client.post("/v1/charts/#{encode(chart_id)}/duplicate", nil, idempotency_key: idempotency_key)
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

    def create(chart_id:, name: nil, slug: nil, starts_at: nil, venue: nil,
               external_ref: nil, currency: nil, idempotency_key: nil)
      body = compact({ "chartId" => chart_id, "name" => name, "slug" => slug,
                       "startsAt" => starts_at, "venue" => venue,
                       "externalRef" => external_ref, "currency" => currency })
      @client.post("/v1/events", body, idempotency_key: idempotency_key)
    end

    def retrieve(event_key)
      @client.get("/v1/events/#{encode(event_key)}")
    end

    def update(event_key, fields)
      @client.patch("/v1/events/#{encode(event_key)}", fields)
    end

    def delete(event_key)
      @client.delete("/v1/events/#{encode(event_key)}")
    end

    # Move a live event onto the latest published version of its chart.
    def update_chart(event_key)
      @client.post("/v1/events/#{encode(event_key)}/update-chart")
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
      @client.post("/v1/events/#{encode(event_key)}/hold-ttl", { "holdTtlMs" => hold_ttl_ms })
    end

    def retrieve_report(event_key)
      @client.get("/v1/events/#{encode(event_key)}/report")
    end

    def retrieve_log(event_key)
      @client.get("/v1/events/#{encode(event_key)}/log")
    end
  end
end
