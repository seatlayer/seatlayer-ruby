# frozen_string_literal: true

module SeatLayer
  # Base class for every SeatLayer error.
  class Error < StandardError; end

  # Raised for any non-2xx response.
  #
  # The API answers failures with {"error":…, "code":…, "message":…} and a status.
  # Surfacing that as one opaque exception leaves every caller string-matching on
  # +error+. The subclasses below are the ones an integration actually branches
  # on — a sold-out seat is a business outcome that belongs in a rescue of its
  # own, not lumped in with a bad key.
  class APIError < Error
    # @return [Integer] HTTP status the API answered with.
    attr_reader :status
    # @return [String] machine-readable slug: body "code", falling back to "error".
    attr_reader :code
    # @return [Hash] the decoded error body, for fields this SDK does not model.
    attr_reader :body
    # @return [String, nil] correlation id from X-Request-ID. Quote it in support requests.
    attr_reader :request_id

    def initialize(status:, code:, body:, request_id:, message: nil)
      @status = status
      @code = code
      @body = body
      @request_id = request_id
      super(message || "SeatLayer API error #{status} (#{code})")
    end

    # Build the most specific error class for a response.
    def self.from_response(status:, body:, request_id:, retry_after:)
      code = presence(body["code"]) || presence(body["error"]) || "unknown_error"
      attrs = { status: status, code: code, body: body, request_id: request_id,
                message: presence(body["message"]) }

      case status
      when 401, 403 then AuthError.new(**attrs)
      when 404 then NotFoundError.new(**attrs)
      when 409 then ConflictError.new(**attrs)
      when 422 then ValidationError.new(**attrs)
      when 429 then RateLimitError.new(**attrs, retry_after: retry_after)
      else APIError.new(**attrs)
      end
    end

    def self.presence(value)
      value.is_a?(String) && !value.empty? ? value : nil
    end
    private_class_method :presence
  end

  # 401/403 — bad key, revoked key, or a live key used against a test event.
  class AuthError < APIError
    # The key's mode and the event's mode disagree. The most common cause of a
    # "works locally, 403s in production" report.
    def mode_mismatch?
      code == "mode_mismatch"
    end
  end

  # 404 — including another organisation's resource.
  #
  # Asking for something owned by a different organisation answers 404, never
  # 403: a 403 would confirm the resource exists, which is not something one
  # customer should be able to learn about another.
  class NotFoundError < APIError; end

  # 409 — the seats moved under you.
  #
  # Normal in ticketing, not exceptional: two buyers wanted the same seat and one
  # lost.
  class ConflictError < APIError
    # @return [Array<Hash>] per-object conflicts, when the endpoint reports them.
    def conflicts
      value = body["conflicts"]
      value.is_a?(Array) ? value.grep(Hash) : []
    end

    # Best-available could not find enough free inventory.
    def sold_out?
      %w[sold_out not_enough_together].include?(body["reason"])
    end
  end

  # 422 — the request was understood and rejected.
  class ValidationError < APIError; end

  # 429. +retry_after+ prefers the header over the JSON field.
  class RateLimitError < APIError
    # @return [Float] seconds to wait before retrying.
    attr_reader :retry_after

    def initialize(retry_after:, **attrs)
      @retry_after = retry_after
      super(**attrs)
    end
  end

  # The request never got an answer: DNS, TLS, socket, or timeout.
  class ConnectionError < Error; end

  # The webhook delivery did not come from SeatLayer. Respond 400; do not
  # process it.
  class WebhookVerificationError < Error; end
end
