// 「更多」页与工作台快捷入口共用的模块清单。
// 图标用**实心深色字形**：实心比细线有份量（细灰线一排下来很平），
// 深色而不是一物一色——整套配色是黑白灰 + 品牌黄，彩色图标会把这套打散。
// 底部 tab 只放五个高频入口，其余全部收在这里。
export const MODULE_GROUPS = [
  {
    title: '销售',
    items: [
      { name: 'opportunities', label: '商机', icon: 'i-ri-focus-3-fill' },
      { name: 'orders', label: '销售订单', icon: 'i-ri-box-3-fill' },
      { name: 'quotes', label: '报价单', icon: 'i-ri-file-text-fill' },
      { name: 'pis', label: 'PI 形式发票', icon: 'i-ri-bill-fill' },
      { name: 'products', label: '产品与核价', icon: 'i-ri-price-tag-3-fill' },
    ],
  },
  {
    title: '数据',
    items: [
      { name: 'my-target', label: '我的目标', icon: 'i-ri-trophy-fill' },
      { name: 'team-dashboard', label: '团队看板', icon: 'i-ri-bar-chart-box-fill' },
    ],
  },
  {
    title: '生产与财务',
    items: [
      { name: 'mes', label: 'MES 生产', icon: 'i-ri-building-4-fill' },
      { name: 'erp', label: 'ERP 财务', icon: 'i-ri-scales-3-fill' },
    ],
  },
  {
    title: '办公',
    items: [
      { name: 'approvals', label: 'OA 审批', icon: 'i-ri-file-list-3-fill' },
      { name: 'attendance', label: '考勤打卡', icon: 'i-ri-fingerprint-fill' },
      { name: 'docs', label: '知识库', icon: 'i-ri-book-2-fill' },
    ],
  },
];

// MES / ERP 是和 CRM 同级的子系统，不混进「常用」的快捷入口里，
// 工作台上单独两张大卡。这里只是给「更多」页列表用。
export const SUBSYSTEMS = [
  {
    name: 'mes',
    label: 'MES 生产',
    desc: '工单 · 库存 · 采购',
    icon: 'i-ri-building-4-fill',
  },
  {
    name: 'erp',
    label: 'ERP 财务',
    desc: '凭证 · 报表 · 往来',
    icon: 'i-ri-scales-3-fill',
  },
];

// 扁平清单：工作台的横滑「常用」直接用它
export const ALL_MODULES = MODULE_GROUPS.flatMap(g => g.items);

// 工作台九宫格：从上面挑最高频的几个，顺序即展示顺序
export const HOME_SHORTCUTS = [
  'approvals',
  'attendance',
  'orders',
  'opportunities',
  'quotes',
  'products',
  'my-target',
  'docs',
];
