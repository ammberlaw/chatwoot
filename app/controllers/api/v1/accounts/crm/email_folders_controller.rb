class Api::V1::Accounts::Crm::EmailFoldersController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization

  # 我的文件夹（含层级 parent_id，前端拼树）+ 各自邮件数。
  def index
    folders = Current.account.crm_email_folders.owned_by(current_user.id).order(:name)
    counts = Current.account.crm_emails.where(crm_email_folder_id: folders.map(&:id)).group(:crm_email_folder_id).count
    @folders = folders.map { |f| { id: f.id, name: f.name, parent_id: f.parent_id, count: counts[f.id].to_i } }
    render json: { payload: @folders }
  end

  # parent_id 传了则建为子文件夹（校验父级属本人，防越权嵌套）。
  def create
    parent_id = params[:parent_id].presence
    if parent_id && Current.account.crm_email_folders.owned_by(current_user.id).where(id: parent_id).none?
      return render json: { error: '上级文件夹无效' }, status: :unprocessable_entity
    end

    folder = Current.account.crm_email_folders.create!(
      name: params.require(:name), owner_id: current_user.id, parent_id: parent_id
    )
    render json: { id: folder.id, name: folder.name, parent_id: folder.parent_id, count: 0 }
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
