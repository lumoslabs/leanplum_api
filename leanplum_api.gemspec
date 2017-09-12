$:.push File.expand_path('../lib', __FILE__)

require 'leanplum_api/version'

Gem::Specification.new do |gem|
  gem.name        = 'leanplum_api'
  gem.version     = LeanplumApi::VERSION
  gem.authors     = ['Lumos Labs, Inc.', 'Countable Corp']
  gem.email       = ['analytics-dev@lumoslabs.com', 'eng@countable.us']
  gem.homepage    = 'http://www.github.com/lumoslabs/leanplum_api'
  gem.summary     = 'Gem for the Leanplum API'
  gem.description = 'Ruby-esque access to Leanplum API'
  gem.licenses    = ['MIT']
  gem.files       = Dir["lib/**/*"] + ['Gemfile', 'LICENSE.txt', 'README.md']
  gem.test_files  = Dir["spec/**/*"]

  gem.required_ruby_version = '>= 2.0'

  gem.add_dependency 'activesupport', '> 3.0', '< 5'
  gem.add_dependency 'awesome_print', '~> 1'
  gem.add_dependency 'faraday', '~> 0.9', '>= 0.9.1'
  gem.add_dependency 'faraday_middleware', '~> 0.9.1'

  gem.add_development_dependency 'rspec', '~> 3'
  gem.add_development_dependency 'timecop', '~> 0.8'
  gem.add_development_dependency 'vcr', '> 2'
  gem.add_development_dependency 'webmock', '> 2'
  gem.add_development_dependency 'dotenv', '~> 2.2', '>= 2.2.1'

end
