require "logstash/devutils/rspec/spec_helper"
require "logstash/inputs/blueliv"
require "json"

describe LogStash::Inputs::Blueliv do
  let(:settings) {
    {
      "api_key" => "mykey",
      "feeds" => {
          "crimeservers" => {
            "active" => false,
            "feed_type" => "test",
            "interval" => 900,
            "initialize" => true
          },
          "botips" => {
            "active" => false,
            "feed_type" => "test",
            "interval" => 600
          }
      }
    }
  }

  let(:authorization) {
    "Bearer mykey"
  }

  let(:timeout) {
    500
  }

  let(:url) {
    "https://api.blueliv.com/v1/ip/full/last"
  }

  let(:feed_name) {
    "botips"
  }

  let(:mock_response) {
    RestClient::Response.create(
      {
        "ips" => [
            {
              "field1" => "this",
              "longitude" => 0.0,
              "latitude" => 0.0
            }
          ],
        "meta" => {
          "totalSize" =>  1,
          "updated" => "2015-07-01T10:40:00+0000",
          "nextUpdate" => "2015-07-01T10:50:00+0000"
        }
      }.to_json, nil, nil, nil)
  }

  context "with json codec, when server responds" do
    it "should not add an event if user is not authorized" do
       subject = LogStash::Inputs::Blueliv.new()
       logstash_queue = Queue.new

       subject.get_feed logstash_queue, feed_name, url
       expect(logstash_queue.size).to eq(0)
       subject.teardown
    end

    it "should add an event if user is authorized" do
       subject = LogStash::Inputs::Blueliv.new()
       logstash_queue = Queue.new
       subject.auth = authorization
       subject.timeout = timeout

       allow(subject.client).to receive(:get).with("#{url}?key=#{API_CLIENT}", :Authorization => authorization,
        :timeout => timeout, :user_agent => USER_AGENT, :headers => {"X-API-CLIENT" => API_CLIENT}).and_return(mock_response)
       subject.get_feed logstash_queue, feed_name, url
       expect(logstash_queue.size).to eq(1)
       subject.teardown
    end
  end
end

