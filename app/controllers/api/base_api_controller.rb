module Api
  class BaseApiController < ApplicationController
    skip_before_action :require_artsy_authentication
    skip_before_action :verify_authenticity_token
    before_action :authenticate_request!
    before_action :use_request_metadata

    private

    def use_request_metadata(&block)
      Rails.configuration.event_store.with_metadata(request_metadata, &block)
    end

    def request_metadata
      { user_id: current_user[:id] }
    end
  end
end
