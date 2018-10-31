require 'rails_helper'

describe OrderTotalUpdaterService, type: :service do
  let(:shipping_total_cents) { nil }
  let(:tax_total_cents) { nil }
  let(:mode) { Order::BUY }
  let(:order) { Fabricate(:order, mode: mode, shipping_total_cents: shipping_total_cents, tax_total_cents: tax_total_cents) }
  describe '#update_order_totals!' do
    context 'BUY order' do
      context 'without line items' do
        it 'returns 0 for everything' do
          OrderTotalUpdaterService.new(order).update_totals!
          expect(order.reload.items_total_cents).to eq 0
          expect(order.buyer_total_cents).to eq 0
          expect(order.seller_total_cents).to eq 0
        end
      end
      context 'with line items' do
        let(:line_item1) { Fabricate(:line_item, order: order, price_cents: 100_00, sales_tax_cents: 500, should_remit_sales_tax: true) }
        let(:line_item2) { Fabricate(:line_item, order: order, price_cents: 200_00, quantity: 2, sales_tax_cents: 10_00, should_remit_sales_tax: false) }
        let!(:line_items) { [line_item1, line_item2] }
        context 'with shipping and tax' do
          let(:shipping_total_cents) { 50_00 }
          let(:tax_total_cents) { 60_00 }
          context 'without commission rate' do
            it 'sets correct totals on the order' do
              OrderTotalUpdaterService.new(order).update_totals!
              expect(order.items_total_cents).to eq 500_00
              expect(order.buyer_total_cents).to eq(500_00 + 50_00 + 60_00)
              expect(order.transaction_fee_cents).to eq 17_99
              expect(order.commission_fee_cents).to be_nil
              expect(order.seller_total_cents).to eq(610_00 - 17_99 - 500)
            end
          end
          context 'with commission rate' do
            it 'raises error for commission rate > 1' do
              expect { OrderTotalUpdaterService.new(order, 2) }.to raise_error do |error|
                expect(error).to be_a(Errors::ValidationError)
                expect(error.code).to eq :invalid_commission_rate
              end
            end
            it 'raises error for commission rate < 0' do
              expect { OrderTotalUpdaterService.new(order, -0.2) }.to raise_error do |error|
                expect(error).to be_a(Errors::ValidationError)
                expect(error.code).to eq :invalid_commission_rate
              end
            end
            it 'sets correct totals on the order' do
              OrderTotalUpdaterService.new(order, 0.40).update_totals!
              expect(order.items_total_cents).to eq 500_00
              expect(order.buyer_total_cents).to eq(500_00 + 50_00 + 60_00)
              expect(order.transaction_fee_cents).to eq 17_99
              expect(order.commission_fee_cents).to eq 200_00
              expect(order.seller_total_cents).to eq(610_00 - (17_99 + 200_00 + 500))
            end
            it 'sets correct commission on each line item' do
              OrderTotalUpdaterService.new(order, 0.40).update_totals!
              expect(line_item1.reload.commission_fee_cents).to eq 40_00
              expect(line_item2.reload.commission_fee_cents).to eq 160_00
            end
          end
        end
      end
    end
    context 'OFFER order' do
      let(:mode) { Order::OFFER }
      let(:line_item1) { Fabricate(:line_item, order: order, price_cents: 100_00, sales_tax_cents: 500, should_remit_sales_tax: true) }
      let(:line_item2) { Fabricate(:line_item, order: order, price_cents: 200_00, quantity: 2, sales_tax_cents: 10_00, should_remit_sales_tax: false) }
      let!(:line_items) { [line_item1, line_item2] }

      context 'with last_offer' do
        let(:offer) { Fabricate(:offer, order: order, amount_cents: 300_00) }
        before do
          order.update!(last_offer: offer)
        end
        context 'with shipping and tax' do
          let(:shipping_total_cents) { 50_00 }
          let(:tax_total_cents) { 60_00 }
          context 'without commission rate' do
            it 'sets correct totals on the order' do
              OrderTotalUpdaterService.new(order).update_totals!
              expect(order.items_total_cents).to eq 300_00
              expect(order.buyer_total_cents).to eq(300_00 + 50_00 + 60_00)
              expect(order.transaction_fee_cents).to eq 12_19
              expect(order.commission_fee_cents).to be_nil
              expect(order.seller_total_cents).to eq(410_00 - 12_19 - 500)
            end
          end
          context 'with commission rate' do
            it 'raises error for commission rate > 1' do
              expect { OrderTotalUpdaterService.new(order, 2) }.to raise_error do |error|
                expect(error).to be_a(Errors::ValidationError)
                expect(error.code).to eq :invalid_commission_rate
              end
            end
            it 'raises error for commission rate < 0' do
              expect { OrderTotalUpdaterService.new(order, -0.2) }.to raise_error do |error|
                expect(error).to be_a(Errors::ValidationError)
                expect(error.code).to eq :invalid_commission_rate
              end
            end
            it 'sets correct totals on the order' do
              OrderTotalUpdaterService.new(order, 0.40).update_totals!
              expect(order.items_total_cents).to eq 300_00
              expect(order.buyer_total_cents).to eq(300_00 + 50_00 + 60_00)
              expect(order.transaction_fee_cents).to eq 12_19
              expect(order.commission_fee_cents).to eq 200_00
              expect(order.seller_total_cents).to eq(410_00 - (12_19 + 200_00 + 500))
            end
            it 'sets correct commission on each line item' do
              OrderTotalUpdaterService.new(order, 0.40).update_totals!
              expect(line_item1.reload.commission_fee_cents).to eq 40_00
              expect(line_item2.reload.commission_fee_cents).to eq 160_00
            end
          end
        end
      end
    end
  end
end
