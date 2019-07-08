require 'rails_helper'
require 'support/gravity_helper'

describe Api::GraphqlController, type: :request do
  describe 'create_order mutation' do
    include_context 'GraphQL Client'
    let(:artwork_id) { 'artwork-id' }
    let(:edition_set_id) { 'edition-set-id' }
    let(:seller_id) { 'gravity-partner-id' }
    let(:quantity) { 2 }
    let(:mutation_input) do
      {
        artworkId: artwork_id,
        editionSetId: edition_set_id,
        quantity: quantity
      }
    end
    let(:mutation) do
      <<-GRAPHQL
        mutation($input: CreateOrderWithArtworkInput!) {
          createOrderWithArtwork(input: $input) {
            orderOrError {
              ... on OrderWithMutationSuccess {
                order {
                  id
                  buyer {
                    ... on Partner {
                      id
                    }
                  }
                  seller {
                    ... on User {
                      id
                    }
                  }
                }
              }
              ... on OrderWithMutationFailure {
                error {
                  code
                  data
                  type
                }
              }
            }
          }
        }
      GRAPHQL
    end

    context 'with proper token' do
      context 'without artworkId' do
        it 'requires artwork id' do
          expect do
            client.execute(mutation, input: { quantity: 1 })
          end.to raise_error do |error|
            expect(error).to be_a(Graphlient::Errors::GraphQLError)
            expect(error.message).to match(/was provided invalid value for artworkId/)
          end
        end
      end

      context 'with failed artwork fetch' do
        before do
          expect(Adapters::GravityV1).to receive(:get).with('/artwork/artwork-id').and_raise(Adapters::GravityError.new('Timeout'))
        end
        it 'does not create order and returns proper error' do
          expect do
            response = client.execute(mutation, input: mutation_input)
            expect(response.data.create_order_with_artwork.order_or_error).not_to respond_to(:order)
            expect(response.data.create_order_with_artwork.order_or_error.error).not_to be_nil

            expect(response.data.create_order_with_artwork.order_or_error.error.type).to eq 'validation'
            expect(response.data.create_order_with_artwork.order_or_error.error.code).to eq 'unknown_artwork'
          end.to change(Order, :count).by(0).and change(LineItem, :count).by(0)
        end
      end

      context 'with successful artwork fetch' do
        let(:artwork) { gravity_v1_artwork }
        before do
          expect(Gravity).to receive(:get_artwork).with(artwork_id).and_return(artwork)
        end
        context 'artwork with one edition set' do
          context 'without passing edition_set_id' do
            it 'uses artworks edition set' do
              expect do
                response = client.execute(mutation, input: mutation_input.except(:editionSetId))
                expect(response.data.create_order_with_artwork.order_or_error.order.id).not_to be_nil
                expect(response.data.create_order_with_artwork.order_or_error).not_to respond_to(:error)
                order = Order.find(response.data.create_order_with_artwork.order_or_error.order.id)
                expect(order.mode).to eq Order::BUY
                expect(order.currency_code).to eq 'USD'
                expect(order.buyer_id).to eq jwt_user_id
                expect(order.seller_id).to eq seller_id
                expect(order.seller_type).to eq 'gallery'
                expect(order.line_items.count).to eq 1
                expect(order.line_items.first.list_price_cents).to eq 4200_42
                expect(order.line_items.first.artwork_id).to eq 'artwork-id'
                expect(order.line_items.first.edition_set_id).to eq 'edition-set-id'
                expect(order.line_items.first.quantity).to eq 2
              end.to change(Order, :count).by(1).and change(LineItem, :count).by(1)
            end
          end
          context 'with passing edition set id' do
            it 'creates order with edition_set price' do
              expect do
                response = client.execute(mutation, input: mutation_input)
                expect(response.data.create_order_with_artwork.order_or_error.order.id).not_to be_nil
                expect(response.data.create_order_with_artwork.order_or_error).not_to respond_to(:error)

                order = Order.find(response.data.create_order_with_artwork.order_or_error.order.id)
                expect(order.mode).to eq Order::BUY
                expect(order.currency_code).to eq 'USD'
                expect(order.buyer_id).to eq jwt_user_id
                expect(order.seller_id).to eq seller_id
                expect(order.line_items.count).to eq 1
                expect(order.line_items.first.list_price_cents).to eq 4200_42
                expect(order.line_items.first.artwork_id).to eq 'artwork-id'
                expect(order.line_items.first.edition_set_id).to eq 'edition-set-id'
                expect(order.line_items.first.quantity).to eq 2
              end.to change(Order, :count).by(1).and change(LineItem, :count).by(1)
            end
          end
        end

        context 'artwork with more than one edition set' do
          let(:edition_sets) do
            [{
              id: 'edition-set-id',
              forsale: true,
              sold: false,
              price: '$4200',
              price_listed: 4200.42,
              price_currency: 'USD',
              acquireable: false,
              dimensions: { in: '44 × 30 1/2 in', cm: '111.8 × 77.5 cm' },
              editions: 'Edition of 15',
              display_price_currency: 'USD (United States Dollar)',
              availability: 'for sale'
            }, {
              id: 'edition-set-id2',
              forsale: true,
              sold: false,
              price: '$4400',
              price_listed: 4200.42,
              price_currency: 'USD',
              acquireable: false,
              dimensions: { in: '44 × 30 1/2 in', cm: '111.8 × 77.5 cm' },
              editions: 'Edition of 15',
              display_price_currency: 'USD (United States Dollar)',
              availability: 'for sale'
            }]
          end
          let(:artwork) { gravity_v1_artwork(edition_sets: edition_sets) }

          context 'without setting edition_set_id' do
            it 'raises error' do
              expect do
                client.execute(mutation, input: mutation_input.except(:editionSetId))
              end.to change(Order, :count).by(0).and change(LineItem, :count).by(0)
            end
          end
          context 'with editionSetId' do
            it 'creates order with edition_set price' do
              expect do
                response = client.execute(mutation, input: mutation_input)
                expect(response.data.create_order_with_artwork.order_or_error.order.id).not_to be_nil
                expect(response.data.create_order_with_artwork.order_or_error).not_to respond_to(:error)

                order = Order.find(response.data.create_order_with_artwork.order_or_error.order.id)
                expect(order.mode).to eq Order::BUY
                expect(order.currency_code).to eq 'USD'
                expect(order.buyer_id).to eq jwt_user_id
                expect(order.seller_id).to eq seller_id
                expect(order.line_items.count).to eq 1
                expect(order.line_items.first.list_price_cents).to eq 4200_42
                expect(order.line_items.first.artwork_id).to eq 'artwork-id'
                expect(order.line_items.first.edition_set_id).to eq 'edition-set-id'
                expect(order.line_items.first.quantity).to eq 2
                expect(order.original_user_agent).to eq user_agent
                expect(order.original_user_ip).to eq user_ip
              end.to change(Order, :count).by(1).and change(LineItem, :count).by(1)
            end
          end

          context 'with specific analytics fields' do
            let(:user_agent) { '2340hjf209' }
            let(:user_ip) { '3209uj2' }

            it 'tracks the fields correctly' do
              expect do
                response = client.execute(mutation, input: mutation_input)
                order = Order.find(response.data.create_order_with_artwork.order_or_error.order.id)
                expect(order.original_user_agent).to eq '2340hjf209'
                expect(order.original_user_ip).to eq '3209uj2'
              end.to change(Order, :count).by(1).and change(LineItem, :count).by(1)
            end
          end
        end

        context 'artwork with empty array edition set' do
          let(:artwork) { gravity_v1_artwork(edition_sets: []) }
          it 'creates order with artwork price' do
            expect do
              response = client.execute(mutation, input: mutation_input.except(:editionSetId))
              expect(response.data.create_order_with_artwork.order_or_error.order.id).not_to be_nil
              expect(response.data.create_order_with_artwork.order_or_error).not_to respond_to(:error)
              order = Order.find(response.data.create_order_with_artwork.order_or_error.order.id)
              expect(order.mode).to eq Order::BUY
              expect(order.currency_code).to eq 'USD'
              expect(order.buyer_id).to eq jwt_user_id
              expect(order.seller_id).to eq seller_id
              expect(order.line_items.count).to eq 1
              expect(order.line_items.first.list_price_cents).to eq 5400_12
              expect(order.line_items.first.artwork_id).to eq 'artwork-id'
              expect(order.line_items.first.edition_set_id).to be_nil
              expect(order.line_items.first.quantity).to eq 2
            end.to change(Order, :count).by(1).and change(LineItem, :count).by(1)
          end
        end

        context 'artwork without edition set' do
          let(:artwork) { gravity_v1_artwork(edition_sets: nil) }
          it 'creates order with artwork price' do
            expect do
              response = client.execute(mutation, input: mutation_input.except(:editionSetId))
              expect(response.data.create_order_with_artwork.order_or_error.order.id).not_to be_nil
              expect(response.data.create_order_with_artwork.order_or_error).not_to respond_to(:error)
              order = Order.find(response.data.create_order_with_artwork.order_or_error.order.id)
              expect(order.mode).to eq Order::BUY
              expect(order.currency_code).to eq 'USD'
              expect(order.buyer_id).to eq jwt_user_id
              expect(order.seller_id).to eq seller_id
              expect(order.line_items.count).to eq 1
              expect(order.line_items.first.list_price_cents).to eq 5400_12
              expect(order.line_items.first.artwork_id).to eq 'artwork-id'
              expect(order.line_items.first.edition_set_id).to be_nil
              expect(order.line_items.first.quantity).to eq 2
            end.to change(Order, :count).by(1).and change(LineItem, :count).by(1)
          end
          context 'without quantity' do
            it 'defaults to 1' do
              expect do
                response = client.execute(mutation, input: { artworkId: artwork_id })
                expect(response.data.create_order_with_artwork.order_or_error.order.id).not_to be_nil
                expect(response.data.create_order_with_artwork.order_or_error).not_to respond_to(:error)

                order = Order.find(response.data.create_order_with_artwork.order_or_error.order.id)
                expect(order.mode).to eq Order::BUY
                expect(order.currency_code).to eq 'USD'
                expect(order.buyer_id).to eq jwt_user_id
                expect(order.seller_id).to eq seller_id
                expect(order.line_items.count).to eq 1
                expect(order.line_items.first.list_price_cents).to eq 5400_12
                expect(order.line_items.first.artwork_id).to eq 'artwork-id'
                expect(order.line_items.first.edition_set_id).to be_nil
                expect(order.line_items.first.quantity).to eq 1
              end.to change(Order, :count).by(1).and change(LineItem, :count).by(1)
            end
          end
          context 'with existing pending order for artwork' do
            let!(:order) do
              order = Fabricate(:order, buyer_id: jwt_user_id, state: Order::PENDING)
              order.line_items = [Fabricate(:line_item, artwork_id: artwork_id)]
              order
            end
            it 'creates a new order' do
              expect do
                response = client.execute(mutation, input: { artworkId: artwork_id })
                expect(response.data.create_order_with_artwork.order_or_error.order.id).not_to be_nil
                expect(response.data.create_order_with_artwork.order_or_error).not_to respond_to(:error)
                expect(order.reload.state).to eq Order::PENDING
              end.to change(Order, :count).by(1)
            end
          end
        end
      end

      context 'with artwork price in unsupported currency' do
        before do
          expect(Gravity).to receive(:get_artwork).with(artwork_id).and_return(gravity_v1_artwork(edition_sets: nil, price_currency: 'RIA'))
        end
        it 'returns error' do
          expect do
            response = client.execute(mutation, input: mutation_input.except(:editionSetId))
            expect(response.data.create_order_with_artwork.order_or_error).not_to respond_to(:order)
            expect(response.data.create_order_with_artwork.order_or_error.error).not_to be_nil

            expect(response.data.create_order_with_artwork.order_or_error.error.type).to eq 'validation'
            expect(response.data.create_order_with_artwork.order_or_error.error.code).to eq 'invalid_order'
          end.to change(Order, :count).by(0)
        end
      end
    end
  end
end
