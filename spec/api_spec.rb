describe LeanplumApi::API do
  let(:api) { described_class.new }
  let(:first_user_id) { 123456 }

  let(:user_id) { first_user_id }
  let(:message_id) { '5389574245449728' }
  let(:device_id) { 'fu123' }

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
      deviceId: device_id,
      appVersion: 'x42x',
      deviceModel: 'p0d',
      create_date: '2018-01-01'.to_date
    }
  end

  context 'devices' do
    it 'build_device_attributes_hash' do
      expect(api.send(:build_device_attributes_hash, device)).to eq(
        deviceId: device[:deviceId],
        action: described_class::SET_DEVICE_ATTRIBUTES,
        deviceAttributes: api.send(:fix_iso8601, device.except(:deviceId))
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
    let(:unsubscribe_categories) {Hash(unsubscribeCategoriesToAdd: 'foo', unsubscribeCategoriesToRemove: 'bar', unsubscribeChannelsToAdd: 'baz', unsubscribeChannelsToRemove: 'biz')}
    let(:user_with_unsubscribe_categories) { user.merge(unsubscribe_categories) }

    context '#extract_user_hash_attributes!' do
      let(:extract_attributes) do
        {
          userId: first_user_id
        }
      end

      it 'builds the right hash' do
        expect(api.send(:extract_user_hash_attributes!, user)).to eq(extract_attributes)
      end

      it 'builds the right hash with categories' do
        expect(api.send(:extract_user_hash_attributes!, user_with_unsubscribe_categories)).to eq(extract_attributes.merge(unsubscribe_categories))
      end
    end

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

      context 'with unsubscribe categories' do
        it 'builds the right hash' do
          expect(api.send(:build_user_attributes_hash, user_with_unsubscribe_categories)).to eq(built_attributes.merge(unsubscribe_categories))
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

  context 'messages' do
    # let(:device) {
    #   VCR.use_cassette('set_device_attributes_device') do
    #     api.set_device_attributes(devices)
    #   end
    # }
    #
    # let(:user) {
    #   VCR.use_cassette('set_user_attributes_users') do
    #     api.set_user_attributes(users)
    #   end
    # }

    let(:spock) {
      VCR.use_cassette('spock') do
        api.set_user_attributes(
          [{
             user_id: "spock",
             first_name: "Spock",
             gender: "m",
             email: "spock@ufop.org",
             create_date: "2018-01-01".to_date
          }]
        )
      end
    }

    describe '#get_newsfeed_messages' do
      let(:newsfeed_response) { YAML.load_file('spec/fixtures/webmock/get_newsfeed_messages.yml') }
      let(:messages) { newsfeed_response['response'].first['newsfeedMessages'] }
      let(:headers) {{'Content-Type' => 'application/json'}}
      before do
        WebMock.stub_request(:get, /www.leanplum.com.*getNewsfeedMessages.*deviceId.*#{device_id}/).to_return(
          body: newsfeed_response.to_json,
          headers: headers,
          status: 200,
        )
      end
      it 'responds with the associated newsfeed messages' do
        expect(api.get_newsfeed_messages(deviceId: device_id).length)
          .to eq messages.count
      end
    end

    describe '#send_message' do
      it 'requires message_id' do
        expect { api.send_message(user_id: user_id) }.to raise_error(ArgumentError, "missing keyword: message_id")
      end

      it 'requires user_id or user_ids' do
        expect { api.send_message(message_id: message_id) }.to raise_error(ArgumentError, "missing keyword: user_id")
      end

      it 'sends a message to Leanplum' do
        user
        response = VCR.use_cassette('send_message') do
          api.send_message(message_id: message_id, user_id: user_id)
        end
        expect(response.size).to eq 1
        response = response.first
        expect(response['success']).to eq true
        expect(response['error']).to be_blank
      end

      it 'sends a message to Leanplum using device_id' do
        user
        device
        response = VCR.use_cassette('send_message_with_device_id') do
          api.send_message(message_id: message_id, user_id: user_id, device_id: device_id)
        end
        expect(response.size).to eq 1
        response = response.first
        expect(response['success']).to eq true
        expect(response['error']).to be_blank
      end

      it 'accepts a values JSON object' do
        response = VCR.use_cassette('send_message_with_values') do
          api.send_message(message_id: message_id, user_id: user_id, values: {foo: "bar", baz: "fizz"})
        end
        expect(response.size).to eq 1
        response = response.first
        expect(response['success']).to eq true
        expect(response['error']).to be_blank
      end

      it "receives the expected error when message_id does not exist" do
        response = VCR.use_cassette('send_message_with_invalid_message_id') do
          api.send_message(message_id: "thisisaninvalidmessageid", user_id: user_id)
        end
        expect(response.size).to eq 1
        response = response.first
        expect(response['success']).to eq true
        expect(response['warning']['message']).to eq "Message entity not found"
        expect(response['messagesSent']).to be_blank
        expect(response['error']).to be_blank
      end

      it "receives the expected error when user_id is passed in but does not exist" do
        response = VCR.use_cassette('send_message_with_invalid_user_id') do
          api.send_message(message_id: message_id, user_id: "thisisaninvaliduserid")
        end
        expect(response.size).to eq 1
        response = response.first
        expect(response['success']).to eq true
        expect(response['warning']['message']).to eq "User not found; request skipped."
        expect(response['messagesSent']).to be_blank
        expect(response['error']).to be_blank
      end
    end

    describe '#send_messages' do
      it "requires message_id" do
        expect { api.send_messages(users: [{id: user_id}]) }.to raise_error(ArgumentError, "missing keyword: message_id")
      end

      it "requires users" do
        expect { api.send_messages(message_id: message_id) }.to raise_error(ArgumentError, "missing keyword: users")
      end

      it "succesfully sends a message to Leanplum's API" do
        user
        response = VCR.use_cassette('send_messages') do
          api.send_messages(message_id: message_id, users: [{id: user_id}])
        end
        expect(response.size).to eq 1
        response = response.first
        expect(response['success']).to eq true
        expect(response['error']).to be_blank
      end

      it "succesfully sends a message to Leanplum's API using device_id" do
        user
        device
        response = VCR.use_cassette('send_messages_with_device_id') do
          api.send_messages(message_id: message_id, users: [{id: user_id, device_id: device_id}])
        end
        expect(response.size).to eq 1
        response = response.first
        expect(response['success']).to eq true
        expect(response['error']).to be_blank
      end

      it "succesfully sends multiple messages" do
        user
        spock
        response = VCR.use_cassette('send_multiple_messages') do
          api.send_messages(message_id: message_id, users: [{id: user_id}, {id: "spock"}])
        end
        expect(response.size).to eq 2
        response.each do |r|
          expect(r['success']).to eq true
          expect(r['error']).to be_blank
        end
      end

      it "accepts a values JSON object" do
        response = VCR.use_cassette('send_messages_with_values') do
          api.send_messages(message_id: message_id, users: [{id: user_id, values: {foo: "bar", baz: "fizz"}}])
        end
        expect(response.size).to eq 1
        response = response.first
        expect(response['success']).to eq true
        expect(response['error']).to be_blank
      end

      it "receives the expected error when message_id does not exist" do
        response = VCR.use_cassette('send_messages_with_invalid_message_id') do
          api.send_messages(message_id: "thisisaninvalidmessageid", users: [{id: user_id}])
        end
        expect(response.size).to eq 1
        response = response.first
        expect(response['success']).to eq true
        expect(response['warning']['message']).to eq "Message entity not found"
        expect(response['messagesSent']).to be_blank
        expect(response['error']).to be_blank
      end

      it "receives the expected error when users includes an invalid id" do
        response = VCR.use_cassette('send_messages_with_invalid_user_id') do
          api.send_messages(message_id: message_id, users: [{id: "thisisaninvaliduserid"}])
        end
        expect(response.size).to eq 1
        response = response.first
        expect(response['success']).to eq true
        expect(response['warning']['message']).to eq "User not found; request skipped."
        expect(response['messagesSent']).to be_blank
        expect(response['error']).to be_blank
      end

      it "does not process if passing in more than 50 users" do
        expect { api.send_messages(message_id: message_id, users: Array.new(51)) }.to raise_error(ArgumentError)
      end

      it "does not process if even one user does not include an id" do
        expect { api.send_messages(message_id: message_id, users: [{}]) }.to raise_error(ArgumentError, "users failed validation. User is missing `:id` key: {}")
      end

      it "does not process if even one user includes an invalid values hash" do
        expect { api.send_messages(message_id: message_id, users: [{id: user_id, values: "Invalid"}]) }.to raise_error(ArgumentError, "users failed validation. user[:values] must be a hash: {:id=>123456, :values=>\"Invalid\"}")
      end
    end
  end

  context 'event tracking' do
    let(:timestamp) { '2015-05-01 01:02:03' }
    let(:purchase) { 'purchase' }
    let(:events) do
      [
        {
          user_id: first_user_id,
          event: purchase,
          time: last_event_time,
          some_timestamp: timestamp
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

        # @NOTE: this spec requires setup of events in LP.
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

    context '#user_devices' do
      it 'should get user devices for this user' do
        VCR.use_cassette('export_user') do
          expect(api.user_devices(first_user_id).first['deviceId']).to eq(device_id)
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
            expect(messages = api.get_messages).to be_a(Array)
            expect(messages.size).to be > 1
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
