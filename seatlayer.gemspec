# frozen_string_literal: true

require_relative "lib/seatlayer/version"

Gem::Specification.new do |spec|
  spec.name = "seatlayer"
  spec.version = SeatLayer::VERSION
  spec.authors = ["SeatLayer"]
  spec.email = ["hello@seatlayer.io"]

  spec.summary = "Official Ruby server SDK for the SeatLayer reserved-seating API."
  spec.description = "Server-side Ruby client for SeatLayer: charts, events, holds, booking, " \
                     "embed sessions and webhook verification, with idempotency and retries built in."
  spec.homepage = "https://docs.seatlayer.io/server-sdk/install/"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/seatlayer/seatlayer-ruby"
  spec.metadata["changelog_uri"] = "https://github.com/seatlayer/seatlayer-ruby/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "https://github.com/seatlayer/seatlayer-ruby/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "LICENSE", "README.md", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  # No runtime dependencies on purpose. A server SDK that drags in Faraday or
  # HTTParty becomes a supply-chain surface for every customer and can conflict
  # with what the host app already uses. net/http and openssl are stdlib.
end
