class BuyOrderTotals
  def initialize(order)
    raise NotImplementedError unless order.mode == Order::BUY

    @order = order
  end

  def tax_total_cents
    @tax_total_cents ||= @order.tax_total_cents || @order.line_items.map(&:sales_tax_cents).sum
  end

  def items_total_cents
    @items_total_cents ||= @order.items_total_cents || @order.line_items.map(&:total_list_price_cents).sum
  end

  def commission_fee_cents
    @commission_fee_cents ||= @order.commission_fee_cents || @order.line_items.map(&:commission_fee_cents).sum
  end

  def shipping_total_cents
    @shipping_total_cents ||= @order.shipping_total_cents
  end

  def buyer_total_cents
    @buyer_total_cents ||= @order.buyer_total_cents || items_total_cents + shipping_total_cents.to_i + tax_total_cents.to_i
  end

  def transaction_fee_cents
    @transaction_fee_cents ||= @transaction_fee_cents || TransactionFeeCalculator.calculate(buyer_total_cents)
  end

  def seller_total_cents
    return @order.seller_total_cents if @order.seller_total_cents.present?
    return unless buyer_total_cents && commission_fee_cents && transaction_fee_cents

    @seller_total_cents ||= buyer_total_cents - commission_fee_cents - transaction_fee_cents - calculate_remittable_sales_tax
  end

  private

  def calculate_remittable_sales_tax
    @order.line_items.select(&:should_remit_sales_tax).sum(&:sales_tax_cents)
  end
end
