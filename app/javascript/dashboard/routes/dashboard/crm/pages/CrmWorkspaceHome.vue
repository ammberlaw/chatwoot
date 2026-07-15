<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import RequestsAPI from 'dashboard/api/oa/approvalRequests';
import ChatAPI from 'dashboard/api/chat/conversations';
import DepartmentsAPI from 'dashboard/api/org/departments';

import Icon from 'dashboard/components-next/icon/Icon.vue';
import wintouchLockup from 'dashboard/assets/images/wintouch/lockup.png';

const router = useRouter();
const { accountScopedRoute } = useAccount();
const currentUser = useMapGetter('getCurrentUser');

const stats = ref({ todo: 0, mine: 0, approverView: true, dept: 0, unread: 0 });
const userName = computed(() => currentUser.value?.name || '');
// 非 CRM 人员（无 crm_role 且非系统管理员）隐藏 CRM 旗舰入口。后端仍以 403 兜底。
const canAccessCrm = computed(() => currentUser.value?.can_access_crm !== false);

// 按时段问候，落地页有温度但不喧哗。
const now = new Date();
const greeting = computed(() => {
  const h = now.getHours();
  if (h < 6) return '夜深了';
  if (h < 12) return '早上好';
  if (h < 14) return '中午好';
  if (h < 18) return '下午好';
  return '晚上好';
});
const WEEK = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
const dateLabel = `${now.getFullYear()}年${now.getMonth() + 1}月${now.getDate()}日 · ${WEEK[now.getDay()]}`;

// 旗舰模块：CRM 独占主视觉。
const HERO = {
  label: 'CRM 客户管理',
  desc: '外贸全流程 · 从客户建档到成交回款',
  icon: 'i-lucide-users',
  to: 'crm_dashboard_index',
  chips: ['客户', '商机', '报价', '订单', '邮件', '资料'],
};

// 已上线的协同模块，各自承载一项真实指标。
const LIVE = computed(() => [
  {
    key: 'oa',
    label: 'OA 审批',
    desc: '请假 · 报销 · 付款流程',
    icon: 'i-lucide-file-check',
    to: 'crm_approvals_index',
    accent: 'blue',
    metric: stats.value.approverView ? stats.value.todo : stats.value.mine,
    metricLabel: stats.value.approverView ? '待我审批' : '我的申请',
    urgent: stats.value.approverView && stats.value.todo > 0,
  },
  {
    key: 'chat',
    label: '团队协同',
    desc: '内部单聊 · 群聊 · 已读回执',
    icon: 'i-lucide-messages-square',
    to: 'crm_team_chat_index',
    accent: 'teal',
    metric: stats.value.unread,
    metricLabel: '未读消息',
    urgent: stats.value.unread > 0,
  },
  {
    key: 'hr',
    label: 'HR 组织人事',
    desc: '组织架构 · 部门 · 成员职位',
    icon: 'i-lucide-network',
    to: 'crm_org_structure_index',
    accent: 'iris',
    metric: stats.value.dept,
    metricLabel: '个部门',
  },
  {
    key: 'docs',
    label: '文档中心',
    desc: '制度 · 流程 · 培训 · 全公司知识',
    icon: 'i-lucide-book-open',
    to: 'crm_doc_center_index',
    accent: 'violet',
  },
]);

// 未上线模块，安静收在底部。ERP/MES 按成员模块权限显隐（管理员全模块）。
const ALL_SOON = [
  { key: 'erp', label: 'ERP 进销存', icon: 'i-lucide-package' },
  { key: 'mes', label: 'MES 生产制造', icon: 'i-lucide-factory' },
  { key: 'schedule', label: '日程 Schedule', icon: 'i-lucide-calendar-days' },
];
const SOON = computed(() => {
  if (currentUser.value?.role === 'administrator') return ALL_SOON;
  const allowed = currentUser.value?.module_access || [];
  return ALL_SOON.filter(
    m => !['erp', 'mes'].includes(m.key) || allowed.includes(m.key)
  );
});

