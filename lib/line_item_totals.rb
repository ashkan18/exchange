class LineItemTotals
  # Given a line_item, it calculates tax, shipping based on offer amount
  delegate :tax_total_cents, to: :tax_data
  delegate :should_remit_sales_tax, to: :tax_data

  def initialize(line_item, fulfillment_type:, shipping_address:, seller_locations:, artsy_collects_sales_tax:)
    @line_item = line_item
    @fulfillment_type = fulfillment_type
    @shipping_address = shipping_address
    @seller_locations = seller_locations
    @artsy_collects_sales_tax = artsy_collects_sales_tax
    @order = line_item.order
  end

  def shipping_total_cents
    return unless @order.shipping_info? && artwork_location.present?

    @shipping_total_cents ||= ShippingHelper.calculate(artwork, @order.fulfillment_type, @order.shipping_address)
  end

  private

  def artwork
    @artwork ||= Gravity.get_artwork(@line_item.artwork_id) || raise(Errors::ValidationError, :unknown_artwork)
  end

  def artwork_location
    raise Errors::ValidationError, :missing_artwork_location if artwork[:location].blank?

    @artwork_location ||= Address.new(artwork[:location])
  end

  def tax_data
    return OpenStruct.new(tax_total_cents: nil, should_remit_sales_tax: nil) unless @order.shipping_info?

    @tax_data ||= begin
      service = Tax::CalculatorService.new(
        @line_item.total_list_price_cents,
        @line_item.total_list_price_cents / @line_item.quantity,
        @line_item.quantity,
        @fulfillment_type,
        @shipping_address,
        shipping_total_cents,
        artwork_location,
        @seller_locations
      )
      sales_tax = @artsy_collects_sales_tax ? service.sales_tax : 0
      OpenStruct.new(tax_total_cents: sales_tax, should_remit_sales_tax: service.artsy_should_remit_taxes?)
    end
  rescue Errors::ValidationError => e
    raise e unless e.code == :no_taxable_addresses

    # If there are no taxable addresses then we set the sales tax to 0.
    OpenStruct.new(tax_total_cents: 0, should_remit_sales_tax: false)
  end
end
