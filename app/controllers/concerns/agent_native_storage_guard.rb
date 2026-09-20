module AgentNativeStorageGuard
  extend ActiveSupport::Concern
  included do
    prepend_before_action :guard_native_blob, only: :show
    after_action { response.set_header("Cache-Control", "private, no-store") }
  end

  private
    def guard_native_blob
      blob = if params[:signed_id]
        ActiveStorage::Blob.find_signed(params[:signed_id])
      elsif params[:encoded_key]
        data = ActiveStorage.verifier.verified(params[:encoded_key], purpose: :blob_key)
        ActiveStorage::Blob.find_by(key: data[:key]) if data
      end
      return unless blob
      protected_blob = blob.attachments.any? do |attachment|
        record = attachment.record
        record.class.name.start_with?("AgentNative::") || (record.is_a?(Message) && record.creator.native_agent?)
      end
      head :not_found if protected_blob
    end
end
