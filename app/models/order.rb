class Order < ApplicationRecord
  has_paper_trail
  SUPPORTED_CURRENCIES = %w[USD].freeze
  # For more docs about states go to:
  # https://www.notion.so/artsy/37c311363ef046c3aa546047e60cc58a?v=de68d5bbc30748f88b0d92a059bc0ba8
  STATES = [
    PENDING = 'pending'.freeze,
    # Buyer starts checkout flow but never submits
    ABANDONED = 'abandoned'.freeze,
    # Check-out complete; payment authorized.
    # Buyer credit card has been authorized and hold has been placed.
    # At this point, availability must be confirmed manually.
    # Holds expire 7 days after being placed.
    SUBMITTED = 'submitted'.freeze,
    # Availability has been manually confirmed and hold has been "captured" (debited).
    APPROVED = 'approved'.freeze,
    # Items have been deemed unavailable and hold is voided.
    CANCELED = 'canceled'.freeze,
    # Order is completely fulfilled by the seller
    FULFILLED = 'fulfilled'.freeze.freeze,
    # Order was refunded after approval/fulfillment
    RETURNED = 'returned'.freeze
  ].freeze

  REASONS = {
    CANCELED => {
      seller_lapsed: 'seller_lapsed'.freeze,
      seller_rejected: 'seller_rejected'.freeze
    }
  }.freeze

  STATE_EXPIRATIONS = {
    'pending' => 2.days,
    'submitted' => 2.days,
    'approved' => 7.days
  }.freeze

  FULFILLMENT_TYPES = [
    PICKUP = 'pickup'.freeze,
    SHIP = 'ship'.freeze
  ].freeze

  ACTIONS = %i[abandon submit approve reject fulfill seller_lapse return].freeze
  ACTION_REASONS = {
    seller_lapse: REASONS[CANCELED][:seller_lapsed],
    reject: REASONS[CANCELED][:seller_rejected]
  }.freeze

  PARTY_TYPES = [
    USER = 'user'.freeze,
    PARTNER = 'partner'.freeze
  ].freeze

  AUCTION_SELLER_TYPE = 'auction'.freeze

  has_many :line_items, dependent: :destroy, class_name: 'LineItem'
  has_many :transactions, dependent: :destroy
  has_many :state_histories, dependent: :destroy
  has_many :admin_notes, dependent: :destroy

  before_validation { self.currency_code = currency_code.upcase if currency_code.present? }

  validates :state, presence: true, inclusion: STATES
  validate :state_reason_inclusion
  validates :currency_code, inclusion: SUPPORTED_CURRENCIES

  after_create :update_code
  after_create :create_state_history
  before_save :update_state_timestamps, if: :state_changed?
  before_save :set_currency_code

  scope :pending, -> { where(state: PENDING) }
  scope :active, -> { where(state: [Order::APPROVED, Order::SUBMITTED]) }
  scope :approved, -> { where(state: APPROVED) }

  ACTIONS.each do |action|
    define_method "#{action}!" do |state_reason = nil, &block|
      with_lock do
        state_machine.trigger!(action)
        self.state_reason = state_reason || ACTION_REASONS[action]
        save!
        create_state_history
        block.call if block.present?
      end
    rescue MicroMachine::InvalidState
      raise Errors::ValidationError.new(:invalid_state, state: state)
    end
  end

  def shipping_info?
    fulfillment_type == PICKUP ||
      (fulfillment_type == SHIP && complete_shipping_details?)
  end

  def payment_info?
    credit_card_id.present?
  end

  def auction_seller?
    seller_type == AUCTION_SELLER_TYPE
  end

  def to_s
    "Order #{id}"
  end

  def last_submitted_at
    get_last_state_timestamp(Order::SUBMITTED)
  end

  def last_approved_at
    get_last_state_timestamp(Order::APPROVED)
  end

  def shipping_address
    return unless fulfillment_type == Order::SHIP

    Address.new(
      country: shipping_country,
      postal_code: shipping_postal_code,
      region: shipping_region,
      city: shipping_city,
      address_line1: shipping_address_line1,
      address_line2: shipping_address_line2
    )
  end

  private

  def state_reason_inclusion
    errors.add(:state_reason, "Current state not expecting reason: #{state}") if state_reason.present? && !REASONS.key?(state)
    errors.add(:state_reason, 'Invalid state reason') if REASONS[state] && !REASONS[state].value?(state_reason)
  end

  def update_code(attempts = 10)
    while attempts.positive?
      code = format('%09d', SecureRandom.rand(999999999))
      unless Order.where(code: code).exists?
        update!(code: code)
        break
      end
      attempts -= 1
    end
    raise Errors::ValidationError, :failed_order_code_generation if attempts.zero?
  end

  def update_state_timestamps
    self.state_updated_at = Time.now.utc
    self.state_expires_at = STATE_EXPIRATIONS.key?(state) ? state_updated_at + STATE_EXPIRATIONS[state] : nil
  end

  def get_last_state_timestamp(state)
    state_histories.where(state: state).order(:updated_at).last&.updated_at
  end

  def create_state_history
    state_histories.create!(state: state, reason: state_reason, updated_at: state_updated_at)
  end

  def set_currency_code
    self.currency_code ||= 'USD'
  end

  def state_machine
    @state_machine ||= build_machine
  end

  def build_machine
    machine = MicroMachine.new(state)
    machine.when(:abandon, PENDING => ABANDONED)
    machine.when(:submit, PENDING => SUBMITTED)
    machine.when(:approve, SUBMITTED => APPROVED)
    machine.when(:reject, SUBMITTED => CANCELED)
    machine.when(:seller_lapse, SUBMITTED => CANCELED)
    machine.when(:cancel, SUBMITTED => CANCELED)
    machine.when(:fulfill, APPROVED => FULFILLED)
    machine.when(:return, APPROVED => RETURNED, FULFILLED => RETURNED)
    machine.on(:any) do
      self.state = machine.state
    end
    machine
  end

  def complete_shipping_details?
    [shipping_name, shipping_address_line1, shipping_city, shipping_country, shipping_postal_code, buyer_phone_number].all?(&:present?)
  end
end
