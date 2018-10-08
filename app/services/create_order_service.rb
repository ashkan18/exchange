class CreateOrderService
  attr_reader :order

  AUCTION_PARTNER_TYPE = 'Auction'.freeze

  def initialize(user_id:, artwork_id:, edition_set_id: nil, quantity:, is_auction: nil)
    @user_id = user_id
    @artwork_id = artwork_id
    @edition_set_id = edition_set_id
    @quantity = quantity
    @edition_set = nil
    @order = nil
    @partner = nil
    @auction = is_auction
  end

  def process!
    pre_process!

    Order.transaction do
      @order = Order.create!(
        buyer_id: @user_id,
        buyer_type: Order::USER,
        seller_id: @artwork[:partner][:_id],
        seller_type: Order::PARTNER,
        currency_code: @artwork[:price_currency],
        state: Order::PENDING,
        state_updated_at: Time.now.utc,
        state_expires_at: Order::STATE_EXPIRATIONS[Order::PENDING].from_now,
        is_auction: auction?
      )
      @order.line_items.create!(
        artwork_id: @artwork_id,
        artwork_version_id: @artwork[:current_version_id],
        edition_set_id: @edition_set_id,
        price_cents: artwork_price,
        quantity: @quantity
      )
      OrderTotalUpdaterService.new(@order).update_totals!
    end
    post_process
  rescue ActiveRecord::RecordInvalid => e
    raise Errors::ValidationError.new(:invalid_order, message: e.message)
  end

  private

  def pre_process!
    @artwork = GravityService.get_artwork(@artwork_id)
    raise Errors::ValidationError.new(:unknown_artwork, artwork_id: @artwork_id) if @artwork.nil?
    raise Errors::ValidationError.new(:unpublished_artwork, artwork_id: @artwork_id) unless @artwork[:published]
    raise Errors::ValidationError.new(:not_acquireable, artwork_id: @artwork_id) unless @artwork[:acquireable]

    find_verify_edition_set
  end

  def auction?
    @auction ||= begin
      @partner = GravityService.get_partner(@artwork[:partner_id])
      @partner && @partner[:type] == AUCTION_PARTNER_TYPE
    end
  end

  def post_process
    OrderFollowUpJob.set(wait_until: @order.state_expires_at).perform_later(@order.id, @order.state)
  end

  def artwork_price
    item = @edition_set.presence || @artwork
    raise Errors::ValidationError, :missing_price unless item[:price_listed]&.positive?

    raise Errors::ValidationError, :missing_currency if item[:price_currency].blank?

    # TODO: 🚨 update gravity to expose amount in cents and remove this duplicate logic
    # https://github.com/artsy/gravity/blob/65e398e3648d61175e7a8f4403a2d379b5aa2107/app/models/util/for_sale.rb#L221
    UnitConverter.convert_dollars_to_cents(item[:price_listed])
  end

  def find_verify_edition_set
    return unless @edition_set_id.present? || @artwork[:edition_sets].present?

    if @edition_set_id
      @edition_set = @artwork[:edition_sets]&.find { |e| e[:id] == @edition_set_id }
      raise Errors::ValidationError.new(:unknown_edition_set, artwork_id: @artwork[:id], edition_set_id: @edition_set_id) unless @edition_set
    else
      # If artwork has EditionSet but it was not passed in the request
      # if there are more than one EditionSet we'll raise error
      # if there is one we are going to assume thats the one buyer meant to buy
      # TODO: ☝ is a temporary logic till Eigen starts supporting editionset artworks
      # https://artsyproduct.atlassian.net/browse/PURCHASE-505
      raise Errors::ValidationError.new(:missing_edition_set_id, artwork_id: @artwork_id) if @artwork[:edition_sets].count > 1

      @edition_set = @artwork[:edition_sets].first
      @edition_set_id = @edition_set[:id]
    end
  end
end
