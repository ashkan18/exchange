class SalesTaxService
  REMITTING_STATES = [].freeze
  attr_reader :transaction
  def initialize(
    line_item,
    fulfillment_type,
    shipping_address,
    shipping_total_cents,
    artwork_location,
    tax_client = Taxjar::Client.new(
      api_key: Rails.application.config_for(:taxjar)['taxjar_api_key'],
      api_url: Rails.application.config_for(:taxjar)['taxjar_api_url'].presence
    )
  )

    @line_item = line_item
    @fulfillment_type = fulfillment_type
    @tax_client = tax_client
    @artwork_location = artwork_location
    @shipping_address = shipping_address
    @shipping_total_cents = artsy_should_remit_taxes? ? shipping_total_cents : 0
    @transaction = nil
    @refund = nil
  end

  def sales_tax
    @sales_tax ||= UnitConverter.convert_dollars_to_cents(fetch_sales_tax.amount_to_collect)
  rescue Taxjar::Error => e
    raise Errors::ProcessingError.new(:tax_calculator_failure, message: e.message)
  end

  def record_tax_collected
    @transaction = post_transaction if artsy_should_remit_taxes? && @line_item.sales_tax_cents&.positive?
  rescue Taxjar::Error => e
    raise Errors::ProcessingError.new(:tax_recording_failure, message: e.message)
  end

  def refund_transaction(refund_date)
    @transaction = get_transaction(transaction_id)
    @refund = post_refund(refund_date) if @transaction.present?
  rescue Taxjar::Error => e
    raise Errors::ProcessingError.new(:tax_refund_failure, message: e.message)
  end

  def artsy_should_remit_taxes?
    return false unless destination_address.country == Carmen::Country.coded('US').code

    REMITTING_STATES.include? destination_address.region.downcase
  end

  private

  def get_transaction(id)
    @tax_client.show_order(id)
  rescue Taxjar::Error::NotFound
    nil
  end

  def fetch_sales_tax
    @tax_client.tax_for_order(construct_tax_params)
  end

  def post_transaction
    transaction_date = @line_item.order.last_approved_at.iso8601
    @tax_client.create_order(
      construct_tax_params(
        transaction_id: transaction_id,
        transaction_date: transaction_date,
        sales_tax: UnitConverter.convert_cents_to_dollars(@line_item.sales_tax_cents)
      )
    )
  end

  def post_refund(refund_date)
    @tax_client.create_refund(
      construct_tax_params(
        transaction_id: "refund_#{transaction_id}",
        transaction_date: refund_date.iso8601,
        transaction_reference_id: transaction_id,
        sales_tax: UnitConverter.convert_cents_to_dollars(@line_item.sales_tax_cents)
      )
    )
  end

  def construct_tax_params(args = {})
    {
      amount: UnitConverter.convert_cents_to_dollars(@line_item.total_amount_cents),
      from_country: origin_address.country,
      from_zip: origin_address.postal_code,
      from_state: origin_address.region,
      from_city: origin_address.city,
      from_street: origin_address.street_line1,
      to_country: destination_address.country,
      to_zip: destination_address.postal_code,
      to_state: destination_address.region,
      to_city: destination_address.city,
      to_street: destination_address.street_line1,
      shipping: UnitConverter.convert_cents_to_dollars(@shipping_total_cents)
    }.merge(args)
  end

  def origin_address
    @origin_address ||= @fulfillment_type == Order::SHIP ? seller_address : @artwork_location
  end

  def destination_address
    @destination_address ||= @fulfillment_type == Order::SHIP ? @shipping_address : origin_address
  end

  def seller_address
    @seller_address ||= GravityService.get_partner_location(@line_item.order.seller_id)
  end

  def transaction_id
    "#{@line_item.order.id}__#{@line_item.id}"
  end
end
