require 'rails_helper'

RSpec.describe 'Nutriplus Bootstrap', type: :request do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:secret) { 'nutriplus-test-secret-that-is-only-used-in-request-specs' }

  around do |example|
    original_secret = ENV['NUTRIPLUS_DASHBOARD_APP_SECRET']
    ENV['NUTRIPLUS_DASHBOARD_APP_SECRET'] = secret
    example.run
  ensure
    ENV['NUTRIPLUS_DASHBOARD_APP_SECRET'] = original_secret
  end

  describe 'POST /api/v1/accounts/:account_id/nutriplus/bootstrap' do
    it 'returns unauthorized for an unauthenticated request' do
      post "/api/v1/accounts/#{account.id}/nutriplus/bootstrap",
           params: { conversation_id: conversation.display_id },
           as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns unauthorized when an agent cannot view the conversation' do
      agent = create(:user, account: account, role: :agent)

      post "/api/v1/accounts/#{account.id}/nutriplus/bootstrap",
           headers: agent.create_new_auth_token,
           params: { conversation_id: conversation.display_id },
           as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns a short-lived signed token for an agent with conversation access' do
      agent = create(:user, account: account, role: :agent)
      create(:inbox_member, user: agent, inbox: conversation.inbox)

      post "/api/v1/accounts/#{account.id}/nutriplus/bootstrap",
           headers: agent.create_new_auth_token,
           params: { conversation_id: conversation.display_id },
           as: :json

      expect(response).to have_http_status(:success)

      response_body = response.parsed_body
      expect(response_body['expires_in']).to eq(300)

      claims = JWT.decode(
        response_body['token'],
        secret,
        true,
        {
          algorithm: 'HS256',
          verify_aud: true,
          aud: 'nutriplus-crm',
          verify_iss: true,
          iss: 'chatwoot'
        }
      ).first

      expect(claims['sub']).to eq(agent.id.to_s)
      expect(claims['account_id']).to eq(account.id)
      expect(claims['agent_id']).to eq(agent.id)
      expect(claims['conversation_id']).to eq(conversation.display_id)
      expect(claims['contact_id']).to eq(conversation.contact_id)
      expect(claims['exp'] - claims['iat']).to eq(300)
      expect(claims['jti']).to be_present
    end

    it 'rejects an agent bot' do
      agent_bot = create(:agent_bot, account: account)
      create(:agent_bot_inbox, inbox: conversation.inbox, agent_bot: agent_bot)

      post "/api/v1/accounts/#{account.id}/nutriplus/bootstrap",
           headers: { api_access_token: agent_bot.access_token.token },
           params: { conversation_id: conversation.display_id },
           as: :json

      expect(response.status).to be_in([401, 403])
    end
  end
end
