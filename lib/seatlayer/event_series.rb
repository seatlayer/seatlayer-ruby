# frozen_string_literal: true

module SeatLayer
  # Event series: many dates of one show, planned from a schedule and run as
  # one. A series is addressed by the key of its first event.
  class EventSeries < Resource
    # Plan an event series from a +schedule+ Hash, or create it as a job.
    # Pass <tt>dry_run: true</tt> to get the dates back without creating any.
    # Every date carries +name+ as its name.
    #
    # Give +name+ and +chart_key+, or +from_event_key+: an event you already set
    # up becomes the first date under its own key, and every other date is a copy
    # of it (floor plan, prices, checkout, poster and its own seat blocks, none of
    # its orders, holds or sales). The series takes the event's name, zone and
    # floor plan.
    def create_event_series( # rubocop:disable Metrics/ParameterLists
      schedule:, name: nil, chart_key: nil, timezone: nil, venue: nil,
      duration_minutes: nil, dry_run: nil, idempotency_key: nil, from_event_key: nil
    )
      if from_event_key.nil? && (name.nil? || chart_key.nil?)
        raise ArgumentError, "give name: and chart_key:, or from_event_key:"
      end

      body = compact({ "fromEventKey" => from_event_key, "name" => name, "chartKey" => chart_key,
                       "schedule" => schedule, "timezone" => timezone, "venue" => venue,
                       "durationMinutes" => duration_minutes, "dryRun" => dry_run })
      @client.post("/v1/event-series", body, idempotency_key: idempotency_key,
                                             retry_policy: :header_replay)
    end

    # One page of event series.
    def list_event_series(limit: nil, cursor: nil)
      @client.get("/v1/event-series", compact({ "limit" => limit, "cursor" => cursor }))
    end

    # Read one event series.
    def retrieve_event_series(event_key)
      @client.get(path(event_key))
    end

    # Add dates to a series, copied from its first date. Pass one of a +schedule+
    # Hash, a +dates+ list of "YYYY-MM-DDTHH:MM" strings, or +retry_failed: true+ to
    # make again every date that failed to be made (422 nothing_to_retry when none
    # did, 409 series_busy while another change runs).
    def add_event_series_dates(event_key, schedule: nil, dates: nil, retry_failed: false,
                               idempotency_key: nil)
      @client.post(path(event_key, "/dates"),
                   compact({ "schedule" => schedule, "dates" => dates,
                             "retryFailed" => (retry_failed ? true : nil) }),
                   idempotency_key: idempotency_key, retry_policy: :header_replay)
    end

    # Rename a series, replace its prices, or turn sales "on" or "off" on every
    # upcoming date.
    def update_event_series(event_key, name: nil, prices: nil, sales: nil, idempotency_key: nil)
      @client.mutation_with_header_replay(
        "PATCH", path(event_key),
        compact({ "name" => name, "prices" => prices, "sales" => sales }),
        idempotency_key: idempotency_key
      )
    end

    private

    def path(event_key, suffix = "")
      "/v1/event-series/#{encode(event_key)}#{suffix}"
    end
  end
end
