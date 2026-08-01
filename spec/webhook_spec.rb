# frozen_string_literal: true

require "openssl"

RSpec.describe SeatLayer::Webhook do
  # A method, not a constant: a constant inside a describe block leaks into
  # global scope and RuboCop rightly flags it.
  def secret
    "whsec_test"
  end

  def sign(payload, signing_secret = "whsec_test")
    "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", signing_secret, payload)}"
  end

  it "accepts a correctly signed delivery" do
    payload = '{"type":"booking.created","occurrenceId":"occ_1"}'
    event = described_class.verify(payload, sign(payload), secret)
    expect(event["type"]).to eq("booking.created")
  end

  it "rejects a body that was re-serialised rather than passed through raw" do
    # The classic integration bug: re-encoding the parsed body changes the bytes,
    # here by reformatting, so it no longer matches what was signed.
    original = '{"deliveryId":"d_1","occurrenceId":"occ_1","at":1754006400000}'
    reserialised = JSON.pretty_generate(JSON.parse(original))
    expect(reserialised).not_to eq(original) # the setup must actually change bytes

    expect { described_class.verify(reserialised, sign(original), secret) }
      .to raise_error(SeatLayer::WebhookVerificationError)
  end

  it "rejects a signature made with the wrong secret" do
    payload = '{"ok":true}'
    expect { described_class.verify(payload, sign(payload, "whsec_other"), secret) }
      .to raise_error(SeatLayer::WebhookVerificationError, /did not match/)
  end

  it "rejects a missing header rather than trusting the body" do
    expect { described_class.verify("{}", nil, secret) }
      .to raise_error(SeatLayer::WebhookVerificationError, /Missing X-SeatLayer-Signature/)
  end

  it "rejects an unknown signature scheme" do
    expect { described_class.verify("{}", "md5=abc", secret) }
      .to raise_error(SeatLayer::WebhookVerificationError, /Unsupported signature format/)
  end

  it "rejects a truncated signature without leaking which check failed" do
    payload = '{"ok":true}'
    expect { described_class.verify(payload, sign(payload)[0, 20], secret) }
      .to raise_error(SeatLayer::WebhookVerificationError)
  end

  it "requires a secret" do
    expect { described_class.verify("{}", sign("{}"), "") }
      .to raise_error(SeatLayer::WebhookVerificationError, /signing secret is required/)
  end

  it "reports a verified-but-unparseable body distinctly" do
    payload = "not json"
    expect { described_class.verify(payload, sign(payload), secret) }
      .to raise_error(SeatLayer::WebhookVerificationError, /not valid JSON/)
  end

  it "verifies a body containing non-ASCII, byte for byte" do
    # A venue named "Théâtre" must verify — this is where an encoding mismatch
    # in the HMAC would show up.
    payload = '{"venue":"Théâtre du Châtelet — 日本"}'
    event = described_class.verify(payload, sign(payload), secret)
    expect(event["venue"]).to eq("Théâtre du Châtelet — 日本")
  end
end
