class OrderSubmitService
  def self.call!(order, by: nil)
    new(order, by).process!
  end

  attr_accessor :order, :credit_card, :merchant_account, :partner
  def initialize(order, by)
    @order = order
    @by = by
    @credit_card = nil
    @merchant_account = nil
    @partner = nil
    @transaction = nil
  end

  def process!
    deducted_inventory = []
    pre_process!
    @order.submit! do
      # Try holding artwork and deduct inventory
      @order.line_items.each do |li|
        GravityService.deduct_inventory(li)
        deducted_inventory << li
      end
      @transaction = PaymentService.authorize_charge(construct_charge_params)
      raise Errors::ProcessingError.new(:charge_authorization_failed, @transaction) if @transaction.failed?
    end
    @order.update!(external_charge_id: @transaction.external_id)
    post_process!
    @order
  rescue Errors::ValidationError, Errors::ProcessingError => e
    # undeduct all already deducted inventory
    deducted_inventory.each { |li| GravityService.undeduct_inventory(li) }
    raise e
  ensure
    @order.transactions << @transaction if @transaction.present?
  end

  private

  def pre_process!
    raise Errors::ValidationError, :missing_required_info unless can_submit?

    @order.line_items.map do |li|
      artwork = GravityService.get_artwork(li[:artwork_id])
      raise Errors::ProcessingError, :artwork_version_mismatch if artwork[:current_version_id] != li[:artwork_version_id]
    end
    @credit_card = GravityService.get_credit_card(@order.credit_card_id)
    assert_credit_card!
    @partner = GravityService.get_partner(@order.seller_id)
    raise Errors::ValidationError.new(:missing_commission_rate, partner_id: @partner[:id]) if @partner[:effective_commission_rate].blank?

    @merchant_account = GravityService.get_merchant_account(@order.seller_id)
    OrderTotalUpdaterService.new(@order, @partner[:effective_commission_rate]).update_totals!
  end

  def post_process!
    PostNotificationJob.perform_later(@order.id, Order::SUBMITTED, @by)
    OrderFollowUpJob.set(wait_until: @order.state_expires_at).perform_later(@order.id, @order.state)
  end

  def construct_charge_params
    {
      credit_card: @credit_card,
      buyer_amount: @order.buyer_total_cents,
      merchant_account: @merchant_account,
      seller_amount: @order.seller_total_cents,
      currency_code: @order.currency_code,
      metadata: charge_metadata,
      description: charge_description
    }
  end

  def assert_credit_card!
    raise Errors::ValidationError.new(:credit_card_missing_external_id, credit_card_id: @credit_card[:id]) if @credit_card[:external_id].blank?
    raise Errors::ValidationError.new(:credit_card_missing_customer, credit_card_id: @credit_card[:id]) if @credit_card.dig(:customer_account, :external_id).blank?
    raise Errors::ValidationError.new(:credit_card_deactivated, credit_card_id: @credit_card[:id]) unless @credit_card[:deactivated_at].nil?
  end

  def can_submit?
    @order.shipping_info? && @order.payment_info?
  end

  def charge_description
    "#{(@partner[:name] || '').parameterize[0...12].upcase} via Artsy"
  end

  def charge_metadata
    {
      exchange_order_id: @order.id,
      buyer_id: @order.buyer_id,
      buyer_type: @order.buyer_type,
      seller_id: @order.seller_id,
      seller_type: @order.seller_type,
      type: 'bn-mo'
    }
  end
end
