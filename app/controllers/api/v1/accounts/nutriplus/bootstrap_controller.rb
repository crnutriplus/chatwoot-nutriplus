class Api::V1::Accounts::Nutriplus::BootstrapController < Api::V1::Accounts::BaseController
  def create
    return head :forbidden unless Current.user.is_a?(User)

    conversation = Current.account.conversations.find_by!(
      display_id: params.require(:conversation_id)
    )

    authorize conversation, :show?

    token = Nutriplus::DashboardAppTokenService.new(
      account: Current.account,
      user: Current.user,
      conversation: conversation
    ).generate_token

    render json: {
      token: token,
      expires_in: Nutriplus::DashboardAppTokenService::TOKEN_TTL.to_i
    }
  end
end
