# 单据号自动生成：PREFIX-YYYYMMDD-NN（当天序号递增，删单不回填避免撞号）。
# 用法：include Mes::DocumentNumber，并在类里定义 `document_number_prefix`。
# 号列默认 order_no，可覆写 `document_number_column`。
module Mes::DocumentNumber
  extend ActiveSupport::Concern

  included do
    before_validation :generate_document_number, on: :create
  end

  # 撞号自愈：MAX+1 取号在并发建单下会撞号，唯一索引拦下后一个抛 RecordNotUnique。
  # savepoint 包住写入(冲突只回滚本次 INSERT、不牵连外层事务)，清号重算重试，杜绝偶发建单失败。
  def create_or_update(*, **)
    attempts = 0
    begin
      self.class.transaction(requires_new: true) { super }
    rescue ActiveRecord::RecordNotUnique => e
      col = self.class.document_number_column
      raise unless new_record? && e.message.include?(col.to_s) && (attempts += 1) <= 5

      self[col] = nil
      generate_document_number
      retry
    end
  end

  private

  def generate_document_number
    column = self.class.document_number_column
    return if self[column].present?

    prefix = "#{self.class.document_number_prefix}-#{Time.zone.today.strftime('%Y%m%d')}"
    last_seq = self.class.where(account_id: account_id)
                   .where("#{column} LIKE ?", "#{prefix}-%")
                   .pick(Arel.sql("MAX(SPLIT_PART(#{column}, '-', 3)::int)")) || 0
    self[column] = format('%<prefix>s-%<seq>02d', prefix: prefix, seq: last_seq + 1)
  end

  class_methods do
    def document_number_prefix
      raise NotImplementedError, "#{name} must define document_number_prefix"
    end

    def document_number_column
      :order_no
    end
  end
end
