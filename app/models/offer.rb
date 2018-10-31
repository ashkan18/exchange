class Offer < ApplicationRecord
  belongs_to :order
  belongs_to :responds_to, class_name: 'Offer', optional: true
end
