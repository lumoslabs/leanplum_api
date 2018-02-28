describe LeanplumApi::API do
  let(:api) { described_class.new }
  let(:first_user_id) { 123456 }
  let(:first_event_time) { Time.now.utc - 1.day }
  let(:last_event_time) { Time.now.utc }
  let(:users) { [user] }
  let(:devices) { [device] }
  let(:user) do
    {
      user_id: first_user_id,
      first_name: 'Mike',
      last_name: 'Jones',
      gender: 'm',
      email: 'still_tippin@test.com',
      create_date: '2010-01-01'.to_date,
      is_tipping: true
    }
  end
  let(:device) do
    {
      device_id: 'fu123',
      appVersion: 'x42x',
      deviceModel: 'p0d',
      create_date: '2018-01-01'.to_date
    }
  end

  context 'devices' do
    it 'build_device_attributes_hash' do
      expect(api.send(:build_device_attributes_hash, device)).to eq(
        deviceId: device[:device_id],
        action: described_class::SET_DEVICE_ATTRIBUTES,
        deviceAttributes: api.send(:fix_iso8601, device.except(:device_id))
      )
    end

    context 'set_device_attributes' do
      it 'sets device attributes without error' do
        VCR.use_cassette('set_device_attributes') do
          expect { api.set_device_attributes(devices) }.to_not raise_error
        end
      end
    end
  end

  context 'users' do
    let(:events) { { eventName1: { count: 1, firstTime: first_event_time, lastTime: last_event_time } } }
    let(:events_with_timestamps) { Hash[events.map { |k, v| [k, api.send(:fix_seconds_since_epoch, v)] }] }
    let(:user_with_devices) { user.merge(devices: devices) }
    let(:user_with_events) { user.merge(events: events) }

    context '#build_user_attributes_hash' do
      let(:built_attributes) do
        {
          userId: first_user_id,
          action: described_class::SET_USER_ATTRIBUTES,
          userAttributes: api.send(:fix_iso8601, user.except(:user_id))
        }
      end

      it 'builds the right hash' do
        expect(api.send(:build_user_attributes_hash, user)).to eq(built_attributes)
      end

      context 'with events' do
        it 'builds the right hash' do
          expect(api.send(:build_user_attributes_hash, user_with_events)).to eq(
            built_attributes.merge(events: events_with_timestamps)
          )
        end
      end

      context 'with devices' do
        it 'builds the right hash' do
          expect(api.send(:build_user_attributes_hash, user_with_devices)).to eq(
            built_attributes.merge(devices: devices)
          )
        end
      end
    end

    context '#set_user_attributes' do
      context 'valid request' do
        it 'should successfully set user attributes' do
          VCR.use_cassette('set_user_attributes') do
            expect { api.set_user_attributes(users) }.to_not raise_error
          end
        end

        it 'should successfully set user attributes and events' do
          VCR.use_cassette('set_user_attributes_with_events') do
            expect { api.set_user_attributes([user_with_events]) }.to_not raise_error
          end
        end

        it 'should successfully set user attributes and devices' do
          VCR.use_cassette('set_user_attributes_with_devices') do
            expect { api.set_user_attributes([user_with_devices]) }.to_not raise_error
          end
        end

        it 'should successfully set user attributes and devices and events' do
          VCR.use_cassette('set_user_attributes_with_devices_and_events') do
            expect { api.set_user_attributes([user_with_devices.merge(events: events)]) }.to_not raise_error
          end
        end
      end

      context 'invalid request' do
        let(:broken_users) { users + [{ first_name: 'Moe' }] }

        it 'should raise an error' do
          expect{ api.set_user_attributes(broken_users) }.to raise_error(/No device_id or user_id in hash/)
        end
      end
    end

    context '#user_attributes' do
      let(:true_key) { 'random_true_key' }
      let(:false_key) { 'arbitrary_false_key' }
      let(:test_hash) { { 'userAttributes' => { true_key => 'TrUe', false_key => 'fALSE' } } }

      it 'should get user attributes for this user' do
        VCR.use_cassette('export_user') do
          api.user_attributes(first_user_id).each do |k, v|
            if user[k.to_sym].is_a?(Date) || user[k.to_sym].is_a?(DateTime)
              expect(v).to eq(user[k.to_sym].strftime('%Y-%m-%d'))
            else
              expect(v).to eq(user[k.to_sym])
            end
          end
        end
      end

      it 'should convert true / false strings into booleans' do
        allow(api).to receive(:export_user).and_return(test_hash)
        attributes = api.user_attributes(first_user_id)

        expect(attributes[true_key]).to eq(true)
        expect(attributes[false_key]).to eq(false)
      end

      context 'boolean looking strings' do
        let(:true_like_value) { 'truegrit' }
        let(:false_like_value) { 'whatever string ending in false' }
        let(:test_hash) { { 'userAttributes' => { true_key => true_like_value, false_key => false_like_value } } }

        it 'should not convert true / false like strings' do
          allow(api).to receive(:export_user).and_return(test_hash)
          attributes = api.user_attributes(first_user_id)

          expect(attributes[true_key]).to eq(true_like_value)
          expect(attributes[false_key]).to eq(false_like_value)
        end
      end
    end

    context '#reset_anomalous_users' do
      it 'should successfully call setUserAttributes with resetAnomalies' do
        VCR.use_cassette('reset_anomalous_user') do
          expect { api.reset_anomalous_users(first_user_id) }.to_not raise_error
        end
      end
    end

    context '#delete_user' do
      let(:user_id) { 'delete_yourself_123' }
      let(:deletable_user) { user.merge(user_id: user_id) }

      it 'should delete a user' do
        VCR.use_cassette('delete_user') do
          expect { api.set_user_attributes(deletable_user) }.to_not raise_error
          expect { api.delete_user(user_id) }.to_not raise_error
          expect { api.user_attributes(user_id) }.to raise_error(LeanplumApi::ResourceNotFoundError)
        end
      end
    end
  end

  context 'event tracking' do
    let(:timestamp) { '2015-05-01 01:02:03' }
    let(:purchase) { 'purchase' }
    let(:currency_code) { 'USD' }
    let(:purchase_value) { 10.0 }
    let(:events) do
      [
        {
          user_id: first_user_id,
          event: purchase,
          time: last_event_time,
          some_timestamp: timestamp,
          currency_code: 'USD',
          value: 10.0
        },
        {
          user_id: 54321,
          event: 'purchase_page_view',
          time: last_event_time - 10.minutes
        }
      ]
    end

    context '#build_event_attributes_hash' do
      let(:event_hash) do
        {
          userId: first_user_id,
          event: purchase,
          currencyCode: currency_code,
          value: purchase_value,
          time: last_event_time.strftime('%s').to_i,
          action: described_class::TRACK,
          params: { some_timestamp: timestamp }
        }
      end

      it 'builds the events format' do
        expect(api.send(:build_event_attributes_hash, events.first)).to eq(event_hash)
      end
    end

    context '#track_events' do
      context 'valid request' do
        it 'should successfully track session events' do
          VCR.use_cassette('track_events') do
            expect { api.track_events(events) }.to_not raise_error
          end
        end

        it 'should successfully track non session events' do
          VCR.use_cassette('track_offline_events') do
            expect do
              response = api.track_events(events, allow_offline: true)
              expect(response.map { |r| r['success'] && r['isOffline'] }.all?).to be_truthy
            end.to_not raise_error
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
        let(:old_events) { events.map { |e| e[:time] -= 2.years; e } }

        it 'should successfully force the anomalous data override events' do
          VCR.use_cassette('track_events_anomaly_overrider') do
            expect do
              response = api.track_events(old_events, force_anomalous_override: true)
              expect(response.map { |r| r['warning']['message'] }.all? { |w| w =~ /Past event detected/ }).to be true
            end.to_not raise_error
          end
        end
      end
    end

    context '#track_multi' do
      it 'tracks users and events at the same time' do
        VCR.use_cassette('track_events_and_attributes') do
          expect do
            response = api.track_multi(events: events, user_attributes: users)
            expect(response.first['success']).to be true
          end.to_not raise_error
        end
      end
    end

    context '#user_events' do
      it 'should get user events for this user' do
        VCR.use_cassette('export_user') do
          expect(api.user_events(first_user_id)[purchase].keys.sort).to eq(%w(firstTime lastTime count).sort)
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
              'id' => 5670583287676928,
              'created' => 1440091595.799,
              'name' => 'New Message',
              'active' => false,
              'messageType' => 'Push Notification'
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
        pending 'Docs are extremely unclear about what getVars and setVars even do'

        VCR.use_cassette('get_vars') do
          expect(api.get_vars(user[:user_id])).to eq({ 'test_var' => 1 })
        end
      end
    end
  end

  context 'hash utility methods' do
    let(:hash_with_times) { { not_time: 'grippin', time: last_event_time, date: last_event_time.to_date } }

    it 'turns datetimes into seconds from the epoch' do
      expect(api.send(:fix_seconds_since_epoch, hash_with_times)).to eq(
        hash_with_times.merge(time: last_event_time.strftime('%s').to_i, date: last_event_time.to_date.strftime('%s').to_i)
      )
    end

    it 'turns datetimes into iso8601 format' do
      expect(api.send(:fix_iso8601, hash_with_times)).to eq(
        hash_with_times.merge(time: last_event_time.iso8601, date: last_event_time.to_date.iso8601)
      )
    end
  end
end
