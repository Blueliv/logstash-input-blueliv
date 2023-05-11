# This repositoy is deprecated and has been archived. Please contact customer support if you need help. Thanks

# Logstash Input Plugin by Blueliv

This is an input plugin for [Logstash](https://github.com/elasticsearch/logstash) created and maintained by Blueliv (community@blueliv.com), that allows to access Blueliv's Cyber-Threat Intelligence feeds, such as Crime Servers and Bot IPs.

## Minimum Requirements

* API key (get yours [here](https://community.blueliv.com) )
* Logstash >= 1.5.0
* ElasticSearch >= 2.0.0 (Tested on 2.4.0)

## Installing

```
# In logstash version < 2.3

$LS_HOME/bin/plugin install --version 1.1.0 logstash-input-blueliv

# In logstash version >2.3
$LS_HOME/bin/logstash-plugin install logstash-input-blueliv


```

### Configuration

This plugin has the following configuration parameters:

+ ``api_url`` (default: ``https://api.blueliv.com``): the URL of the API. It may change if you are using our free or commercial API.
+ ``api_key``: The API key to access our feeds. This parameter is **mandatory**.
+ ``http_timeout``(default: ``500`` seconds): HTTP timeout for each API call.
+ ``feeds``: It is a [hash](http://ruby-doc.org/core-1.9.3/Hash.html) that specifies the parameters to access each one of our feeds. Each feed may be configured with the following properties:
    + ``active`` (default: ``false``): if the feed is active or not.
    + ``feed_type`` (default: ``test``): the type of the feed that you want. For **Crime Servers** apart from ``test`` (for _debug_ purposes) you have ``recent`` (1 hour updates) and ``last`` (15 minutes updates). As of **Bot IPs** you may choose between ``non_pos`` (all BotIPs **but** the ones from Point-of-Sale), ``pos`` (only from POS)  or ``full`` (all of them) feed.
    + ``interval`` (default: ``600`` seconds for BotIPs and ``900`` seconds for Crime Servers). The intervall of polling data from our API.

The default configuration for ``feeds`` field is the following:
```javascript
{
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
```


#### Example

```javascript
input {
 blueliv {
  api_key => "<YOUR API KEY>"
  feeds => {
    "attacks" => {
      "active" => "true"
      "feed_type" => "recent"
    }
    "botips" => {
      "active" => "true"
      "feed_type" => "non_pos"
    }
    "crimeservers" => {
      "active" => "true"
      "feed_type" => "recent"
    }
    "malwares" => {
      "active" => "true"
      "feed_type" => "recent"
    }
  }
}
```

Be aware that if you do not specify a given field, the default value will be configured. In this case, we did not touch the ``interval`` field for the feeds, so the defaults will apply.

## Need Help?

Need help? Send us an email to community@blueliv.com

## Contributing

All contributions are welcome: ideas, patches, documentation, bug reports, complaints, and even something you drew up on a napkin.
