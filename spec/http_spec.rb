require 'spec_helper'

describe LeanplumApi::Connections::Production do
  context 'regular mode' do
    it 'should build the right multi url' do
      http = described_class.new
      expect(http.send(:authed_multi_param_string)).to eq(
        "appId=#{LeanplumApi.configuration.app_id}&clientKey=#{LeanplumApi.configuration.production_key}&apiVersion=1.0.6&devMode=false&action=multi&time=#{Time.now.utc.strftime('%s')}"
      )
    end
  end

  context 'devMode' do
    around(:all) do |example|
      LeanplumApi.configure { |c| c.developer_mode = true }
      example.run
      LeanplumApi.configure { |c| c.developer_mode = false }
    end

    it 'should build the right developer mode url' do
      http = described_class.new
      expect(http.send(:authed_multi_param_string)).to eq(
        "appId=#{LeanplumApi.configuration.app_id}&clientKey=#{LeanplumApi.configuration.production_key}&apiVersion=1.0.6&devMode=true&action=multi&time=#{Time.now.utc.strftime('%s')}"
      )
    end
  end
end
