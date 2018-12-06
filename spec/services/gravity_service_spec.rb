require 'rails_helper'
require 'support/gravity_helper'

describe GravityService, type: :services do
  let(:seller_id) { 'partner-1' }
  let(:partner) { { _id: 'partner-1', billing_location_id: 'location-1' } }
  describe '#fetch_partner' do
    it 'calls the /partner endpoint' do
      allow(Adapters::GravityV1).to receive(:get).with("/partner/#{seller_id}/all")
      GravityService.fetch_partner(seller_id)
      expect(Adapters::GravityV1).to have_received(:get).with("/partner/#{seller_id}/all")
    end

    context 'with failed gravity call' do
      before do
        stub_request(:get, %r{partner\/#{seller_id}}).to_return(status: 404, body: { error: 'not found' }.to_json)
      end
      it 'raises error' do
        expect do
          GravityService.fetch_partner(seller_id)
        end.to raise_error do |error|
          expect(error).to be_a Errors::ValidationError
          expect(error.code).to eq :unknown_partner
        end
      end
    end
  end

  describe '#fetch_partner_locations' do
    let(:valid_locations) { [{ country: 'US', state: 'NY', postal_code: '12345' }, { country: 'US', state: 'FL', postal_code: '67890' }] }
    let(:invalid_location) { [{ country: 'US', state: 'Floridada' }] }
    it 'calls the correct location Gravity endpoint' do
      expect(Adapters::GravityV1).to receive(:get).with("/partner/#{seller_id}/locations?private=true").and_return(valid_locations)
      GravityService.fetch_partner_locations(seller_id)
    end
    context 'with at least one partner location' do
      context 'with valid partner locations' do
        it 'returns new addresses for each location' do
          allow(Adapters::GravityV1).to receive(:get).with("/partner/#{seller_id}/locations?private=true").and_return(valid_locations)
          partner_addresses = GravityService.fetch_partner_locations(seller_id)
          partner_addresses.each { |ad| expect(ad).to be_a Address }
        end
      end
    end
    context 'with no partner locations' do
      it 'raises error' do
        allow(Adapters::GravityV1).to receive(:get).with("/partner/#{seller_id}/locations?private=true").and_return([])
        expect { GravityService.fetch_partner_locations(seller_id) }.to raise_error do |error|
          expect(error).to be_a Errors::ValidationError
          expect(error.code).to eq :missing_partner_location
          expect(error.data[:partner_id]).to eq seller_id
        end
      end
    end
  end

  describe '#get_merchant_account' do
    let(:partner_merchant_accounts) { [{ external_id: 'ma-1' }, { external_id: 'some_account' }] }
    context 'with merchant account' do
      before do
        allow(Adapters::GravityV1).to receive(:get).with('/merchant_accounts', params: { partner_id: seller_id }).and_return(partner_merchant_accounts)
      end
      it 'calls the /merchant_accounts Gravity endpoint' do
        GravityService.get_merchant_account(seller_id)
        expect(Adapters::GravityV1).to have_received(:get).with('/merchant_accounts', params: { partner_id: seller_id })
      end
      it "returns the first merchant account of the partner's merchant accounts" do
        result = GravityService.get_merchant_account(seller_id)
        expect(result).to be(partner_merchant_accounts.first)
      end
    end

    it 'raises an error if the partner does not have a merchant account' do
      allow(Adapters::GravityV1).to receive(:get).with('/merchant_accounts', params: { partner_id: seller_id }).and_return([])
      expect { GravityService.get_merchant_account(seller_id) }.to raise_error do |error|
        expect(error).to be_a(Errors::InternalError)
        expect(error.type).to eq :internal
        expect(error.code).to eq :gravity
      end
    end

    context 'with failed gravity call' do
      before do
        stub_request(:get, /merchant_accounts\?partner_id=#{seller_id}/).to_return(status: 404, body: { error: 'not found' }.to_json)
      end
      it 'raises error' do
        expect do
          GravityService.get_merchant_account(seller_id)
        end.to raise_error do |error|
          expect(error).to be_a Errors::ValidationError
          expect(error.code).to eq :missing_merchant_account
        end
      end
    end
  end

  describe '#get_credit_card' do
    let(:credit_card_id) { 'cc-1' }
    let(:credit_card) { { external_id: 'card-1', customer_account: { external_id: 'cust-1' }, deactivated_at: nil } }
    it 'calls the /credit_card Gravity endpoint' do
      allow(Adapters::GravityV1).to receive(:get).with("/credit_card/#{credit_card_id}").and_return(credit_card)
      GravityService.get_credit_card(credit_card_id)
      expect(Adapters::GravityV1).to have_received(:get).with("/credit_card/#{credit_card_id}")
    end

    context 'with failed gravity call' do
      before do
        stub_request(:get, %r{credit_card\/#{credit_card_id}}).to_return(status: 404, body: { error: 'not found' }.to_json)
      end
      it 'raises error' do
        expect do
          GravityService.get_credit_card(credit_card_id)
        end.to raise_error do |error|
          expect(error).to be_a Errors::ValidationError
          expect(error.code).to eq :credit_card_not_found
        end
      end
    end
  end

  describe '#get_artwork' do
    let(:artwork_id) { 'some-id' }
    it 'calls the /artwork endpoint' do
      allow(Adapters::GravityV1).to receive(:get).with("/artwork/#{artwork_id}")
      GravityService.get_artwork(artwork_id)
      expect(Adapters::GravityV1).to have_received(:get).with("/artwork/#{artwork_id}")
    end
    context 'with failed gravity call' do
      it 'returns nil' do
        expect(Adapters::GravityV1).to receive(:get).and_raise(Adapters::GravityError, 'timeout')
        expect(GravityService.get_artwork(artwork_id)).to be_nil
      end
    end
  end

  describe '#get_user' do
    let(:user_id) { 'some-id' }
    it 'calls the /userid endpoint' do
      allow(Adapters::GravityV1).to receive(:get).with("/user/#{user_id}")
      GravityService.get_user(user_id)
      expect(Adapters::GravityV1).to have_received(:get).with("/user/#{user_id}")
    end
    context 'with failed gravity call' do
      it 'returns nil' do
        expect(Adapters::GravityV1).to receive(:get).and_raise(Adapters::GravityError, 'timeout')
        expect(GravityService.get_user(user_id)).to be_nil
      end
    end
  end
end
