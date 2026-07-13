class Api::V1::Accounts::Org::MembershipsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_membership, only: [:update, :destroy]

  def index
    @memberships = Current.account.org_memberships.includes(:user)
    @memberships = @memberships.where(department_id: params[:department_id]) if params[:department_id].present?
  end

  def create
    @membership = Current.account.org_memberships.create!(membership_params)
  end

  def update
    @membership.update!(membership_params)
  end

  def destroy
    @membership.destroy!
    head :ok
  end

  private

  def fetch_membership
    @membership = Current.account.org_memberships.find(params[:id])
  end

  def check_authorization
    authorize(Org::Membership)
  end

  def membership_params
    params.require(:membership).permit(:department_id, :user_id, :title, :is_primary)
  end
end
