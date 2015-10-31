require 'spec_helper'

describe LeanplumApi do
  context 'configuration' do
    after(:each) do
      LeanplumApi.reset!
    end

    it 'should have a default configuration' do
      expect(LeanplumApi.configuration.log_path.is_a?(String)).to eq(true)
    end

    it 'should allow configuration' do
      LeanplumApi.configure do |config|
        config.log_path = 'test/path'
        config.client_key = 'new_client_key'
        config.app_id = 'new_app_id'
      end

      expect(LeanplumApi.configuration.log_path).to eq('test/path')
      expect(LeanplumApi.configuration.client_key).to eq('new_client_key')
      expect(LeanplumApi.configuration.app_id).to eq('new_app_id')
      expect(LeanplumApi.configuration.api_version).to eq(LeanplumApi::Configuration::DEFAULT_LEANPLUM_API_VERSION)
    end
  end
end
