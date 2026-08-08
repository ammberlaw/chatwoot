class Api::V1::Accounts::Crm::FollowUpNotesController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_note, only: [:show, :update, :destroy]

  RESULTS_PER_PAGE = 25

  def index
    @notes_scope = filtered_notes
    @notes_count = @notes_scope.count
    @notes = @notes_scope.order(created_at: :desc).page(params[:page] || 1).per(RESULTS_PER_PAGE)
  end

  def show; end

  def create
    @note = Current.account.crm_follow_up_notes.create!(note_params.merge(owner_id: note_params[:owner_id] || current_user.id))
  end

  def update
    @note.update!(note_params)
  end

  def destroy
    @note.destroy!
    head :ok
  end

  private

  # 单条也按可见范围收口，防止凭 id 越权查看/改他人跟进记录。
  def fetch_note
    @note = scope_by_team_owner(Current.account.crm_follow_up_notes).find(params[:id])
  end

  def check_authorization
    authorize(Crm::FollowUpNote)
  end

  # 数据范围按 CRM 团队收口（负责人列=owner_id）：业务员看自己 / 团队负责人看本队 / 管理员看全部。
  def filtered_notes
    scope = scope_by_team_owner(Current.account.crm_follow_up_notes)
    scope = scope.owned_by(current_user.id) if params[:filter] == 'mine'
    scope = scope.where(crm_customer_id: params[:customer_id]) if params[:customer_id].present?
    scope
  end

  def note_params
    params.require(:note).permit(:title, :body, :follow_up_method, :result_tag,
                                 :crm_customer_id, :contact_id, :crm_opportunity_id, :owner_id)
  end
end
