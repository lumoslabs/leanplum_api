require 'spec_helper'

describe LeanplumApi::Connection do
  let(:http) { described_class.new(LeanplumApi.configuration.production_key) }

  def argument_string(dev_mode)
    "appId=#{LeanplumApi.configuration.app_id}&clientKey=#{LeanplumApi.configuration.production_key}&apiVersion=1.0.6&devMode=#{dev_mode}&action=multi&time=#{Time.now.utc.strftime('%s')}"
  end

  context 'regular mode' do
    before do
      LeanplumApi.configure { |c| c.developer_mode = false }
    end

    it 'should build the right multi url' do
      expect(http.send(:authed_multi_param_string)).to eq(argument_string(false))
    end
  end

  context 'devMode' do
    around(:all) do |example|
      LeanplumApi.configure { |c| c.developer_mode = true }
      example.run
      LeanplumApi.configure { |c| c.developer_mode = false }
    end

    it 'should build the right developer mode url' do
      expect(http.send(:authed_multi_param_string)).to eq(argument_string(true))
    end
  end
end
