class Offer < ApplicationRecord
  has_paper_trail

  STATES = [
    PENDING = 'pending'.freeze,
    SUBMITTED = 'submitted'.freeze
  ].freeze

  belongs_to :order
  belongs_to :responds_to, class_name: 'Offer', optional: true
end
