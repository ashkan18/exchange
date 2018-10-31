# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2018_10_29_122615) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "pgcrypto"
  enable_extension "plpgsql"

  create_table "active_admin_comments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "namespace"
    t.text "body"
    t.string "resource_type"
    t.uuid "resource_id"
    t.string "author_type"
    t.uuid "author_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["author_type", "author_id"], name: "index_active_admin_comments_on_author_type_and_author_id"
    t.index ["namespace"], name: "index_active_admin_comments_on_namespace"
    t.index ["resource_type", "resource_id"], name: "index_active_admin_comments_on_resource_type_and_resource_id"
  end

  create_table "admin_notes", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "order_id"
    t.string "admin_id", null: false
    t.string "note_type", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_admin_notes_on_order_id"
  end

  create_table "fulfillments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "courier"
    t.string "tracking_id"
    t.date "estimated_delivery"
    t.string "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "line_item_fulfillments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "line_item_id"
    t.uuid "fulfillment_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["fulfillment_id"], name: "index_line_item_fulfillments_on_fulfillment_id"
    t.index ["line_item_id"], name: "index_line_item_fulfillments_on_line_item_id"
  end

  create_table "line_items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "order_id"
    t.string "artwork_id"
    t.string "edition_set_id"
    t.integer "price_cents"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "quantity", default: 1, null: false
    t.integer "sales_tax_cents"
    t.string "artwork_version_id"
    t.boolean "should_remit_sales_tax"
    t.string "sales_tax_transaction_id"
    t.integer "commission_fee_cents"
    t.index ["order_id"], name: "index_line_items_on_order_id"
  end

  create_table "offers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "order_id"
    t.integer "amount_cents"
    t.string "from_id"
    t.string "from_type"
    t.string "creator_id"
    t.uuid "responds_to_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_offers_on_order_id"
    t.index ["responds_to_id"], name: "index_offers_on_responds_to_id"
  end

  create_table "orders", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "code"
    t.integer "shipping_total_cents"
    t.integer "tax_total_cents"
    t.integer "transaction_fee_cents"
    t.integer "commission_fee_cents"
    t.string "currency_code", limit: 3
    t.string "buyer_id"
    t.string "seller_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "state", null: false
    t.string "credit_card_id"
    t.datetime "state_updated_at"
    t.datetime "state_expires_at"
    t.string "shipping_address_line1"
    t.string "shipping_address_line2"
    t.string "shipping_city"
    t.string "shipping_country"
    t.string "shipping_postal_code"
    t.string "fulfillment_type"
    t.string "shipping_region"
    t.string "external_charge_id"
    t.string "shipping_name"
    t.string "buyer_type"
    t.string "seller_type"
    t.integer "items_total_cents"
    t.integer "buyer_total_cents"
    t.integer "seller_total_cents"
    t.string "buyer_phone_number"
    t.string "state_reason"
    t.float "commission_rate"
    t.string "mode", null: false
    t.uuid "last_offer_id"
    t.index ["buyer_id"], name: "index_orders_on_buyer_id"
    t.index ["code"], name: "index_orders_on_code"
    t.index ["last_offer_id"], name: "index_orders_on_last_offer_id"
    t.index ["seller_id"], name: "index_orders_on_seller_id"
    t.index ["state"], name: "index_orders_on_state"
  end

  create_table "state_histories", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "order_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "state"
    t.string "reason"
    t.index ["order_id"], name: "index_state_histories_on_order_id"
  end

  create_table "transactions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "order_id"
    t.string "external_id"
    t.string "source_id"
    t.string "destination_id"
    t.integer "amount_cents"
    t.string "failure_code"
    t.string "failure_message"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "transaction_type"
    t.index ["order_id"], name: "index_transactions_on_order_id"
  end

  create_table "versions", force: :cascade do |t|
    t.string "item_type", null: false
    t.integer "item_id", null: false
    t.string "event", null: false
    t.string "whodunnit"
    t.jsonb "object"
    t.datetime "created_at"
    t.index ["item_type", "item_id"], name: "index_versions_on_item_type_and_item_id"
  end

  add_foreign_key "admin_notes", "orders"
  add_foreign_key "line_item_fulfillments", "fulfillments"
  add_foreign_key "line_item_fulfillments", "line_items"
  add_foreign_key "line_items", "orders"
  add_foreign_key "offers", "offers", column: "responds_to_id"
  add_foreign_key "offers", "orders"
  add_foreign_key "orders", "offers", column: "last_offer_id"
  add_foreign_key "state_histories", "orders"
  add_foreign_key "transactions", "orders"
end
