class Api::V1::Accounts::Crm::EmailTemplatesController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_template, only: [:show, :update, :destroy]

  def index
    scope = Current.account.crm_email_templates
    scope = scope.where(category: params[:category]) if params[:category].present?
    @templates = scope.order(:category, :name)
  end

  def show; end

  def create
    @template = Current.account.crm_email_templates.create!(template_params)
    attach_files
  end

  def update
    @template.update!(template_params)
    purge_removed_files
    attach_files
  end

  def destroy
    @template.destroy!
    head :ok
  end

  private

  def fetch_template
    @template = Current.account.crm_email_templates.find(params[:id])
  end

  def check_authorization
    authorize(Crm::EmailTemplate)
  end

  def template_params
    params.require(:template).permit(:name, :category, :subject_template, :body, :description)
  end

  # 新上传的附件追加（不动已有）；multipart 下 template[files][] 传 File。
  def attach_files
    files = params.dig(:template, :files)
    @template.files.attach(files) if files.present?
  end

  # 编辑时前端勾掉的已有附件按 blob/attachment id 移除。
  def purge_removed_files
    ids = Array(params.dig(:template, :remove_file_ids)).map(&:to_s).reject(&:blank?)
    return if ids.empty?

    @template.files.attachments.each { |a| a.purge if ids.include?(a.id.to_s) }
  end
end
