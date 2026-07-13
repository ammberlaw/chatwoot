class Api::V1::Accounts::Crm::KnowledgeCategoriesController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :fetch_category, only: [:update, :destroy]

  def index
    Crm::KnowledgeCategory.seed_defaults!(Current.account)
    @categories = Current.account.crm_knowledge_categories.ordered
  end

  def create
    @category = Current.account.crm_knowledge_categories.create!(category_params)
  end

  def update
    @category.update!(category_params)
  end

  def destroy
    @category.destroy!
    head :ok
  end

  private

  def fetch_category
    @category = Current.account.crm_knowledge_categories.find(params[:id])
  end

  def check_authorization
    authorize(Crm::KnowledgeCategory)
  end

  def category_params
    params.require(:category).permit(:name, :position)
  end
end
