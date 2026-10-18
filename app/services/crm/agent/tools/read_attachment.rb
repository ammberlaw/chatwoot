# 读客户来信里的附件：询价表、PI、订单确认书 → 抽成型号/数量/单价的明细。
#
# 外贸的询价八成在附件里，正文就一句「see attached」。以前 agent 看得到附件名
# 却读不了内容，业务员还得自己下载、自己照着敲进报价单。
#
# 识别直接复用订单那边的 PI 自动填单（Crm::PiParseService）——同一套抽取逻辑，
# 这边绝不另写一份：那边改了识别规则，这边自动跟上。
#
# 返回的明细刻意排成「型号 | 描述 | 数量 | 单价」一行一项——
# 和 draft_quote / draft_pi 的 items 参数同一个格式，模型抽完能直接拿去建单。
class Crm::Agent::Tools::ReadAttachment < Crm::Agent::Tools::Base
  description '读某封客户来信的附件（PDF/Excel/CSV 的询价单、PI、订单），把里面的品名、规格、数量、单价抽出来，拿到后可以接着建报价单或 PI 草稿。只认能抽出文字的文件，图片和扫描件读不了。邮件ID 和附件序号从 customer_emails 的结果里取。'
  param :email_id, type: 'integer', desc: '邮件ID（customer_emails 结果里每封信开头的那个）'
  param :index, type: 'integer', desc: '读第几个附件，从 1 开始；不传读第一个', required: false

  def execute(email_id:, index: nil)
    email = scope.emails.find_by(id: email_id)
    return "看不到邮件 #{email_id}（可能不在你的权限范围内）。" if email.nil?

    files = email.files.attachments.to_a
    return '这封信没有附件。' if files.empty?

    position = index.to_i.positive? ? index.to_i : 1
    attachment = files[position - 1]
    return "这封信只有 #{files.size} 个附件（#{names(files)}），没有第 #{position} 个。" if attachment.nil?

    parse(attachment)
  end

  private

  def names(files) = files.each_with_index.map { |a, i| "#{i + 1}. #{a.blob.filename}" }.join('　')

  def parse(attachment)
    result = Crm::PiParseService.from_attachment(account: scope.account, user: scope.user,
                                                 attachment: attachment).call
    render(attachment, result)
  rescue Crm::PiParseService::UnsupportedType => e
    "附件「#{attachment.blob.filename}」读不出内容：#{e.message}（扫描件、图片型 PDF 这类抽不出文字）。"
  rescue StandardError => e
    Rails.logger.warn("[crm_agent] read_attachment 失败 blob=#{attachment.blob.id}: #{e.class} #{e.message}")
    "附件「#{attachment.blob.filename}」解析失败：#{e.message}"
  end

  def render(attachment, result)
    [head(attachment, result), items_block(result), tail(result)].compact_blank.join("\n")
  end

  def head(attachment, result)
    parts = ["【附件】#{attachment.blob.filename}"]
    parts << "单号 #{result[:pi_no]}" if result[:pi_no].present?
    parts << "币种 #{result[:currency]}" if result[:currency].present?
    parts << "日期 #{result[:order_date]}" if result[:order_date].present?
    parts << "交期 #{result[:delivery_date]}" if result[:delivery_date].present?
    parts.join('｜')
  end

  def items_block(result)
    rows = Array(result[:line_items])
    return '附件里没抽到明细行。' if rows.empty?

    lines = rows.map { |item| item_line(item) }
    # 列名要写清楚：识别服务吐的是「品名/规格」，型号可能落在任意一列
    # （实测 CSV 里的 WT-IPM104 被归进了规格列）。不说清楚，模型会把品名当型号直接建单。
    "明细（#{rows.size} 项，列依次是 品名 | 规格 | 数量 | 单价；" \
      "建单时型号从前两列里挑准的那个）：\n#{lines.join("\n")}"
  end

  # 抽不到的格子留空而不是填 0：0 会被当成真实单价直接建进单子里。
  def item_line(item)
    [item['name'], item['spec'], num(item['quantity']), num(item['unit_price'])].join(' | ')
  end

  def num(value) = value.blank? ? '' : fnum(value)

  def tail(result)
    parts = []
    parts << "附件上的合计 #{result[:amount]}" if result[:amount].present?
    parts << "运费 #{result[:shipping_cost]}" if result[:shipping_cost].present?
    # 客户名按「这个人名下的客户」模糊匹配（PiParseService 的口径），匹配不上不新建。
    parts << customer_line(result[:customer])
    parts.compact_blank.join('｜')
  end

  def customer_line(info)
    return nil if info.blank? || info[:raw_name].blank?

    return "附件上的客户名「#{info[:raw_name]}」在你名下没匹配到档案" if info[:matched_id].blank?

    "匹配到客户 #{info[:matched_name]}（ID #{info[:matched_id]}）"
  end
end
