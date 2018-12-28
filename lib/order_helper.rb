class OrderHelper
  def initialize(order)
    @order = order
  end

  def valid_artwork_version?
    @order.line_items.all? { |li| order_helper.artworks[li[:artwork_id]][:current_version_id] == li[:artwork_version_id] }
  end

  def assert_credit_card
    case order_helper.credit_card
    when ->(cc) { cc[:external_id].blank? } then :credit_card_missing_external_id
    when ->(cc) { cc.dig(:customer_account, :external_id).blank? } then :credit_card_missing_customer
    when ->(cc) { cc[:deactivated_at].present? } then :credit_card_deactivated
    end
  end

  def artworks
    @artworks ||= Hash[@order.line_items.pluck(:artwork_id).uniq.map do |artwork_id|
      artwork = Gravity.get_artwork(artwork_id)
      validate_artwork!(artwork)
      [artwork[:_id], artwork]
    end]
  end

  def shipping_total_cents
    @shipping_total_cents ||= @order.line_items.map { |li| ShippingHelper.calculate(artworks[li.artwork_id], @order.fulfillment_type, @order.shipping_address) }.sum
  end

  def credit_card
    @credit_card ||= Gravity.get_credit_card(@order.credit_card_id)
  end

  def partner
    @partner ||= Gravity.fetch_partner(@order.seller_id)
  end

  def merchant_account
    @merchant_account ||= Gravity.get_merchant_account(@order.seller_id)
  end

  def seller_locations
    @seller_locations ||= Gravity.fetch_partner_locations(@order.seller_id)
  end

  def commission_rate
    @commission_rate ||= partner[:effective_commission_rate]
  end

  def inventory?
    @order.line_items.all? do |li|
      artwork = artworks[li.artwork_id]
      inventory = li.edition_set_id.present? ? artwork[:edition_sets][li.edition_set_id][:inventory] : artwork[:inventory]
      inventory[:count].positive? || inventory[:unlimited] == true
    end
  end

  def artsy_collects_sales_tax?
    @artsy_collects_sales_tax ||= partner[:artsy_collects_sales_tax]
  end

  private

  def order_helper
    @order_helper ||= OrderHelper.new(@order)
  end

  def validate_artwork!(artwork)
    raise Errors::ValidationError, :unknown_artwork unless artwork
    raise Errors::ValidationError, :missing_artwork_location if artwork[:location].blank?
  end
end
