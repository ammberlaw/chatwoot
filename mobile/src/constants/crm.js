// 客户字段的枚举中文名。国家表直接复用主仓单一事实源，不另抄一份。
export { COUNTRY_LABELS } from '../../../app/javascript/dashboard/routes/dashboard/crm/constants/countries';

export const CUSTOMER_STATUS_LABELS = {
  PROSPECT: '潜在客户',
  FOLLOWING: '跟进中',
  WON: '已成交',
  DORMANT: '休眠',
  LOST: '已流失',
};

export const CUSTOMER_LEVEL_LABELS = { A: 'A 级', B: 'B 级', C: 'C 级', D: 'D 级' };

export const PRODUCT_GROUP_LABELS = {
  TABLET: '平板电脑',
  COMMERCIAL_DISPLAY: '商显工控',
};

export const CONTACT_PREFERENCE_LABELS = {
  EMAIL: '邮件',
  PHONE: '电话',
  WHATSAPP: 'WhatsApp',
  WECHAT: '微信',
};

export const CURRENCY_LABELS = { USD: '美元 USD', CNY: '人民币 CNY', EUR: '欧元 EUR' };

// 跟进方式 / 结果标签：值是后端枚举 code（Crm::FollowUpNote 校验），不是中文字面量
export const FOLLOW_UP_METHOD_LABELS = {
  EMAIL: '邮件',
  PHONE: '电话',
  MEETING: '会议',
  WHATSAPP: 'WhatsApp',
  WECHAT: '微信',
};
export const FOLLOW_UP_RESULT_LABELS = {
  INTERESTED: '有意向',
  WAITING_CUSTOMER: '等客户回复',
  WAITING_INTERNAL: '等内部处理',
  INVALID: '无效',
};

export const OPPORTUNITY_STAGE_LABELS = {
  NEEDS_CONFIRMED: '需求确认',
  SAMPLING: '打样中',
  PENDING_PAYMENT: '待付款',
  WON: '赢单',
  LOST: '输单',
};

export const ORDER_STATUS_LABELS = {
  PENDING_CONFIRMATION: '待确认',
  IN_PRODUCTION: '生产中',
  PENDING_SHIPMENT: '待发货',
  SHIPPED: '已发货',
  COMPLETED: '已完成',
  CANCELLED: '已取消',
};

export const APPROVAL_STATUS_LABELS = {
  pending: '审批中',
  approved: '已通过',
  rejected: '已驳回',
  canceled: '已撤回',
};

export const TRADE_REGION_LABELS = {
  NORTH_AMERICA: '北美',
  EUROPE: '欧洲',
  SOUTH_AMERICA: '南美',
  MIDDLE_EAST: '中东',
  SOUTHEAST_ASIA: '东南亚',
  AFRICA: '非洲',
  OTHER: '其他',
};

export const INDUSTRY_LABELS = {
  RETAIL: '零售',
  WHOLESALE: '批发',
  DISTRIBUTOR: '经销商',
  MANUFACTURING: '制造业',
  ECOMMERCE: '电商',
  OTHER: '其他',
};

export const RISK_LEVEL_LABELS = { LOW: '低', MEDIUM: '中', HIGH: '高' };

// { code: label } → [{ value, label }]，供 <select v-for> 用
export const toOptions = labels =>
  Object.entries(labels).map(([value, label]) => ({ value, label }));
