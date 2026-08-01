# frozen_string_literal: true

require "json"
require "openssl"

module SeatLayer
  # Webhook signature verification.
  #
  # The most security-sensitive thing an integrator writes by hand, and the two
  # classic mistakes are both easy to make and silent:
  #
  # 1. verifying against a re-serialised body, which changes bytes and fails — or
  #    worse, gets "fixed" by skipping verification entirely;
  # 2. comparing signatures with ==, which leaks the expected value through timing.
  #
  # So the SDK does it, takes the RAW body, and compares in constant time.
  module Webhook
    module_function

    # Verify a delivery and return its decoded payload.
    #
    # +payload+ must be the raw request body. In Rails that is
    # <tt>request.raw_post</tt>; in Sinatra, <tt>request.body.read</tt>. Never a
    # parsed Hash re-encoded.
    #
    # NOTE ON REPLAY: deliveries are signed over the body, which carries an "at"
    # timestamp — but nothing enforces a freshness window, so a captured delivery
    # stays valid indefinitely. Replay protection is yours: every event carries
    # an occurrenceId, and the correct pattern is to record processed ids and
    # ignore repeats. Do not skip this.
    #
    # @raise [SeatLayer::WebhookVerificationError] when the delivery is not ours
    def verify(payload, signature, secret)
      raise WebhookVerificationError, "A webhook signing secret is required." if secret.nil? || secret.empty?

      if signature.nil? || signature.empty?
        raise WebhookVerificationError, "Missing X-SeatLayer-Signature header."
      end

      scheme, _, provided = signature.partition("=")
      if scheme != "sha256" || provided.empty?
        raise WebhookVerificationError,
              "Unsupported signature format #{signature.inspect}; expected \"sha256=<hex>\"."
      end

      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, payload)
      # secure_compare is constant time and handles a length mismatch without
      # leaking which of the two failures occurred.
      unless OpenSSL.secure_compare(expected, provided)
        raise WebhookVerificationError, "Webhook signature did not match."
      end

      begin
        JSON.parse(payload)
      rescue JSON::ParserError => e
        raise WebhookVerificationError, "Signature verified but the body is not valid JSON: #{e.message}"
      end
    end
  end
end
