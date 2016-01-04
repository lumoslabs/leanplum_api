require 'faraday'
require 'active_support/all'

path = File.join(File.expand_path(File.dirname(__FILE__)), 'leanplum_api')
Dir["#{path}/*.rb"].each { |f| require f }
Dir["#{path}/**/*.rb"].each { |f| require f }

module LeanplumApi
end
