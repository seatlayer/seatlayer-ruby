# frozen_string_literal: true

require "json"
require "net/http"
require "securerandom"
require "uri"

module SeatLayer
  # The transport: auth, idempotency, retry, and error mapping.
  #
  # Built on net/http from the standard library rather than Faraday or HTTParty.
  # A server SDK that drags in an HTTP stack becomes a supply-chain surface for
  # every customer who installs it, and can conflict with whatever the host
  # application already uses.
  class HTTPClient
    DEFAULT_BASE_URL = "https://api.seatlayer.io"
    DEFAULT_MAX_RETRIES = 3
    DEFAULT_TIMEOUT = 30.0

    # The API's own charset for Idempotency-Key.
    IDEMPOTENCY_KEY_PATTERN = /\A[A-Za-z0-9._:-]{1,128}\z/

    # @return [String] "live", "test", or "unknown", derived from the key prefix.
    attr_reader :mode
    attr_reader :base_url

    def initialize(secret_key:, base_url: DEFAULT_BASE_URL, max_retries: DEFAULT_MAX_RETRIES,
                   timeout: DEFAULT_TIMEOUT, transport: nil)
      raise ArgumentError, "A SeatLayer secret key is required." if secret_key.nil? || secret_key.empty?

      # Caught here rather than as a 401 three round-trips later. The pk_ case
      # gets its own message: it is the one people paste by mistake.
      if secret_key.start_with?("pk_")
        raise ArgumentError,
              "That is a publishable key. The server SDK needs a secret key (sk_live_… or sk_test_…)."
      end
      unless secret_key.start_with?("sk_")
        raise ArgumentError, "A SeatLayer secret key starts with sk_live_ or sk_test_."
      end

      @secret_key = secret_key
      @base_url = base_url.sub(%r{/+\z}, "")
      @max_retries = max_retries
      @timeout = timeout
      @transport = transport
      @mode = if secret_key.start_with?("sk_test_") then "test"
              elsif secret_key.start_with?("sk_live_") then "live"
              else "unknown"
              end
    end

    def self.validate_idempotency_key!(key)
      return if IDEMPOTENCY_KEY_PATTERN.match?(key)

      raise ArgumentError,
            "Invalid Idempotency-Key #{key.inspect}: allowed characters are " \
            "A-Z a-z 0-9 . _ : - and the length must be 1-128."
    end

    # Percent-encode a path segment, including slashes.
    def self.encode(segment)
      URI.encode_www_form_component(segment.to_s).gsub("+", "%20")
    end

    def request(method, path, query: nil, body: nil, raw_body: nil, content_type: nil,
                idempotency_key: nil, retry_policy: :none)
      url = @base_url + path
      if query
        pairs = query.compact
        url += "?#{URI.encode_www_form(pairs)}" unless pairs.empty?
      end

      headers = {
        "Authorization" => "Bearer #{@secret_key}",
        "Accept" => "application/json",
        "User-Agent" => "seatlayer-ruby"
      }
      payload = build_payload(body, raw_body, content_type, headers)

      # Only operations with exact server-side response replay get an automatic
      # key. A caller key on any other mutation is forwarded, but cannot opt that
      # operation into automatic retries.
      unless %w[GET HEAD].include?(method)
        key = idempotency_key
        key ||= SecureRandom.uuid if retry_policy == :header_replay
        if key
          self.class.validate_idempotency_key!(key)
          headers["Idempotency-Key"] = key
        end
      end

      retry_allowed = %w[GET HEAD].include?(method) || retry_policy == :header_replay
      execute(method, url, headers, payload, retry_allowed: retry_allowed)
    end

    def get(path, query = nil)
      request("GET", path, query: query)
    end

    def post(path, body = nil, idempotency_key: nil, retry_policy: :none)
      request("POST", path, body: body, idempotency_key: idempotency_key, retry_policy: retry_policy)
    end

    # Internal path for non-POST mutations backed by exact response replay.
    def mutation_with_header_replay(method, path, body = nil, idempotency_key: nil)
      request(method, path, body: body, idempotency_key: idempotency_key,
                            retry_policy: :header_replay)
    end

    def put(path, body)
      request("PUT", path, body: body)
    end

    def put_raw(path, raw_body, content_type: "application/octet-stream")
      request("PUT", path, raw_body: raw_body, content_type: content_type)
    end

    def patch(path, body)
      request("PATCH", path, body: body)
    end

    def delete(path, query = nil)
      request("DELETE", path, query: query)
    end

    private

    def build_payload(body, raw_body, content_type, headers)
      raise ArgumentError, "body and raw_body are mutually exclusive" if !body.nil? && !raw_body.nil?

      unless raw_body.nil?
        headers["Content-Type"] = content_type || "application/octet-stream"
        return raw_body
      end
      return if body.nil?

      headers["Content-Type"] = "application/json"
      JSON.generate(body)
    end

    # The retry loop, extracted from #request so each piece stays readable: the
    # public method builds the call, this one decides how many times to make it.
    def execute(method, url, headers, payload, retry_allowed:)
      last_error = nil

      @max_retries.times do |attempt|
        begin
          response = send_request(method, url, headers, payload)
        rescue ConnectionError => e
          raise e unless retry_allowed && attempt < @max_retries - 1

          last_error = e
          sleep(backoff(attempt, nil))
          next
        end

        status = response[:status]
        return parse_success(status, response[:body]) if status >= 200 && status < 300

        error_body = decode_error_body(response[:body])
        retry_after = parse_retry_after(response[:headers], error_body)

        if retry_allowed && retryable?(status) && attempt < @max_retries - 1
          sleep(backoff(attempt, status == 429 ? retry_after : nil))
          next
        end

        raise APIError.from_response(
          status: status, body: error_body,
          request_id: response[:headers]["x-request-id"], retry_after: retry_after
        )
      end

      raise last_error || ConnectionError.new("Request failed with no attempts made.")
    end

    # A proxy or WAF can answer with HTML; that must not become a parse crash
    # that hides the real status from the caller.
    def decode_error_body(body)
      parsed = JSON.parse(body.to_s)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end

    def parse_success(status, body)
      return {} if status == 204 || body.nil? || body.empty?

      JSON.parse(body)
    end

    def send_request(method, url, headers, payload)
      return @transport.call(method, url, headers, payload) if @transport

      uri = URI.parse(url)
      request_class = Net::HTTP.const_get(method.capitalize)
      http_request = request_class.new(uri)
      headers.each { |name, value| http_request[name] = value }
      http_request.body = payload if payload

      response = Net::HTTP.start(uri.hostname, uri.port,
                                 use_ssl: uri.scheme == "https",
                                 open_timeout: @timeout, read_timeout: @timeout) do |http|
        http.request(http_request)
      end

      normalised = {}
      response.each_header { |name, value| normalised[name.downcase] = value }
      { status: response.code.to_i, body: response.body, headers: normalised }
    rescue StandardError => e
      raise ConnectionError, "Request to #{method} #{url} failed: #{e.message}"
    end

    # Retry only what is safe to retry. 429 and 5xx are transient by definition;
    # a 4xx is the API saying the request itself is wrong, and retrying only
    # burns rate-limit budget and delays the error the caller needs to see.
    def retryable?(status)
      status == 429 || status == 408 || (status >= 500 && status < 600)
    end

    # Exponential with full jitter, so a fleet of workers limited at the same
    # moment does not retry in lockstep and re-limit itself.
    def backoff(attempt, retry_after)
      return retry_after if retry_after

      ceiling = [8.0, 0.25 * (2**attempt)].min
      rand * ceiling
    end

    def parse_retry_after(headers, body)
      header = headers["retry-after"]
      if header
        seconds = Float(header, exception: false)
        return seconds if seconds && seconds >= 0
      end
      # Fall back to the JSON field for routes that predate the headers.
      field = body["retryAfterSeconds"]
      field.is_a?(Numeric) ? field.to_f : 1.0
    end
  end
end
