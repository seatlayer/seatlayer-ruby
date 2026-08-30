# frozen_string_literal: true

require_relative "seatlayer/version"
require_relative "seatlayer/errors"
require_relative "seatlayer/http_client"
require_relative "seatlayer/resources"
require_relative "seatlayer/inventory"
require_relative "seatlayer/channels"
require_relative "seatlayer/performance_groups"
require_relative "seatlayer/seasons"
require_relative "seatlayer/webhook"

# Official Ruby server SDK for the SeatLayer reserved-seating API.
#
# Server-side only: this gem authenticates with your secret key. Never load it
# anywhere a ticket buyer can reach — browser surfaces get short-lived, scoped
# tokens that you mint with SeatLayer::Sessions.
#
#   client = SeatLayer::Client.new(ENV.fetch("SEATLAYER_SECRET_KEY"))
#   held = client.inventory.hold_best_available("summer-gala", qty: 4)
module SeatLayer
  # The SeatLayer client.
  class Client
    attr_reader :charts, :events, :inventory, :channels, :performance_groups, :sessions,
                :seasons, :webhooks, :workspaces, :templates

    def initialize(secret_key, base_url: HTTPClient::DEFAULT_BASE_URL,
                   max_retries: HTTPClient::DEFAULT_MAX_RETRIES,
                   timeout: HTTPClient::DEFAULT_TIMEOUT, transport: nil)
      @http = HTTPClient.new(secret_key: secret_key, base_url: base_url,
                             max_retries: max_retries, timeout: timeout, transport: transport)

      @charts = Charts.new(@http)
      @events = Events.new(@http)
      @inventory = Inventory.new(@http)
      @channels = Channels.new(@http)
      @performance_groups = PerformanceGroups.new(@http)
      @seasons = Seasons.new(@http)
      @sessions = Sessions.new(@http)
      @templates = Templates.new(@http)
      @webhooks = Webhooks.new(@http)
      @workspaces = Workspaces.new(@http)
    end

    # @return [String] "live" or "test", derived from the key prefix.
    def mode
      @http.mode
    end

    # Dependency-aware readiness probe.
    def ready
      @http.get("/health/ready")
    end

    # Escape hatch for surface this SDK does not wrap yet. Reads retain retries;
    # raw mutations are single-attempt because their replay contract is unknown.
    def request(method, path, query: nil, body: nil, raw_body: nil, content_type: nil,
                idempotency_key: nil)
      @http.request(method, path, query: query, body: body, raw_body: raw_body,
                                  content_type: content_type, idempotency_key: idempotency_key)
    end
  end
end