// 每个强调色对应一套 icon 徽章 + hover 描边类。Radix n-* 色阶，全部预声明避免动态 class 被 purge。
const ACCENT = {
  blue: {
    badge: 'bg-n-blue-4 text-n-blue-11',
    metric: 'text-n-blue-11',
    ring: 'hover:border-n-blue-7',
  },
  teal: {
    badge: 'bg-n-teal-4 text-n-teal-11',
    metric: 'text-n-teal-11',
    ring: 'hover:border-n-teal-7',
  },
  iris: {
    badge: 'bg-n-iris-4 text-n-iris-11',
    metric: 'text-n-iris-11',
    ring: 'hover:border-n-iris-7',
  },
  violet: {
    badge: 'bg-n-violet-4 text-n-violet-11',
    metric: 'text-n-violet-11',
    ring: 'hover:border-n-violet-7',
  },
};

const go = to => router.push(accountScopedRoute(to));
const soonHint = label => useAlert(`${label} 模块即将上线`);

onMounted(async () => {
  try {
    const { data } = await RequestsAPI.counts();
    stats.value.todo = data.todo || 0;
    stats.value.mine = data.mine || 0;
    stats.value.approverView = data.approver_view !== false;
  } catch {
    /* 概览统计取不到不阻塞落地页 */
  }
  try {
    const { data } = await ChatAPI.list();
    stats.value.unread = (data.payload || []).reduce(
      (sum, c) => sum + (c.unread_count || 0),
      0
    );
  } catch {
    /* ignore */
  }
  try {
    const { data } = await DepartmentsAPI.get();
    stats.value.dept = (data.payload || []).length;
  } catch {
    /* ignore */
  }
});
</script>

