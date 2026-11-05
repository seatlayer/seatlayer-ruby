# frozen_string_literal: true

RSpec.describe SeatLayer::EventSeries do
  it "maps all 5 event series operations and their replay classes" do
    client, transport = build_client(Array.new(6) { { status: 202 } })
    series = client.event_series
    schedule = { "rule" => "weekly", "from" => "2027-01-04", "count" => 4, "times" => ["19:30"] }

    series.create_event_series(name: "Hamlet", chart_key: "chart_1", schedule: schedule,
                               timezone: "Europe/London", dry_run: true)
    series.list_event_series(limit: 10, cursor: "c/1")
    series.retrieve_event_series("ev/a")
    series.add_event_series_dates("ev/a", dates: ["2027-02-01T19:30"], idempotency_key: "dates-1")
    series.update_event_series("ev/a", sales: "off")
    series.add_event_series_dates("ev/a", retry_failed: true)

    expect(transport.calls.map { |call| request_summary(call) }).to eq(
      [
        ["POST /v1/event-series",
         { "name" => "Hamlet", "chartKey" => "chart_1", "schedule" => schedule,
           "timezone" => "Europe/London", "dryRun" => true }, true],
        ["GET /v1/event-series?limit=10&cursor=c%2F1", nil, false],
        ["GET /v1/event-series/ev%2Fa", nil, false],
        ["POST /v1/event-series/ev%2Fa/dates", { "dates" => ["2027-02-01T19:30"] }, true],
        ["PATCH /v1/event-series/ev%2Fa", { "sales" => "off" }, true],
        # Make again the dates that failed to be made.
        ["POST /v1/event-series/ev%2Fa/dates", { "retryFailed" => true }, true]
      ]
    )
    expect(transport.calls[3].headers["Idempotency-Key"]).to eq("dates-1")
  end
end
