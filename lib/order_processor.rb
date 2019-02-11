class OrderProcessor
  attr_accessor :order, :transaction, :error

  def initialize(order, user_id)
    @order = order
    @user_id = user_id
    @error = nil
    @transaction = nil
    @deducted_inventory = []
    @validated = false
  end

  def hold
    raise Errors::ValidationError, @error unless valid?

    deduct_inventory
    @transaction = PaymentService.create_and_authorize_charge(construct_charge_params)
    raise Errors::ProcessingError.new(:charge_authorization_failed, @transaction) if @transaction.failed?

    @order.update!(external_charge_id: @transaction.external_id)
  rescue Errors::ValidationError, Errors::ProcessingError => e
    undeduct_inventory
    raise e
  ensure
    handle_transaction
  end

  def charge
    raise Errors::ValidationError, @error unless valid?

    deduct_inventory
    @transaction = PaymentService.create_and_capture_charge(construct_charge_params)
    undeduct_inventory if @transaction.failed?
  rescue Errors::ValidationError, Errors::ProcessingError => e
    undeduct_inventory
    raise e
  end

  def valid?
    @validated ||= begin
      @error = :missing_required_info unless @order.can_commit?
      @error ||= @order.assert_credit_card
    end
    @error.nil?
  end

  private

  def undeduct_inventory
    @deducted_inventory.each { |li| Gravity.undeduct_inventory(li) }
    @deducted_inventory = []
  end

  def deduct_inventory
    # Try holding artwork and deduct inventory
    @order.line_items.each do |li|
      Gravity.deduct_inventory(li)
      @deducted_inventory << li
    end
  end

  def construct_charge_params
    {
      credit_card: @order.credit_card,
      buyer_amount: @order.buyer_total_cents,
      merchant_account: @order.merchant_account,
      seller_amount: @order.seller_total_cents,
      currency_code: @order.currency_code,
      metadata: charge_metadata,
      description: charge_description
    }
  end

  def charge_description
    partner_name = (@order.partner[:name] || '').parameterize[0...12].upcase
    "#{partner_name} via Artsy"
  end

  def charge_metadata
    {
      exchange_order_id: @order.id,
      buyer_id: @order.buyer_id,
      buyer_type: @order.buyer_type,
      seller_id: @order.seller_id,
      seller_type: @order.seller_type,
      type: @order.auction_seller? ? 'auction-bn' : 'bn-mo'
    }
  end
end