<template>
  <Teleport to="body">
    <div class="fixed inset-0 z-50 overflow-auto bg-n-background">
      <!-- 暖橙氛围光斑，托在不透明底色上，随内容垂直居中而不失衡 -->
      <div
        class="pointer-events-none absolute -top-32 -left-24 size-[560px] rounded-full bg-n-iris-4/70 blur-[130px]"
      />
      <div
        class="pointer-events-none absolute top-40 right-[-8rem] size-[360px] rounded-full bg-n-iris-3/50 blur-[130px]"
      />

      <div
        class="relative flex flex-col justify-center w-full max-w-[1080px] min-h-full mx-auto px-6 sm:px-10 py-12"
      >
        <!-- 品牌 -->
        <img
          :src="wintouchLockup"
          alt="Wintouch"
          class="w-auto h-10 mb-8 self-start"
        />

        <!-- 问候 -->
        <header class="flex flex-wrap items-baseline justify-between gap-x-6 gap-y-1">
          <h1 class="text-4xl font-semibold tracking-tight text-balance text-n-slate-12">
            {{ greeting }}<template v-if="userName">，{{ userName }}</template>
          </h1>
          <p class="text-sm tabular-nums text-n-slate-11">{{ dateLabel }}</p>
        </header>
        <p class="mt-2 text-[15px] text-n-slate-11">
          选择一个系统开始工作。
        </p>

        <!-- 主区：CRM 旗舰 + 协同模块竖列（无 CRM 权限时仅展示共享模块） -->
        <div class="grid gap-4 mt-9 lg:grid-cols-5">
          <!-- CRM 旗舰主卡 -->
          <button
            v-if="canAccessCrm"
            type="button"
            class="group relative flex flex-col overflow-hidden text-left transition-all duration-200 ease-out border shadow-sm outline-none lg:col-span-3 rounded-[28px] border-n-iris-6 bg-n-iris-2 p-7 hover:-translate-y-0.5 hover:shadow-lg hover:border-n-iris-8 focus-visible:ring-2 focus-visible:ring-n-iris-8 motion-reduce:transition-none motion-reduce:hover:translate-y-0"
            @click="go(HERO.to)"
          >
            <!-- 角落大图标水印 -->
            <Icon
              :icon="HERO.icon"
              class="absolute -top-6 -right-6 size-40 text-n-iris-4 transition-transform duration-500 ease-out group-hover:scale-110"
            />
            <div class="relative flex flex-col h-full">
              <div class="flex items-center justify-center bg-n-iris-9 shadow-sm size-14 rounded-2xl">
                <Icon :icon="HERO.icon" class="text-white size-7" />
              </div>
              <h2 class="mt-5 text-2xl font-semibold text-n-iris-12">
                {{ HERO.label }}
              </h2>
              <p class="mt-1.5 text-sm text-n-iris-11">{{ HERO.desc }}</p>

              <!-- 子域 chips -->
              <div class="flex flex-wrap gap-1.5 mt-5">
                <span
                  v-for="chip in HERO.chips"
                  :key="chip"
                  class="px-2.5 py-1 text-xs font-medium rounded-full bg-n-iris-3 text-n-iris-11 ring-1 ring-inset ring-n-iris-5"
                >
                  {{ chip }}
                </span>
              </div>

              <div class="flex items-center gap-1.5 mt-auto pt-7 text-sm font-medium text-n-iris-11">
                进入工作区
                <Icon
                  icon="i-lucide-arrow-right"
                  class="transition-transform duration-200 size-4 group-hover:translate-x-1 motion-reduce:transition-none"
                />
              </div>
            </div>
          </button>

          <!-- 协同模块：有 CRM 旗舰时竖列在侧；否则铺满成网格 -->
          <div
            class="gap-4"
            :class="
              canAccessCrm
                ? 'flex flex-col lg:col-span-2'
                : 'grid sm:grid-cols-2 lg:col-span-5'
            "
          >
            <button
              v-for="m in LIVE"
              :key="m.key"
              type="button"
              class="group relative flex items-center flex-1 gap-4 p-4 text-left transition-all duration-200 ease-out bg-white border shadow-sm outline-none rounded-3xl border-n-weak hover:-translate-y-0.5 hover:shadow-md focus-visible:ring-2 focus-visible:ring-n-slate-8 motion-reduce:transition-none motion-reduce:hover:translate-y-0"
              :class="ACCENT[m.accent].ring"
              @click="go(m.to)"
            >
              <div
                class="flex items-center justify-center shrink-0 size-11 rounded-2xl"
                :class="ACCENT[m.accent].badge"
              >
                <Icon :icon="m.icon" class="size-5" />
              </div>
              <div class="min-w-0">
                <h3 class="text-[15px] font-medium truncate text-n-slate-12">
                  {{ m.label }}
                </h3>
                <p class="text-xs truncate text-n-slate-11">{{ m.desc }}</p>
              </div>
              <!-- 实时指标；无指标的模块显示进入箭头 -->
              <div
                v-if="m.metric !== undefined"
                class="ml-auto text-right shrink-0"
              >
                <div
                  class="text-xl font-semibold tabular-nums"
                  :class="m.urgent ? 'text-n-iris-11' : ACCENT[m.accent].metric"
                >
                  {{ m.metric }}
                </div>
                <div class="text-[11px] text-n-slate-10">{{ m.metricLabel }}</div>
              </div>
              <Icon
                v-else
                icon="i-lucide-arrow-up-right"
                class="ml-auto transition-colors shrink-0 size-4 text-n-slate-9 group-hover:text-n-slate-11"
              />
              <span
                v-if="m.urgent"
                class="absolute rounded-full size-2 top-3 right-3 bg-n-iris-9 ring-2 ring-white"
              />
            </button>
          </div>
        </div>

        <!-- 未上线：安静收底 -->
        <div class="flex flex-wrap items-center gap-2 mt-8">
          <span class="mr-1 text-xs font-medium text-n-slate-10">即将上线</span>
          <button
            v-for="m in SOON"
            :key="m.key"
            type="button"
            class="inline-flex items-center gap-2 py-2 pl-2.5 pr-3.5 text-xs transition-colors rounded-full bg-n-slate-2 text-n-slate-10 border border-transparent hover:border-n-slate-5 hover:text-n-slate-11"
            @click="soonHint(m.label)"
          >
            <Icon :icon="m.icon" class="size-4 text-n-slate-9" />
            {{ m.label }}
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
