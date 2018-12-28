class OrderShipping
  def initialize(order)
    @order = order
  end

  def pickup!
    @order.with_lock do
      @order.update!(fulfillment_type: Order::PICKUP)
      update_totals!
    end
  end

  def ship!(shipping_info)
    @shipping_address = Address.new(shipping_info)
    raise Errors::ValidationError, :missing_country if @shipping_address&.country.blank?

    @order.with_lock do
      @order.update!(
        fulfillment_type: Order::SHIP,
        buyer_phone_number: shipping_info[:phone_number],
        shipping_name: shipping_info[:name],
        shipping_address_line1: @shipping_address&.street_line1,
        shipping_address_line2: @shipping_address&.street_line2,
        shipping_city: @shipping_address&.city,
        shipping_region: @shipping_address&.region,
        shipping_country: @shipping_address&.country,
        shipping_postal_code: @shipping_address&.postal_code
      )
      update_totals!
    end
  end

  private

  def update_totals!
    pending_offer? ? set_offer_totals! : set_order_totals!
  end

  def set_offer_totals!
    offer_totals = OfferTotals.new(@order, pending_offer.amount_cents)
    pending_offer.update!(
      shipping_total_cents: offer_totals.shipping_total_cents,
      tax_total_cents: offer_totals.tax_total_cents,
      should_remit_sales_tax: offer_totals.should_remit_sales_tax
    )
  end

  def set_order_totals!
    order_helper = OrderHelper.new(@order)
    # update order line items
    line_items_totals = @order.line_items.map do |li|
      line_item_totals = LineItemTotals.new(li, fulfillment_type: @order.fulfillment_type, shipping_address: @order.shipping_address, seller_locations: order_helper.seller_locations, artsy_collects_sales_tax: order_helper.artsy_collects_sales_tax?)
      li.update!(sales_tax_cents: line_item_totals.tax_total_cents, should_remit_sales_tax: line_item_totals.should_remit_sales_tax)
      line_item_totals
    end
    @order.update!(shipping_total_cents: line_items_totals.map(&:shipping_total_cents).sum)
    buy_order_totals = BuyOrderTotals.new(@order)
    @order.update!(
      tax_total_cents: buy_order_totals.tax_total_cents,
      buyer_total_cents: buy_order_totals.buyer_total_cents
    )
  end

  def pending_offer?
    @order.offers.pending.exists?
  end

  def pending_offer
    @pending_offer ||= @order.offers.pending.order(created_at: :desc).first
  end
end
