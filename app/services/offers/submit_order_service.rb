module Offers
  class SubmitOrderService
    attr_reader :order, :offer

    def initialize(offer, user_id: nil)
      @offer = offer
      @order = @offer.order
      @user_id = user_id
    end

    def process!
      pre_process!
      @order.submit! do
        SubmitOfferService.new(@offer).process!
      end
      post_process
    end

    private

    def pre_process!
      assert_can_submit!

      @order.line_items.map do |li|
        artwork = GravityService.get_artwork(li[:artwork_id])
        if artwork[:current_version_id] != li[:artwork_version_id]
          Exchange.dogstatsd.increment 'submit.artwork_version_mismatch'
          raise Errors::ProcessingError, :artwork_version_mismatch
        end
      end
      @credit_card = GravityService.get_credit_card(@order.credit_card_id)
      assert_credit_card!
    end

    def post_process
      Exchange.dogstatsd.increment 'order.submit'
      PostOrderNotificationJob.perform_later(@order.id, Order::SUBMITTED, @user_id)
      OrderFollowUpJob.set(wait_until: @order.state_expires_at).perform_later(@order.id, @order.state)
      ReminderFollowUpJob.set(wait_until: @order.state_expires_at - 2.hours).perform_later(@order.id, @order.state)
    end

    def assert_can_submit!
      raise Errors::ValidationError, :cant_submit unless @order.mode == Order::OFFER
      raise Errors::ValidationError, :missing_required_info unless @order.can_commit?
    end

    def assert_credit_card!
      raise Errors::ValidationError.new(:credit_card_missing_external_id, credit_card_id: @credit_card[:id]) if @credit_card[:external_id].blank?
      raise Errors::ValidationError.new(:credit_card_missing_customer, credit_card_id: @credit_card[:id]) if @credit_card.dig(:customer_account, :external_id).blank?
      raise Errors::ValidationError.new(:credit_card_deactivated, credit_card_id: @credit_card[:id]) unless @credit_card[:deactivated_at].nil?
    end
  end
end
