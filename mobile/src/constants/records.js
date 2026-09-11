// 商机 / 订单 / 报价 / PI 四类单据在移动端结构一致（列表 → 详情），
// 差别只在字段映射，所以收成一份配置，页面只有薄薄一层。
import {
  OPPORTUNITY_STAGE_LABELS,
  ORDER_STATUS_LABELS,
  COUNTRY_LABELS,
} from './crm';
import { money, shortDate } from '@/utils/format';

export const QUOTE_STATUS_LABELS = {
  DRAFT: '草稿',
  SENT: '已发送',
  CONFIRMED: '已确认',
  EXPIRED: '已过期',
};

export const PI_STATUS_LABELS = { DRAFT: '草稿', PAID: '已付款', VOID: '已作废' };

// 状态底色统一在这里定，四个页面共用一套观感
const TONE = {
  neutral: 'bg-n-alpha-1 text-n-slate-11',
  info: 'bg-n-iris-3 text-n-iris-11',
  good: 'bg-n-teal-3 text-n-teal-11',
  warn: 'bg-n-amber-3 text-n-amber-11',
  bad: 'bg-n-ruby-3 text-n-ruby-11',
};

export const RECORDS = {
  opportunity: {
    title: '商机',
    searchable: false,
    statusKey: 'sales_stage',
    statusLabels: OPPORTUNITY_STAGE_LABELS,
    statusTone: {
      NEEDS_CONFIRMED: TONE.neutral,
      SAMPLING: TONE.info,
      PENDING_PAYMENT: TONE.warn,
      WON: TONE.good,
      LOST: TONE.bad,
    },
    // 列表行：主标题 / 副标题 / 右侧金额
    row: r => ({
      title: r.name,
      subtitle: [r.customer_name, r.expected_close_date && `预计 ${shortDate(r.expected_close_date)}`]
        .filter(Boolean)
        .join(' · '),
      amount: money(r.amount_micros, r.currency),
    }),
    detail: r => [
      { label: '客户', value: r.customer_name },
      { label: '金额', value: money(r.amount_micros, r.currency) },
      { label: '赢单概率', value: r.probability != null ? `${r.probability}%` : '' },
      { label: '预计成交', value: r.expected_close_date && shortDate(r.expected_close_date) },
      { label: '当前需求', value: r.current_need },
      { label: '下一步', value: r.next_action },
      { label: '竞争对手', value: r.competitor },
      { label: '输单原因', value: r.loss_reason },
      { label: '负责人', value: r.owner_name },
      { label: '备注', value: r.opportunity_remark },
    ],
  },

  order: {
    title: '销售订单',
    searchable: true,
    statusKey: 'status',
    statusLabels: ORDER_STATUS_LABELS,
    statusTone: {
      PENDING_CONFIRMATION: TONE.neutral,
      IN_PRODUCTION: TONE.info,
      PENDING_SHIPMENT: TONE.warn,
      SHIPPED: TONE.info,
      COMPLETED: TONE.good,
      CANCELLED: TONE.bad,
    },
    row: r => ({
      title: r.order_no || r.name,
      subtitle: [r.customer_name, r.order_date && shortDate(r.order_date)]
        .filter(Boolean)
        .join(' · '),
      amount: money(r.order_amount_micros, r.order_currency),
    }),
    // 成本 / 毛利字段后端会返回，但移动端是销售视角，一律不渲染
    detail: r => [
      { label: '订单号', value: r.order_no },
      { label: '订单名', value: r.name },
      { label: 'PI 号', value: r.pi_no },
      { label: '客户', value: r.customer_name },
      { label: '国家', value: COUNTRY_LABELS[r.customer_country] || r.customer_country },
      { label: '金额', value: money(r.order_amount_micros, r.order_currency) },
      { label: '运费', value: r.shipping_micros ? money(r.shipping_micros, r.order_currency) : '' },
      { label: '下单日期', value: r.order_date && shortDate(r.order_date) },
      { label: '交期', value: r.delivery_date && shortDate(r.delivery_date) },
      { label: '负责人', value: r.owner_name },
      { label: '跟单', value: r.handled_by_name },
      { label: '备注', value: r.remark },
    ],
    itemsKey: 'line_items',
    filesKey: 'files',
  },

  quote: {
    title: '报价单',
    searchable: true,
    statusKey: 'status',
    statusLabels: QUOTE_STATUS_LABELS,
    statusTone: {
      DRAFT: TONE.neutral,
      SENT: TONE.info,
      CONFIRMED: TONE.good,
      EXPIRED: TONE.warn,
    },
    row: r => ({
      title: r.quote_no || r.name,
      subtitle: [r.customer_name, r.quote_date && shortDate(r.quote_date)]
        .filter(Boolean)
        .join(' · '),
      amount: money(r.total_amount_micros, r.quote_currency),
    }),
    detail: r => [
      { label: '报价号', value: r.quote_no },
      { label: '名称', value: r.name },
      { label: '客户', value: r.customer_name },
      { label: '联系人', value: r.contact_name },
      { label: '小计', value: money(r.subtotal_micros, r.quote_currency) },
      {
        label: '折扣',
        value: r.discount_amount_micros ? money(r.discount_amount_micros, r.quote_currency) : '',
      },
      {
        label: '运费',
        value: r.shipping_fee_micros ? money(r.shipping_fee_micros, r.quote_currency) : '',
      },
      { label: '税费', value: r.tax_amount_micros ? money(r.tax_amount_micros, r.quote_currency) : '' },
      { label: '合计', value: money(r.total_amount_micros, r.quote_currency) },
      { label: '报价日期', value: r.quote_date && shortDate(r.quote_date) },
      { label: '有效期至', value: r.valid_until && shortDate(r.valid_until) },
      { label: '负责人', value: r.owner_name },
      { label: '备注', value: r.remark },
    ],
    itemsKey: 'line_items',
  },

  pi: {
    title: 'PI 形式发票',
    searchable: true,
    statusKey: 'status',
    statusLabels: PI_STATUS_LABELS,
    statusTone: { DRAFT: TONE.neutral, PAID: TONE.good, VOID: TONE.bad },
    row: r => ({
      title: r.pi_no,
      subtitle: [r.buyer_company || r.customer_name, r.pi_date && shortDate(r.pi_date)]
        .filter(Boolean)
        .join(' · '),
      amount: money(r.total_amount_micros, r.currency),
    }),
    detail: r => [
      { label: 'PI 号', value: r.pi_no },
      { label: '买方', value: r.buyer_company || r.customer_name },
      { label: '联系人', value: r.attention },
      { label: '买方邮箱', value: r.buyer_email },
      { label: '买方电话', value: r.buyer_tel },
      { label: '买方地址', value: r.buyer_address },
      { label: '起运港', value: r.port_of_shipment },
      { label: '目的港', value: r.port_of_destination },
      { label: '运输方式', value: r.shipping_method },
      {
        label: r.shipping_cost_label || '运费',
        value: r.shipping_cost_micros ? money(r.shipping_cost_micros, r.currency) : '',
      },
      { label: '合计', value: money(r.total_amount_micros, r.currency) },
      { label: 'PI 日期', value: r.pi_date && shortDate(r.pi_date) },
      { label: '负责人', value: r.owner_name },
      { label: '备注', value: r.remark },
    ],
    itemsKey: 'items',
  },
};
