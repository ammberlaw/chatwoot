# 邮件部件正文的字符集解码（中文邮件兼容），供 IMAP/POP 收件入库使用。
#
# mail 2.8 对已知 charset 的文本部件会自动转成 UTF-8；此时再按 part.charset
# force_encoding 会把正确的 UTF-8 字节二次错解成乱码（GBK 中文邮件事故根因）。
# 这里只在 mail 未转（返回二进制，charset 缺失/未知）时自己转，并对「声明撒谎」
# （标 utf-8 实为 GBK）的邮件按 GB18030 重解补救。
module Crm::MailCharset
  module_function

  # 邮件头字段（主题/发件人/收件人/Message-ID）清洗成合法 UTF-8。
  # 部分中文客户端把 GBK 原始字节直接塞进邮件头、不做 RFC2047 编码，mail gem 原样返回；
  # 这类字节直接入库会触发 PG::CharacterNotInRepertoire，整封邮件被丢（客户来信收不到）。
  # 先按 UTF-8 采信、非法再试 GB18030 补救、仍不行才用 '?' 替换非法字节——绝不丢整封。
  def scrub(str)
    return str if str.nil?

    s = str.to_s
    return s if s.encoding == Encoding::UTF_8 && s.valid_encoding?

    bytes = s.b
    utf8 = bytes.dup.force_encoding('UTF-8')
    return utf8 if utf8.valid_encoding?

    gb = bytes.dup.force_encoding('GB18030')
    return gb.encode('UTF-8', invalid: :replace, undef: :replace) if gb.valid_encoding?

    bytes.force_encoding('UTF-8').scrub('?')
  rescue StandardError
    str.to_s.scrub('?')
  end

  def decoded(part)
    body = part.decoded
    body = body.force_encoding(guessed_charset(part, body)) if body.encoding == Encoding::ASCII_8BIT
    body = salvage_gbk(part, body)
    body.encode('UTF-8', invalid: :replace, undef: :replace)
  rescue StandardError
    part.body.to_s.scrub('?')
  end

  # 声明撒谎的两种残局，都按 GB18030 重解、整串有效才采纳：
  # 1) body 编码无效——直接重贴标签；
  # 2) mail 已把无效字节替换成多个 U+FFFD——回到未转换的原始字节重解
  #    （阈值 ≥3 个替换符，避免误伤恰好含替换符的真 UTF-8 邮件）。
  def salvage_gbk(part, body)
    if !body.valid_encoding?
      regbk = body.dup.force_encoding('GB18030')
      return regbk if regbk.valid_encoding?
    elsif body.count('�') >= 3
      raw = part.body.decoded.dup.force_encoding('GB18030')
      return raw if raw.valid_encoding?
    end
    body
  rescue StandardError
    body
  end

  # charset 缺失时的兜底猜测：先试 UTF-8，无效再试 GB18030（中文外贸邮件最常见）。
  # gb 系声明统一按 GB18030 超集解，兼容声明偏小的服务器。
  def guessed_charset(part, body)
    declared = part.charset.to_s.downcase
    return 'GB18030' if declared.match?(/\Agb(k|2312|18030)\z/)
    return part.charset if declared.present? && Encoding.find(declared)

    body.dup.force_encoding('UTF-8').valid_encoding? ? 'UTF-8' : 'GB18030'
  rescue ArgumentError
    'UTF-8'
  end
end
