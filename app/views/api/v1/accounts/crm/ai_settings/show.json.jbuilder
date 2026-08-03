# api_key 不回显明文：只告知是否已配置 + 尾 4 位，供前端显示「已配置 ••••abcd」。
key = @setting.api_key.to_s
json.configured key.present?
json.key_hint key.present? ? key[-4..] : nil
json.model @setting.model
json.api_base @setting.api_base
