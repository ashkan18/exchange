require 'rails_helper'
require 'support/gravity_helper'

describe GravityService, type: :services do
  let(:partner_id) { 'partner-1' }
  let(:partner) { { _id: 'partner-1', billing_location_id: 'location-1' } }
  describe '#get_partner' do
    it 'calls the /partner endpoint' do
      allow(Adapters::GravityV1).to receive(:get).with("/partner/#{partner_id}/all")
      GravityService.get_partner(partner_id)
      expect(Adapters::GravityV1).to have_received(:get).with("/partner/#{partner_id}/all")
    end

    context 'with failed gravity call' do
      before do
        stub_request(:get, %r{partner\/#{partner_id}}).to_return(status: 404, body: { error: 'not found' }.to_json)
      end
      it 'raises error' do
        expect do
          GravityService.get_partner(partner_id)
        end.to raise_error do |error|
          expect(error).to be_a Errors::ValidationError
          expect(error.code).to eq :unknown_partner
        end
      end
    end
  end

  describe '#get_partner_location' do
    let(:valid_location) { { country: 'US', state: 'NY', postal_code: '12345' } }
    let(:invalid_location) { { country: 'US', state: 'Floridada' } }
    before do
      allow(GravityService).to receive(:get_partner).and_return(partner)
    end
    it 'fetches the partner' do
      expect(GravityService).to receive(:get_partner).with(partner_id)
      allow(Adapters::GravityV1).to receive(:get).with("/partner/#{partner_id}/location/#{partner[:billing_location_id]}").and_return(valid_location)
      GravityService.get_partner_location(partner_id)
    end
    it 'calls the correct location Gravity endpoint' do
      expect(Adapters::GravityV1).to receive(:get).with("/partner/#{partner_id}/location/#{partner[:billing_location_id]}").and_return(valid_location)
      GravityService.get_partner_location(partner_id)
    end
    context 'with a valid partner location' do
      it 'returns a new address' do
        allow(Adapters::GravityV1).to receive(:get).with("/partner/#{partner_id}/location/#{partner[:billing_location_id]}").and_return(valid_location)
        expect(GravityService.get_partner_location(partner_id)).to be_a Address
      end
    end
    context 'with an invalid partner location' do
      it 'rescues AddressError and raises ValidationError' do
        allow(Adapters::GravityV1).to receive(:get).with("/partner/#{partner_id}/location/#{partner[:billing_location_id]}").and_return(invalid_location)
        expect { GravityService.get_partner_location(partner_id) }.to raise_error do |error|
          expect(error).to be_a Errors::ValidationError
          expect(error.code).to eq :invalid_seller_address
          expect(error.data[:partner_id]).to eq partner_id
        end
      end
    end
  end

  describe '#get_merchant_account' do
    let(:partner_merchant_accounts) { [{ external_id: 'ma-1' }, { external_id: 'some_account' }] }
    context 'with merchant account' do
      before do
        allow(Adapters::GravityV1).to receive(:get).with('/merchant_accounts', params: { partner_id: partner_id }).and_return(partner_merchant_accounts)
      end
      it 'calls the /merchant_accounts Gravity endpoint' do
        GravityService.get_merchant_account(partner_id)
        expect(Adapters::GravityV1).to have_received(:get).with('/merchant_accounts', params: { partner_id: partner_id })
      end
      it "returns the first merchant account of the partner's merchant accounts" do
        result = GravityService.get_merchant_account(partner_id)
        expect(result).to be(partner_merchant_accounts.first)
      end
    end

    it 'raises an error if the partner does not have a merchant account' do
      allow(Adapters::GravityV1).to receive(:get).with('/merchant_accounts', params: { partner_id: partner_id }).and_return([])
      expect { GravityService.get_merchant_account(partner_id) }.to raise_error do |error|
        expect(error).to be_a(Errors::InternalError)
        expect(error.type).to eq :internal
        expect(error.code).to eq :gravity
      end
    end

    context 'with failed gravity call' do
      before do
        stub_request(:get, /merchant_accounts\?partner_id=#{partner_id}/).to_return(status: 404, body: { error: 'not found' }.to_json)
      end
      it 'raises error' do
        expect do
          GravityService.get_merchant_account(partner_id)
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
end
