require 'spec_helper'

describe LeanplumApi::API do
  let(:api) { LeanplumApi::API.new }
  let(:users) do
    [{
      user_id: 123456,
      first_name: 'Mike',
      last_name: 'Jones',
      gender: 'm',
      email: 'still_tippin@test.com',
      create_date: '2010-01-01'.to_date
    }]
  end
  let(:first_user_id) { users.first[:user_id] }

  context 'users' do
    it 'build_user_attributes_hash' do
      expect(api.send(:build_user_attributes_hash, users.first)).to eq({
        'userId' => 123456,
        'action' => 'setUserAttributes',
        'userAttributes' => HashWithIndifferentAccess.new(
          first_name: 'Mike',
          last_name: 'Jones',
          gender: 'm',
          email: 'still_tippin@test.com',
          create_date: '2010-01-01'
        )
      })
    end

    context 'set_user_attributes' do
      context 'valid request' do
        it 'should successfully set user attributes' do
          VCR.use_cassette('set_user_attributes') do
            expect { api.set_user_attributes(users) }.to_not raise_error
          end
        end
      end

      context 'invalid request' do
        let(:broken_users) { users + [{ first_name: 'Moe' }] }

        it 'should raise an error' do
          VCR.use_cassette('set_user_attributes_broken') do
            expect{ api.set_user_attributes(broken_users) }.to raise_error(/No device_id or user_id in hash/)
          end
        end
      end
    end

    context 'export_user' do
      it 'should get user attributes for this user' do
        VCR.use_cassette('export_user') do
          user_info = api.export_user(first_user_id)
          user_info.keys.each do |k|
            if users.first[k.to_sym].is_a?(Date) || users.first[k.to_sym].is_a?(DateTime)
              expect(user_info[k]).to eq(users.first[k.to_sym].strftime('%Y-%m-%d'))
            else
              expect(user_info[k]).to eq(users.first[k.to_sym])
            end
          end
        end
      end
    end

    context 'export_users' do
      it 'should export users'
    end

    context 'reset_anomalous_users' do
      it 'should successfully call setUserAttributes with resetAnomalies' do
        VCR.use_cassette('reset_anomalous_user') do
          expect { api.reset_anomalous_users(first_user_id) }.to_not raise_error
        end
      end
    end
  end

  context 'events' do
    let(:events) do
      [
        {
          user_id: 12345,
          event: 'purchase',
          time: Time.now.utc,
          'some_timestamp' => '2015-05-01 01:02:03'
        },
        {
          user_id: 54321,
          event: 'purchase_page_view',
          time: Time.now.utc - 10.minutes
        }
      ]
    end

    context '#build_event_attributes_hash' do
      it 'builds the events from a deprecated format' do
        expect(api.send(:build_event_attributes_hash, events.first)).to eq({
          'userId' => 12345,
          'time' => Time.now.utc.strftime('%s'),
          'action' => 'track',
          'event' => 'purchase',
          'params' => { 'some_timestamp'=>'2015-05-01 01:02:03' }
        })
      end

      it 'builds the events from a deprecated format' do
        deprecated_format_event = events.last.merge(params: { 'some_timestamp' => '2015-05-01 01:02:03' })
        expect(api.send(:build_event_attributes_hash, events.first)).to eq({
          'userId' => 12345,
          'time' => Time.now.utc.strftime('%s'),
          'action' => 'track',
          'event' => 'purchase',
          'params' => { 'some_timestamp'=>'2015-05-01 01:02:03' }
        })
      end
    end

    context 'without user attributes' do
      context 'valid request' do
        it 'should successfully track events' do
          VCR.use_cassette('track_events') do
            expect { api.track_events(events) }.to_not raise_error
          end
        end
      end

      context 'invalid request' do
        let(:broken_events) { events + [{ event: 'no_user_id_event' }] }

        it 'should raise an error' do
          VCR.use_cassette('track_events_broken') do
            expect { api.track_events(broken_events) }.to raise_error(/No device_id or user_id in hash/)
          end
        end
      end

      context 'anomalous data force_anomalous_override' do
        it 'should successfully force the anomalous data override events' do
          VCR.use_cassette('track_events_anomaly_overrider') do
            expect { api.track_events(events, force_anomalous_override: true) }.to_not raise_error
          end
        end
      end
    end

    context 'along with user attributes' do
      it 'should work' do
        VCR.use_cassette('track_events_and_attributes') do
          expect { api.track_multi(events, users) }.to_not raise_error
        end
      end
    end
  end

  # Data export and content read only endpoints forbid use of devMode
  context 'non devMode methods' do
    around(:all) do |example|
      LeanplumApi.configure { |c| c.developer_mode = false }
      example.run
      LeanplumApi.configure { |c| c.developer_mode = true }
    end

    context 'data export methods' do
      around(:all) do |example|
        LeanplumApi.configure do |c|
          c.developer_mode = false
        end
        example.run
        LeanplumApi.configure { |c| c.developer_mode = true }
      end

      context 'export_data' do
        context 'regular export' do
          it 'should request a data export job with a starttime' do
            VCR.use_cassette('export_data') do
              expect { api.export_data(Time.at(1438660800).utc) }.to raise_error LeanplumApi::ResourceNotFoundError
            end
          end

          it 'should request a data export job with start and end dates' do
            VCR.use_cassette('export_data_dates') do
              expect { api.export_data(Date.new(2015, 9, 5), Date.new(2015, 9, 6)) }.to raise_error LeanplumApi::ResourceNotFoundError
            end
          end
        end

        context 's3 export' do
          let(:s3_bucket_name) { 'bucket' }
          let(:s3_access_key) { 's3_access_key' }
          let(:s3_access_id) { 's3_access_id' }

          it 'should request an S3 export'
        end
      end

      context 'get_export_results' do
        it 'should get a status for a data export job' do
          VCR.use_cassette('get_export_results') do
            response = api.get_export_results('export_4727756026281984_2904941266315269120')
            expect(response).to eq({
              files: ['https://leanplum_export.storage.googleapis.com/export-4727756026281984-d5969d55-f242-48a6-85a3-165af08e2306-output-0'],
              number_of_bytes: 36590,
              number_of_sessions: 101,
              state: LeanplumApi::API::EXPORT_FINISHED,
              s3_copy_status: nil
            })
          end
        end
      end
    end

    context 'content read only methods' do
      context 'ab tests' do
        it 'gets ab tests' do
          VCR.use_cassette('get_ab_tests') do
            expect(api.get_ab_tests).to eq([])
          end
        end

        it 'gets an ab test' do
          VCR.use_cassette('get_ab_test') do
            expect(api.get_ab_tests(1)).to eq([])
          end
        end
      end

      context 'messages' do
        it 'gets messages' do
          VCR.use_cassette('get_messages') do
            expect(api.get_messages).to eq([{
              "id" => 5670583287676928,
              "created" => 1440091595.799,
              "name" => "New Message",
              "active" => false,
              "messageType" => "Push Notification"
            }])
          end
        end

        it 'throws exception on missing message' do
          VCR.use_cassette('missing_message') do
            expect { api.get_message(1234) }.to raise_error LeanplumApi::ResourceNotFoundError
          end
        end
      end

      it 'gets vars' do
        VCR.use_cassette('get_vars') do
          vars = api.get_vars(first_user_id)
          expect(vars).to eq({ 'test_var' => 1 })
        end
      end
    end
  end
end
