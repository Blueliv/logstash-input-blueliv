#!/usr/bin/env ruby
# coding: UTF-8

require "date"
require "logstash/inputs/base"
require "logstash/namespace"
require "rest-client"
require "securerandom"


USER_AGENT = "Logstash 1.1.0"
API_CLIENT = "6ee37a93-d064-464b-b4c1-c37e9656273f"

RESOURCES = {
  :crimeservers => {
    :items => "crimeServers",
    :endpoint => "/v1/crimeserver",
    :feeds => {
      :last => {
        900 => "/last"
      },
      :recent => {
        3600 => "/recent"
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
        600 => "/last",
        3600 => "/recent"
      },
      :pos => {
        600 => "/pos/last",
        3600 => "/pos/recent"
      },
      :full => {
        600 => "/full/last",
        3600 => "/full/recent"
      },
      :test => {
        600 => "/test"
      }
    }
  },
  :attacks => {
    :items => "attacks",
    :endpoint => "/v1/attack",
    :feeds => {
      :last => {
        1800 => "/last"
      },
      :recent => {
        10800 => "/recent"
      }
    }
  },
  :malwares => {
    :items => "malwares",
    :endpoint => "/v1/malware",
    :feeds => {
      :last => {
        600 => "/last"
      },
      :recent => {
        3600 => "/recent"
      }
    }
  }
}

DEFAULT_CONFIG = {
  "attacks" => {
    "active" => false,
    "feed_type" => "recent",
    "interval" => 600
  },
  "botips" => {
    "active" => false,
    "feed_type" => "test",
    "interval" => 600
  },
  "crimeservers" => {
    "active" => true,
    "feed_type" => "test",
    "interval" => 900
  },
  "malwares" => {
    "active" => false,
    "feed_type" => "recent",
    "interval" => 3600
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
        if conf["active"] == 'true'
          url, interval = get_url(name, conf["feed_type"], conf["interval"])
          threads << Thread.new{get_feed_each(queue, name, url, interval)}
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
    @logger.info("Start getting #{url} feed")
    loop do
      begin
        response = client.get("#{url}?key=#{API_CLIENT}", :Authorization => @auth, :timeout => @timeout,
          :user_agent => USER_AGENT, :headers => {"X-API-CLIENT" => API_CLIENT})
        response_json = JSON.parse(response.body)
        keyItems = RESOURCES[name.to_sym][:items]
        items = response_json[keyItems]
        items.each do |it|
          collection = keyItems.downcase
          it = send("map_"+collection, it)
          it["@collection"] = collection
          it["document_id"] = if it.has_key?("_id") then it["_id"] else SecureRandom.base64(32) end
          it.delete("_id") if it.has_key?("_id")
          @logger.debug("#{it}")
          evt =  LogStash::Event.new(it)
          decorate(evt)
          queue << evt
        end
        @logger.info("End getting data from #{url}")
        block.call if block
        break
      rescue RestClient::Exception => e
        case e.http_code
          when 401, 403
            @logger.info("You do not have access to this resource #{url}! Please contact #{@contact}")
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
        @logger.info(e.message+"\n"+e.backtrace.join("\n"))
        sleep(FAILURE_SLEEP)
      end
    end
  end

  def client
    RestClient
  end

  private
  def map_global_location(it)
    it["location"] = [it["longitude"].to_f, it["latitude"].to_f]
    return it
  end

  def map_ips(it)
    map_global_location(it)
  end

  def map_crimeservers(it)
    map_global_location(it)
  end

  def map_attacks(it)
    source = it["source"];
    #map_global_location(source);
    it["location"] = [source["longitude"].to_f, source["latitude"].to_f]
    firstEvent = DateTime.parse(it["firstEvent"])
    lastEvent = DateTime.parse(it["lastEvent"])
    duration = ((lastEvent - firstEvent)* 24 * 60 * 60).to_i
    if duration < 0 
      duration = -duration
    end
    it[:duration] = duration
    return it
  end
  def map_malwares(it)
    it["_id"] = it["sha256"]
    return it
  end
end
