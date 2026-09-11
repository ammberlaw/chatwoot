// 「更多」页与工作台快捷入口共用的模块清单。
// 底部 tab 只放四个高频入口，其余全部收在这里，按分组列出。
export const MODULE_GROUPS = [
  {
    title: '销售',
    items: [
      { name: 'opportunities', label: '商机', icon: 'i-lucide-target' },
      { name: 'orders', label: '销售订单', icon: 'i-lucide-package' },
      { name: 'quotes', label: '报价单', icon: 'i-lucide-file-text' },
      { name: 'pis', label: 'PI 形式发票', icon: 'i-lucide-receipt' },
      { name: 'products', label: '产品与核价', icon: 'i-lucide-boxes' },
    ],
  },
  {
    title: '数据',
    items: [
      { name: 'my-target', label: '我的目标', icon: 'i-lucide-goal' },
      { name: 'team-dashboard', label: '团队看板', icon: 'i-lucide-chart-no-axes-column' },
    ],
  },
  {
    title: '办公',
    items: [
      { name: 'schedule', label: '日程', icon: 'i-lucide-calendar-days' },
      { name: 'attendance', label: '考勤打卡', icon: 'i-lucide-fingerprint' },
      { name: 'docs', label: '知识库', icon: 'i-lucide-book-open' },
    ],
  },
];

// 工作台九宫格：从上面挑最高频的几个，顺序即展示顺序
export const HOME_SHORTCUTS = [
  'attendance',
  'schedule',
  'orders',
  'opportunities',
  'quotes',
  'products',
  'my-target',
  'docs',
];
