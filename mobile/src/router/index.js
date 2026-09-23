import { createRouter, createWebHashHistory } from 'vue-router';
import { loadCreds } from '@/api/client';

const routes = [
  { path: '/', redirect: '/home' },
  {
    path: '/login',
    name: 'login',
    component: () => import('@/pages/LoginPage.vue'),
    meta: { public: true },
  },
  {
    path: '/home',
    name: 'home',
    component: () => import('@/pages/HomePage.vue'),
    meta: { tab: true, title: '工作台' },
  },
  {
    path: '/customers',
    name: 'customers',
    component: () => import('@/pages/CustomersPage.vue'),
    meta: { tab: true, title: '客户' },
  },
  {
    path: '/private-customers',
    name: 'private-customers',
    component: () => import('@/pages/PrivateCustomersPage.vue'),
    meta: { tab: true, title: '私海客户' },
  },
  {
    path: '/customers/new',
    name: 'customer-new',
    component: () => import('@/pages/CustomerFormPage.vue'),
  },
  {
    path: '/customers/:id',
    name: 'customer-detail',
    component: () => import('@/pages/CustomerDetailPage.vue'),
  },
  {
    path: '/customers/:id/edit',
    name: 'customer-edit',
    component: () => import('@/pages/CustomerFormPage.vue'),
  },
  {
    path: '/messages',
    name: 'messages',
    component: () => import('@/pages/MessagesPage.vue'),
    meta: { tab: true, title: '消息' },
  },
  {
    path: '/mail',
    name: 'mail',
    component: () => import('@/pages/MailPage.vue'),
    meta: { tab: true, title: '邮件' },
  },
  {
    path: '/mail/compose',
    name: 'mail-compose',
    component: () => import('@/pages/MailComposePage.vue'),
  },
  {
    path: '/mail/:id',
    name: 'mail-detail',
    component: () => import('@/pages/MailDetailPage.vue'),
  },
  {
    path: '/approvals',
    name: 'approvals',
    component: () => import('@/pages/ApprovalsPage.vue'),
  },
  // 商机单独一页：它比另外三类多出阶段漏斗、赢单概率、重点标记、公海，
  // 塞进通用组件会把那个组件撑变形
  {
    path: '/opportunities',
    name: 'opportunities',
    component: () => import('@/pages/OpportunitiesPage.vue'),
  },
  // 订单/报价/PI 共用列表与详情组件，靠 meta.kind 区分
  ...[
    { kind: 'order', path: 'orders' },
    { kind: 'quote', path: 'quotes' },
    { kind: 'pi', path: 'pis' },
  ].flatMap(({ kind, path }) => [
    {
      path: `/${path}`,
      name: path,
      component: () => import('@/pages/RecordListPage.vue'),
      meta: { kind },
    },
    {
      path: `/${path}/:id`,
      name: `${kind}-detail`,
      component: () => import('@/pages/RecordDetailPage.vue'),
      meta: { kind },
    },
  ]),
  {
    path: '/opportunities/:id',
    name: 'opportunity-detail',
    component: () => import('@/pages/RecordDetailPage.vue'),
    meta: { kind: 'opportunity' },
  },
  {
    path: '/my-target',
    name: 'my-target',
    component: () => import('@/pages/MyTargetPage.vue'),
  },
  {
    path: '/team-dashboard',
    name: 'team-dashboard',
    component: () => import('@/pages/TeamDashboardPage.vue'),
  },
  {
    path: '/docs',
    name: 'docs',
    component: () => import('@/pages/DocsPage.vue'),
  },
  {
    path: '/docs/:id',
    name: 'doc-detail',
    component: () => import('@/pages/DocDetailPage.vue'),
  },
  {
    path: '/products',
    name: 'products',
    component: () => import('@/pages/ProductsPage.vue'),
  },
  {
    path: '/price-lists/:id',
    name: 'price-list-detail',
    component: () => import('@/pages/PriceListDetailPage.vue'),
  },
  {
    path: '/schedule',
    name: 'schedule',
    component: () => import('@/pages/SchedulePage.vue'),
    meta: { tab: true, title: '日程' },
  },
  {
    path: '/attendance',
    name: 'attendance',
    component: () => import('@/pages/AttendancePage.vue'),
  },
  // MES / ERP：后端在本分支里是齐的，手机端页面还没做，先占位
  {
    path: '/mes',
    name: 'mes',
    component: () => import('@/pages/ModulePlaceholderPage.vue'),
    meta: {
      title: 'MES 生产',
      icon: 'i-ri-building-4-fill',
      planned: ['生产工单', '领料与出入库', '采购申请与采购单', 'BOM 与工艺', '质检', '发货'],
    },
  },
  {
    path: '/erp',
    name: 'erp',
    component: () => import('@/pages/ModulePlaceholderPage.vue'),
    meta: {
      title: 'ERP 财务',
      icon: 'i-ri-scales-3-fill',
      planned: ['凭证与总账', '应收应付', '资金日记账', '财务报表', '固定资产', '期末结账'],
    },
  },
  {
    path: '/more',
    name: 'more',
    component: () => import('@/pages/MorePage.vue'),
    meta: { tab: true, title: '更多' },
  },
  {
    path: '/approvals/new',
    name: 'approval-new',
    component: () => import('@/pages/ApprovalNewPage.vue'),
  },
  {
    path: '/approvals/:id',
    name: 'approval-detail',
    component: () => import('@/pages/ApprovalDetailPage.vue'),
  },
];

// Capacitor 里是 file:// 载入本地包，必须用 hash 路由
const router = createRouter({ history: createWebHashHistory(), routes });

router.beforeEach(async to => {
  if (to.meta.public) return true;
  const c = await loadCreds();
  return c ? true : { name: 'login' };
});

export default router;
