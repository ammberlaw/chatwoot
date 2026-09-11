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
    meta: { tab: true, title: '审批' },
  },
  // 商机/订单/报价/PI 四类单据共用列表与详情组件，靠 meta.kind 区分
  ...[
    { kind: 'opportunity', path: 'opportunities' },
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
  },
  {
    path: '/attendance',
    name: 'attendance',
    component: () => import('@/pages/AttendancePage.vue'),
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
