class CreateOffers < ActiveRecord::Migration[5.2]
  def change
    create_table :offers, id: :uuid do |t|
      t.references :order, foreign_key: true, type: :uuid
      t.integer :amount_cents
      t.string :from_id
      t.string :from_type
      t.string :creator_id
      t.references :responds_to, type: :uuid
      t.foreign_key :offers, column: :responds_to_id

      t.timestamps
    end

    add_reference :orders, :last_offer, null: true, type: :uuid
    add_foreign_key :orders, :offers, column: :last_offer_id
  end
end
