# frozen_string_literal: true

require "seatlayer"
require "json"

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end

# Replays a queue of responses and records every request, so the retry loop and
# header handling are exercised without a network.
class StubTransport
  # `http_method`, not `method`: a Struct member named `method` overrides
  # Struct#method, which breaks anything reflecting on the object.
  Recorded = Struct.new(:http_method, :url, :headers, :body, keyword_init: true)

  attr_reader :calls

  def initialize(responses)
    @responses = responses.dup
    @calls = []
  end

  def to_proc
    method(:call).to_proc
  end

  def call(http_method, url, headers, body)
    @calls << Recorded.new(http_method: http_method, url: url, headers: headers, body: body)
    raise "more requests than queued responses" if @responses.empty?

    stub = @responses.shift
    {
      status: stub.fetch(:status),
      body: stub[:body] || "{}",
      headers: (stub[:headers] || {}).transform_keys(&:downcase)
    }
  end
end

def build_client(responses, **options)
  transport = StubTransport.new(responses)
  client = SeatLayer::Client.new("sk_test_abc", transport: transport.to_proc, **options)
  [client, transport]
end
