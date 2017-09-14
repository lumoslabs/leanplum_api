describe LeanplumApi do
  context 'configuration' do
    after(:each) do
      LeanplumApi.reset!
    end

    it 'should have a default configuration' do
      expect(LeanplumApi.configuration.api_version.is_a?(String)).to eq(true)
    end

    it 'should allow configuration' do
      LeanplumApi.configure do |config|
        config.production_key = 'new_client_key'
        config.app_id = 'new_app_id'
        config.validate_response = false
      end

      expect(LeanplumApi.configuration.production_key).to eq('new_client_key')
      expect(LeanplumApi.configuration.app_id).to eq('new_app_id')
      expect(LeanplumApi.configuration.validate_response).to be false
      expect(LeanplumApi.configuration.api_version).to eq(LeanplumApi::Configuration::DEFAULT_LEANPLUM_API_VERSION)
    end
  end
end
