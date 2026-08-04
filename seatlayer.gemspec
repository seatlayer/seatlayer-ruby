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
  # RubyGems renders this as "Homepage" in the sidebar, so it points at the product,
  # not at one page of the docs — the docs get their own documentation_uri below.
  spec.homepage = "https://seatlayer.io"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["documentation_uri"] = "https://docs.seatlayer.io/server-sdk/install/"
  spec.metadata["source_code_uri"] = "https://github.com/seatlayer/seatlayer-ruby"
  spec.metadata["changelog_uri"] = "https://github.com/seatlayer/seatlayer-ruby/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "https://github.com/seatlayer/seatlayer-ruby/issues"
  # Requires MFA to be enabled on the publishing RubyGems account BEFORE the first
  # `gem push`, or the push is rejected. See RELEASE.md.
  spec.metadata["rubygems_mfa_required"] = "true"

  # Explicit globs, never `git ls-files`: the spec/ suite, .github/ and AGENTS.md
  # (repo-internal agent instructions) must not ship to anyone who installs the gem.
  spec.files = Dir["lib/**/*.rb", "LICENSE", "README.md", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  # No runtime dependencies on purpose. A server SDK that drags in Faraday or
  # HTTParty becomes a supply-chain surface for every customer and can conflict
  # with what the host app already uses. net/http and openssl are stdlib.
end
