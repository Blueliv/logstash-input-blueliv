#!/usr/bin/env ruby
# coding: UTF-8

require "date"
require "logstash/inputs/base"
require "logstash/namespace"
require "rest-client"
require "securerandom"

ONE_DAY_IN_SECONDS = 86400

RESOURCES = {
  :crimeservers => {
    :items => "crimeServers",
    :endpoint => "/v1/crimeserver",
    :feeds => {
      :all => {
        900 => "/last",
        3600 => "/recent",
        ONE_DAY_IN_SECONDS => "/online"
      },
      :test => {
        900 => "/test"
      }
    }
  },
  :botips => {
    :items => "ips",
    :endpoint => "/v1/ip",
    :feeds => {
      :non_pos => {
        600 => "/recent",
        3600 => "/last"
      },
      :pos => {
        600 => "/pos/recent",
        3600 => "/pos/last"
      },
      :full => {
        600 => "/full/recent",
        3600 => "/full/last"
      },
      :test => {
        600 => "/test"
      }
    }
  }
}

DEFAULT_CONFIG = {
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

INITIALIZE_FILE = "blueliv.ini"
FAILURE_SLEEP = 5 # seconds

class LogStash::Inputs::Blueliv < LogStash::Inputs::Base
  attr_accessor :auth, :timeout

  config_name "blueliv"

  @contact = "community@blueliv.com"

  default :codec, "plain"

  config :api_key, :validate => :string, :default => ""
  config :api_url, :validate => :string, :default => "https://api.blueliv.com"
  config :http_timeout, :validate => :number, :default => 500

  config :feeds, :validate => :hash, :default => {}

  public
  def register
    merger = proc { |key, v1, v2| Hash === v1 && Hash === v2 ? v1.merge(v2, &merger) : Array === v1 && Array === v2 ? v1 | v2 : [:undefined, nil, :nil].include?(v2) ? v1 : v2 }

    @auth = "Bearer #{api_key}"
    @feeds = DEFAULT_CONFIG.merge(feeds, &merger)
    @timeout = http_timeout
  end

  def run(queue)
      threads = []
      @feeds.each do |name, conf|
        if feeds[name]["active"]
          if feeds[name]["initialize"]
            if not db_updated?(DateTime.now)
              threads << Thread.new do
                url, interval = get_url(name, @feeds[name]["feed_type"], ONE_DAY_IN_SECONDS)
                get_feed(queue, name, url) { write_last_update_db(DateTime.now) }
                url, interval = get_url(name, @feeds[name]["feed_type"], @feeds[name]["interval"])
                get_feed_each(queue, name, url, interval) { write_last_update_db(DateTime.now) }
              end
            end
          else
            url, interval = get_url(name, @feeds[name]["feed_type"], @feeds[name]["interval"])
            threads << Thread.new(get_feed_each(queue, name, url, interval))
          end
        end
      end

      threads.map {|t| t.join}
  end

  def db_updated?(now)
    result = false
    if File.exists?(INITIALIZE_FILE)
      File.open(INITIALIZE_FILE, "r") do |file|
        file.each do |line|
          unless line.strip.start_with? "#"
            begin
              time = DateTime.strptime(line.strip, "%s")
              result = ((now - time) * ONE_DAY_IN_SECONDS).to_i < ONE_DAY_IN_SECONDS
              break
            rescue Exception => e
              @logger.error(e)
            end
          end
        end
      end
    end

    result
  end

  def write_last_update_db(date)
    File.open(INITIALIZE_FILE, "w") do |file|
      file.write("# GENERATED FILE. DO NOT EDIT IT\n")
      file.write("#{date.to_time.to_i}\n")
    end
  end

  def get_url(name, feed_type, feed_interval)
    base_url = @api_url + RESOURCES[name.to_sym][:endpoint]

    if RESOURCES[name.to_sym][:feeds].key?(feed_type.to_sym)
      feed_lookup = RESOURCES[name.to_sym][:feeds][feed_type.to_sym]
    else
      raise ArgumentError, "Feed #{feed_type} does not exist!"
    end

    interval = nil
    feed_lookup.keys.each do |k|
      if feed_interval <= k
        interval = k
        break
      end
    end
    interval = feed_lookup.keys.max if interval == nil

    return base_url + feed_lookup[interval], interval
  end

  def get_feed_each(queue, name, url, interval, &block)
    loop do
      get_feed(queue, name, url, &block)
      sleep(interval)
    end
  end

  def get_feed(queue, name, url, &block)
    loop do
      begin
        response = client.get url, :Authorization => @auth, :timeout => @timeout
        response_json = JSON.parse(response.body)
        items = response_json[RESOURCES[name.to_sym][:items]]
        items.each do |it|
          it["location"] = [it["longitude"].to_f, it["latitude"].to_f]
          collection = RESOURCES[name.to_sym][:items].downcase
          it["@collection"] = collection
          it["_id"] = SecureRandom.base64(32) unless it.has_key?("_id")
          evt =  LogStash::Event.new(it)
          decorate(evt)
          queue << evt
        end
        block.call if block
        break
      rescue RestClient::Exception => e
        case e.http_code
          when 401, 403
            @logger.info("You do not have access to this resource! Please contact #{@contact}")
            break
          when 404
            @logger.info("Resource #{url} not found")
            break
          when 429
            @logger.info("You exceeded your request limit rate!")
            break
          else
            @logger.error(e)
            @logger.info("Will retry in #{FAILURE_SLEEP} seconds")
            sleep(FAILURE_SLEEP)
        end
      rescue Exception => e
        @logger.info("Will retry in #{FAILURE_SLEEP} seconds")
        sleep(FAILURE_SLEEP)
      end
    end
  end

  def client
    RestClient
  end

end
