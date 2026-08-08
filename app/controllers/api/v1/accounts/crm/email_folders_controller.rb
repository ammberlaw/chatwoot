class Api::V1::Accounts::Crm::EmailFoldersController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization

  # 我的文件夹 + 各自邮件数。
  def index
    folders = Current.account.crm_email_folders.owned_by(current_user.id).order(:name)
    counts = Current.account.crm_emails.where(crm_email_folder_id: folders.map(&:id)).group(:crm_email_folder_id).count
    @folders = folders.map { |f| { id: f.id, name: f.name, count: counts[f.id].to_i } }
    render json: { payload: @folders }
  end

  def create
    folder = Current.account.crm_email_folders.create!(name: params.require(:name), owner_id: current_user.id)
    render json: { id: folder.id, name: folder.name, count: 0 }
  end

  def destroy
    folder = Current.account.crm_email_folders.owned_by(current_user.id).find(params[:id])
    folder.destroy! # dependent: :nullify —— 里面的邮件回到收件箱等系统视图
    head :ok
  end

  private

  def check_authorization
    authorize(Crm::EmailFolder)
  end
end
