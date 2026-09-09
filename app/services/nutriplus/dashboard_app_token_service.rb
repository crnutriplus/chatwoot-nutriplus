module Nutriplus
  class DashboardAppTokenService
    TOKEN_TTL = 5.minutes
    ISSUER = 'chatwoot'.freeze
    AUDIENCE = 'nutriplus-crm'.freeze
    ALGORITHM = 'HS256'.freeze

    def initialize(
      account:,
      user:,
      conversation:,
      secret_key: ENV['NUTRIPLUS_DASHBOARD_APP_SECRET']
    )
      @account = account
      @user = user
      @conversation = conversation
      @secret_key = secret_key
    end

    def generate_token
      raise ArgumentError, 'NUTRIPLUS_DASHBOARD_APP_SECRET is not configured' if @secret_key.blank?
      raise ArgumentError, 'Conversation does not belong to account' unless @conversation.account_id == @account.id

      JWT.encode(token_payload, @secret_key, ALGORITHM)
    end

    private

    def token_payload
      issued_at = Time.current.to_i

      {
        iss: ISSUER,
        aud: AUDIENCE,
        sub: @user.id.to_s,
        account_id: @account.id,
        agent_id: @user.id,
        conversation_id: @conversation.display_id,
        contact_id: @conversation.contact_id,
        iat: issued_at,
        exp: issued_at + TOKEN_TTL.to_i,
        jti: SecureRandom.uuid
      }
    end
  end
end
