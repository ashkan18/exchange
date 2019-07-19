require 'stripe'
Stripe.api_key = Rails.application.config_for(:stripe)['stripe_api_key']
Stripe.api_version = '2019-05-16'
