# 写邮件、答客户技术问、报分级价时要翻的资料：已发布价格表 + 产品附加属性 + 销售知识库。
#
# search_products 只给一个挂牌售价，客户问「1000 台什么价、有没有 CE、支架能不能定制」
# 那一行答不了——分级价在价格表里，选配在附加属性里，认证和话术在知识库里。
#
# 三类一次都查：问这种问题的人不知道答案归哪个模块，分三次问等于逼他猜。
class Crm::Agent::Tools::ProductDocs < Crm::Agent::Tools::Base
  description '查产品资料：已发布的分级价格表（按量报价）、产品的附加属性/选配项、销售知识库文档（认证、参数、话术、常见问题）。回答客户技术问题或要按数量报价时用。'
  param :keyword, desc: '型号、产品名、产品线或关键词（如 CE认证、教育平板、支架）'
  param :limit, type: 'integer', desc: '每类最多几条，默认 5，上限 12', required: false

  DOC_CLIP = 800

  def execute(keyword:, limit: 5)
    kw = keyword.to_s.strip
    return '请给型号、产品名或关键词。' if kw.blank?

    n = limit.to_i.positive? ? [limit.to_i, 12].min : 5
    blocks = [price_block(kw, n), attr_block(kw, n), doc_block(kw, n)].compact_blank
    return "资料里没搜到「#{kw}」（价格表、产品附加属性、知识库都查过了）。" if blocks.empty?

    blocks.join("\n\n")
  end

  private

  # 价格表是「一张表配一条产品线」，命中产品线或标题就把整张表的相关行摆出来。
  def price_block(keyword, limit)
    lists = scope.published_price_lists
                 .where('title ILIKE :t OR product_line ILIKE :t', t: "%#{keyword}%")
                 .newest_first.limit(2).to_a
    lists = matching_item_lists(keyword) if lists.empty?
    return nil if lists.empty?

    lists.map { |list| price_table(list, keyword, limit) }.join("\n\n")
  end

  # 表名没命中时，退一步在明细行里搜型号（客户问的往来往是型号，不是产品线名）。
  def matching_item_lists(keyword)
    ids = scope.published_price_lists.joins(:items)
               .where('crm_price_list_items.values::text ILIKE ?', "%#{keyword}%")
               .distinct.limit(2).pluck(:id)
    ids.empty? ? [] : scope.published_price_lists.where(id: ids).newest_first.to_a
  end

  def price_table(list, keyword, limit)
    cols = list.column_defs
    lines = hit_rows(list, keyword).first(limit).map { |i| "— #{row_text(cols, i)}" }
    [table_header(list, cols), *lines, rules_line(list)].compact_blank.join("\n")
  end

  def table_header(list, cols)
    "【价格表】#{list.title}（#{list.product_line}｜#{list.currency}｜生效 #{day(list.effective_on)}）\n" \
      "列：#{cols.pluck('label').join(' ｜ ')}"
  end

  # 命中的行优先；一行都没命中就把整张表给出来（表名命中时本来就是要整张表）。
  def hit_rows(list, keyword)
    rows = list.items.order(:position, :id).to_a
    hit = rows.select { |i| i.values.to_a.join(' ').downcase.include?(keyword.downcase) }
    hit.presence || rows
  end

  def row_text(cols, item)
    cols.each_with_index.map { |col, idx| "#{col['label']} #{item.values.to_a[idx].presence || '—'}" }.join('｜')
  end

  # 阶梯规则、付款条件这些写在表头/规则说明里，报价时该一起看到。
  def rules_line(list)
    text = clip([list.header_note, list.rules_note].compact_blank.join('；'), 300)
    text.blank? ? nil : "规则：#{text}"
  end

  def attr_block(keyword, limit)
    rows = scope.account.crm_product_aux_attributes.where(is_active: true)
                .joins(:product)
                .where('crm_product_aux_attributes.name ILIKE :t OR crm_product_aux_attributes.code ILIKE :t ' \
                       'OR crm_products.sku ILIKE :t OR crm_products.name ILIKE :t', t: "%#{keyword}%")
                .order('crm_products.sku', :position).limit(limit * 3).to_a
    return nil if rows.empty?

    grouped = rows.group_by(&:product)
    "【产品附加属性/选配】\n#{grouped.first(limit).map { |p, list| attr_line(p, list) }.join("\n")}"
  end

  def attr_line(product, attrs)
    "— #{product&.sku || '—'} #{product&.name}：#{attrs.map { |a| "#{a.name}(#{a.code})" }.join('、')}"
  end

  def doc_block(keyword, limit)
    rows = scope.knowledge_docs
                .where('name ILIKE :t OR summary ILIKE :t OR body ILIKE :t OR category ILIKE :t', t: "%#{keyword}%")
                .order(updated_at: :desc).limit(limit).to_a
    return nil if rows.empty?

    "【知识库】共 #{rows.size} 篇：\n#{rows.map { |d| doc_line(d) }.join("\n\n")}"
  end

  def doc_line(doc)
    "— #{doc.name}#{doc.category.present? ? "（#{doc.category}）" : ''}｜#{doc.scope == 'COMPANY' ? '公司库' : '我的个人库'}" \
      "\n  #{clip(doc.summary.presence || doc.body, DOC_CLIP)}"
  end
end
