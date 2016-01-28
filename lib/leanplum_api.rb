require 'active_support/all'
require 'faraday'
require 'faraday_middleware'
require 'logger'
require 'uri'

path = File.join(File.expand_path(File.dirname(__FILE__)), 'leanplum_api')
Dir["#{path}/*.rb"].each { |f| require f }
Dir["#{path}/**/*.rb"].each { |f| require f }

module LeanplumApi
end
