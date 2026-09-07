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
    path: '/scan',
    name: 'scan',
    component: () => import('@/pages/ScanPage.vue'),
    meta: { tab: true, title: '扫码' },
  },
  {
    path: '/mail',
    name: 'mail',
    component: () => import('@/pages/MailPage.vue'),
    meta: { tab: true, title: '邮件' },
  },
  {
    path: '/approvals',
    name: 'approvals',
    component: () => import('@/pages/ApprovalsPage.vue'),
    meta: { tab: true, title: '审批' },
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
