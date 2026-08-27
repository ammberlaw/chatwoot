# 报价明细：挂在报价单下（index/create），改删按 id 直达。
class Api::V1::Accounts::Crm::QuoteLineItemsController < Api::V1::Accounts::Crm::BaseController
  before_action :check_authorization
  before_action :fetch_line_item, only: [:update, :destroy]

  def index
    @line_items = visible_quotes.find(params[:quote_id]).line_items.order(:id)
  end

  def create
    quote = visible_quotes.find(params[:quote_id])
    @line_item = quote.line_items.create!(line_item_params.merge(account_id: Current.account.id))
  end

  def update
    @line_item.update!(line_item_params)
  end

  def destroy
    @line_item.destroy!
    head :ok
  end

  private

  # 明细按 id 直达也必须收口到可见报价单，否则任意成员可越权改删他人报价明细。
  def fetch_line_item
    @line_item = Current.account.crm_quote_line_items
                        .where(crm_quote_id: visible_quotes.select(:id)).find(params[:id])
  end

  def visible_quotes
    scope_docs_visible(Current.account.crm_quotes)
  end

  def check_authorization
    authorize(Crm::Quote)
  end

  def line_item_params
    params.require(:line_item).permit(
      :name, :crm_product_id, :product_name_snapshot, :spec_snapshot,
      :quantity, :unit_price_micros, :amount_micros, :remark
    )
  end
end
