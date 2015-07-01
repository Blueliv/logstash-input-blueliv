Gem::Specification.new do |s|
  s.name = "logstash-input-blueliv"
  s.version = "0.1.0"
  s.licenses = ["Apache License (2.0)"]
  s.summary = "This plugin allows users to access Blueliv Crime Servers and Bot IPs feeds."
  s.description = "This gem is a logstash plugin required to be installed on top of the Logstash core pipeline using $LS_HOME/bin/plugin install logstash-input-blueliv. This gem is not a stand-alone program"
  s.authors = ["Blueliv"]
  s.email = 'community@blueliv.com'
  s.homepage = "http://github.com/Blueliv/logstash-input-blueliv"
  s.require_paths = ["lib"]

  # Files
  s.files = `git ls-files`.split($\)
  # Tests
  s.test_files = s.files.grep(%r{^(test|spec|features)/})


  s.metadata = { "logstash_plugin" => "true", "logstash_group" => "input" }

  # Gem dependencies
  s.add_runtime_dependency "logstash-core", ">= 1.4.0", "< 2.0.0"
  s.add_runtime_dependency "logstash-codec-plain"
  s.add_runtime_dependency "rest-client", "~> 1.8.0"
  s.add_development_dependency "logstash-devutils"
end
