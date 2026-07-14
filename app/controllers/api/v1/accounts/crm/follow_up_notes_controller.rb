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

  def fetch_note
    @note = Current.account.crm_follow_up_notes.find(params[:id])
  end

  def check_authorization
    authorize(Crm::FollowUpNote)
  end

  def filtered_notes
    scope = Current.account.crm_follow_up_notes
    scope = scope.owned_by(current_user.id) if params[:filter] == 'mine'
    scope = scope.where(crm_customer_id: params[:customer_id]) if params[:customer_id].present?
    scope
  end

  def note_params
    params.require(:note).permit(:title, :body, :follow_up_method, :result_tag,
                                 :crm_customer_id, :contact_id, :crm_opportunity_id, :owner_id)
  end
end
