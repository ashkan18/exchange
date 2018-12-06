class BaseTotalCalculatorService
  def artworks
    @artworks ||= Hash[@order.line_items.pluck(:artwork_id).uniq.map do |artwork_id|
      artwork = GravityService.get_artwork(artwork_id)
      validate_artwork!(artwork)
      [artwork[:_id], artwork]
    end]
  end

  def validate_artwork!(artwork)
    raise Errors::ValidationError, :unknown_artwork unless artwork
    raise Errors::ValidationError, :missing_artwork_location if artwork[:location].blank?
  end

  def set_offer_totals!
    @pending_offer.update!(shipping_total_cents: shipping_total_cents)
    set_offer_tax_total_cents
  end

  def shipping_total_cents
    @shipping_total_cents ||= @order.line_items.map { |li| ShippingCalculatorService.new(artworks[li.artwork_id], @fulfillment_type, @order.shipping_address).shipping_cents }.sum
  end

  def set_offer_tax_total_cents
    seller_addresses = GravityService.fetch_partner_locations(@order.seller_id)
    artwork_id = @order.line_items.first.artwork_id # this is with assumption of Offer order only having one lineItem
    artwork = @artworks[artwork_id]
    @tax_total_cents ||= begin
      artwork_address = Address.new(artwork[:location])
      begin
        service = Tax::CalculatorService.new(
          @pending_offer.amount_cents,
          @pending_offer.amount_cents / @order.line_items.first.quantity,
          @order.line_items.first.quantity,
          @order.fulfillment_type,
          @order.shipping_address,
          shipping_total_cents,
          artwork_address,
          seller_addresses
        )
        @pending_offer.update!(tax_total_cents: service.sales_tax, should_remit_sales_tax: service.artsy_should_remit_taxes?)
      rescue Errors::ValidationError => e
        raise e unless e.code == :no_taxable_addresses

        # If there are no taxable addresses then we set the sales tax to 0.
        @pending_offer.update!(tax_total_cents: 0, should_remit_sales_tax: false)
      end
    end
  rescue Errors::AddressError => e
    raise Errors::ValidationError, e.code
  end
end
