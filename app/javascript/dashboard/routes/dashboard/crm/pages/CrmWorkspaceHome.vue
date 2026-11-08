<script setup>
/* global axios */
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import types from 'dashboard/store/mutation-types';
import { useCrmFinanceOnly } from 'dashboard/composables/useCrmFinanceOnly';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import RequestsAPI from 'dashboard/api/oa/approvalRequests';
import ErpDashboardAPI from 'dashboard/api/erp/dashboard';
import ChatAPI from 'dashboard/api/chat/conversations';
import ScheduleAPI from 'dashboard/api/crm/scheduleEvents';

import Icon from 'dashboard/components-next/icon/Icon.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import SidebarProfileMenu from 'dashboard/components-next/sidebar/SidebarProfileMenu.vue';
import WootKeyShortcutModal from 'dashboard/components/widgets/modal/WootKeyShortcutModal.vue';
import CrmQuickClock from 'dashboard/components-next/CRM/CrmQuickClock.vue';
import wintouchLockup from 'dashboard/assets/images/wintouch/login-card-wordmark-rounded.png';
import WorkspaceDesktop from 'dashboard/components-next/CRM/WorkspaceDesktop.vue';
import WorkspaceWallpaperPicker from 'dashboard/components-next/CRM/WorkspaceWallpaperPicker.vue';
import WallpaperAPI from 'dashboard/api/workspaceWallpaper';
import {
  WORKSPACE_CARDS,
  defaultWorkspaceCardOpacity,
} from 'dashboard/helper/workspaceCardOpacity';
import MesProductionOrderAPI from 'dashboard/api/mes/productionOrders';

const router = useRouter();
const { t } = useI18n();
const { accountScopedRoute, accountId } = useAccount();
const currentUser = useMapGetter('getCurrentUser');
const store = useStore();

const stats = ref({ todo: 0, mine: 0, approverView: true, unread: 0 });

const showShortcutModal = ref(false);
const profileMenuOpen = ref(false);
const wallpaperPicker = ref(null);
const wallpaperUrl = ref('');
const cardOpacity = ref(defaultWorkspaceCardOpacity());
const appearancePreview = ref(null);
const appearanceLoading = ref(true);
const appearanceLoaded = ref(false);
const displayedWallpaper = computed(
  () => appearancePreview.value?.url ?? wallpaperUrl.value
);
const displayedCardOpacity = computed(
  () => appearancePreview.value?.cardOpacity ?? cardOpacity.value
);
const updateWorkspaceAppearance = settings => {
  wallpaperUrl.value = settings.url || '';
  cardOpacity.value = settings.card_opacity || defaultWorkspaceCardOpacity();
  store.commit(types.SET_CURRENT_USER_UI_SETTINGS, {
    uiSettings: { workspace_card_opacity: cardOpacity.value },
  });
};
const loadWorkspaceAppearance = async () => {
  appearanceLoading.value = true;
  try {
    const { data } = await WallpaperAPI.get();
    updateWorkspaceAppearance(data);
    appearanceLoaded.value = true;
  } catch {
    appearanceLoaded.value = false;
  } finally {
    appearanceLoading.value = false;
  }
};
onMounted(loadWorkspaceAppearance);
const openWallpaperPicker = async () => {
  if (appearanceLoading.value) return;
  if (!appearanceLoaded.value) await loadWorkspaceAppearance();
  if (!appearanceLoaded.value) {
    useAlert(t('CRM.WORKSPACE_WALLPAPER.LOAD_ERROR'));
    return;
  }
  wallpaperPicker.value.open();
};

// 首页卡片真实数据（当前用户视角）。
const homeStats = ref(null);
const crmStats = computed(() => homeStats.value?.crm || {});
// 新客开发待处理：判像买家、分数够高、有联系人、不是同事已有客户的那批。
const leadStats = computed(() => homeStats.value?.leads || {});
const hrDays = computed(() => homeStats.value?.hr?.days || []);
const attendancePercent = computed(() => {
  const days = hrDays.value.filter(d => d.workday);
  return days.length
    ? Math.round((days.filter(d => d.present).length / days.length) * 100)
    : 0;
});
const hrAllPresent = computed(() => homeStats.value?.hr?.all_present);
const hrLabel = computed(() => {
  const wd = hrDays.value.filter(d => d?.workday);
  if (!wd.length) return hrAllPresent.value === false ? '—' : '全勤';
  const present = wd.filter(d => d.present).length;
  return present >= wd.length ? '全勤' : `${present}/${wd.length}`;
});

// 工作台优先显示 CRM 英文名，未设置回退中文名。
const userName = computed(
  () => currentUser.value?.crm_name || currentUser.value?.name || ''
);
// 权限门：非 CRM 人员看到置灰旗舰卡（不可进入，后端 403 兜底）。
const canAccessCrm = computed(
  () => currentUser.value?.can_access_crm !== false
);
// 纯财务（有 crm_finance、无 crm_role）：CRM 主体不开，但销售订单/PI 只读放行。
// 卡片要能点，且落到销售订单——CRM 看板他们进不去，点了会被路由弹回来。
const { isCrmFinanceOnly } = useCrmFinanceOnly();
const canOpenCrmCard = computed(
  () => canAccessCrm.value || isCrmFinanceOnly.value
);
const crmCardTarget = computed(() =>
  canAccessCrm.value ? 'crm_dashboard_index' : 'crm_sales_orders_index'
);
// TikTok：管理层/财务/TK 部门成员可见（后端派生 can_access_tiktok）。
const canAccessTiktok = computed(
  () => currentUser.value?.can_access_tiktok === true
);
// 财务 ERP：仅管理员/副管理员/财务岗可见（后端派生 can_access_erp）。
// 承载成本/供应商/毛利，销售端连入口都不显示——不是置灰而是整卡不渲染。
const canAccessErp = computed(() => currentUser.value?.can_access_erp === true);
const visibleWorkspaceCards = computed(() =>
  WORKSPACE_CARDS.filter(
    ({ id }) =>
      (id !== 'erp' || canAccessErp.value) &&
      (id !== 'tiktok' || canAccessTiktok.value)
  ).map(({ id }) => id)
);

const erpDraftCount = ref(null);
onMounted(async () => {
  if (!canAccessErp.value) return;
  try {
    const { data } = await ErpDashboardAPI.show();
    erpDraftCount.value = data.kpis?.draft_voucher_count ?? null;
  } catch {
    /* 财务统计不可用时显示未接入状态。 */
  }
});

// OA 真实待办数（审批人看待我审批，其余看我的申请）。
const oaMetric = computed(() =>
  stats.value.approverView ? stats.value.todo : stats.value.mine
);

// 按时段问候。
const now = new Date();
const greeting = computed(() => {
  const h = now.getHours();
  if (h < 6) return '夜深了';
  if (h < 12) return '早上好';
  if (h < 14) return '中午好';
  if (h < 18) return '下午好';
  return '晚上好';
});
const calendarMonth = ref(new Date(now.getFullYear(), now.getMonth(), 1));
const monthLabel = computed(
  () =>
    `${calendarMonth.value.getFullYear()}年${calendarMonth.value.getMonth() + 1}月`
);
const changeCalendarMonth = offset => {
  calendarMonth.value = new Date(
    calendarMonth.value.getFullYear(),
    calendarMonth.value.getMonth() + offset,
    1
  );
};
const todayNum = now.getDate();

// 本月日程（真实数据）：主栏日历打点 + 今日议程。
const monthEvents = ref([]);
const pad = n => String(n).padStart(2, '0');
const todayStr = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(todayNum)}`;
const eventsByDate = computed(() => {
  const map = {};
  monthEvents.value.forEach(o => {
    (map[o.occurrence_date] ||= []).push(o);
  });
  return map;
});
const todayEvents = computed(() =>
  (eventsByDate.value[todayStr] || [])
    .slice()
    .sort((a, b) => (a.starts_at < b.starts_at ? -1 : 1))
);
const hhmm = iso => (iso ? iso.slice(11, 16) : '');

const calendarEvents = ref([]);
watch(
  () => [calendarMonth.value, accountId.value],
  async (_, __, onCleanup) => {
    let active = true;
    onCleanup(() => {
      active = false;
    });
    calendarEvents.value = [];
    const year = calendarMonth.value.getFullYear();
    const month = calendarMonth.value.getMonth();
    if (year === now.getFullYear() && month === now.getMonth()) return;
    try {
      const { data } = await ScheduleAPI.get(accountId.value, {
        from: `${year}-${pad(month + 1)}-01`,
        to: `${year}-${pad(month + 1)}-${new Date(year, month + 1, 0).getDate()}`,
      });
      if (active) calendarEvents.value = data.payload || [];
    } catch {
      /* 月份请求失败不影响今日议程。 */
    }
  },
  { immediate: true }
);
const calendarEventDates = computed(
  () => new Set(calendarEvents.value.map(event => event.occurrence_date))
);

// 当月日历（周一起），今日高亮，有安排的日子打点。
const calCells = computed(() => {
  const y = calendarMonth.value.getFullYear();
  const m = calendarMonth.value.getMonth();
  const startDow = (new Date(y, m, 1).getDay() + 6) % 7; // 周一=0
  const daysInMonth = new Date(y, m + 1, 0).getDate();
  const prevDays = new Date(y, m, 0).getDate();
  const cells = [];
  for (let i = 0; i < startDow; i += 1)
    cells.push({ n: prevDays - startDow + 1 + i, mut: true });
  for (let d = 1; d <= daysInMonth; d += 1) {
    const key = `${y}-${pad(m + 1)}-${pad(d)}`;
    cells.push({
      n: d,
      mut: false,
      now: key === todayStr,
      has: !!eventsByDate.value[key] || calendarEventDates.value.has(key),
    });
  }
  let next = 1;
  while (cells.length % 7 !== 0) cells.push({ n: next++, mut: true });
  return cells;
});

// MES 待办数（待我审批 + 待我接单 + 待我审的出库单）。生产端反馈：有待办时
// 首页完全没提示，要点进 MES 才看得到，经常漏单或误了时间。
const mesTodo = ref(0);

const go = to => router.push(accountScopedRoute(to));
const soon = label => useAlert(`${label} 即将上线`);

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
    const first = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-01`;
    const lastDay = new Date(
      now.getFullYear(),
      now.getMonth() + 1,
      0
    ).getDate();
    const last = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(lastDay)}`;
    const { data } = await ScheduleAPI.get(accountId.value, {
      from: first,
      to: last,
    });
    monthEvents.value = data.payload || [];
  } catch {
    /* 日程取不到不阻塞落地页 */
  }
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/crm/home_stats`
    );
    homeStats.value = data;
  } catch {
    /* 首页卡片真实数据取不到不阻塞 */
  }
  try {
    const { data } = await MesProductionOrderAPI.todoCount();
    mesTodo.value = data?.total || 0;
  } catch {
    /* 没 MES 权限或取不到就不显示角标，不阻塞落地页 */
  }
});
</script>

<template>
  <Teleport to="body">
    <div
      :class="{ '!z-[60]': profileMenuOpen || showShortcutModal }"
      class="wsh-root !font-sans antialiased [&_.text-heading-2]:!font-medium [&_.text-heading-3]:!font-medium !bg-[#f6f7f8] !bg-none md:!p-0 min-[1100px]:!overflow-hidden"
    >
      <img
        v-if="displayedWallpaper"
        :src="displayedWallpaper"
        alt=""
        class="pointer-events-none fixed inset-0 z-0 h-dvh w-screen object-cover"
      />
      <WorkspaceWallpaperPicker
        ref="wallpaperPicker"
        :url="wallpaperUrl"
        :card-opacity="cardOpacity"
        :card-ids="visibleWorkspaceCards"
        @preview="appearancePreview = $event"
        @update="updateWorkspaceAppearance"
      />
      <div
        class="wsh-actions md:!top-3 md:!right-[max(2rem,calc((100vw-1216px)/2))]"
      >
        <button
          type="button"
          :aria-label="$t('CRM.WORKSPACE_WALLPAPER.TITLE')"
          :title="$t('CRM.WORKSPACE_WALLPAPER.TITLE')"
          :disabled="appearanceLoading"
          :aria-busy="appearanceLoading"
          class="grid size-10 place-items-center rounded-full border border-white/70 bg-white/75 text-[#20241f] backdrop-blur-md hover:bg-white/95 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 disabled:cursor-wait disabled:opacity-50"
          @click="openWallpaperPicker"
        >
          <Icon icon="i-lucide-image" class="size-4" />
        </button>
        <SidebarProfileMenu
          placement="topbar"
          @close="profileMenuOpen = false"
          @open-key-shortcut-modal="showShortcutModal = true"
        >
          <template #trigger="{ toggle, isOpen }">
            <button
              type="button"
              aria-label="用户菜单"
              :aria-expanded="isOpen"
              class="flex h-10 items-center gap-2 rounded-full border border-white/70 bg-white/75 py-1 pl-1 pr-3 text-left text-[#20241f] backdrop-blur-md hover:bg-white/95 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#819452]"
              @click="
                toggle();
                profileMenuOpen = !isOpen;
              "
            >
              <Avatar
                :size="30"
                :name="userName || currentUser?.available_name || '用户'"
                :src="currentUser?.avatar_url || ''"
                rounded-full
              />
              <span
                class="hidden max-w-32 truncate text-heading-3 font-semibold sm:block"
                >{{ userName || currentUser?.available_name }}</span>
              <Icon
                icon="i-lucide-chevron-down"
                class="size-3.5 text-[#70766d]"
              />
            </button>
          </template>
        </SidebarProfileMenu>
      </div>
      <WootKeyShortcutModal
        :show="showShortcutModal"
        @close="showShortcutModal = false"
        @clickaway="showShortcutModal = false"
      />

      <div class="wsh-wrap relative z-[1] !max-w-[1680px] !p-0 md:!m-auto">
        <main class="min-w-0">
          <div class="wsh-top !items-center !mb-3 px-4 pt-1 pb-1 md:!hidden">
            <div class="grid min-w-0 grid-cols-1 gap-1 md:pr-80">
              <img
                :src="wintouchLockup"
                alt="Wintouch"
                class="wsh-logo md:!hidden sm:col-span-2 !mb-2 !h-auto !w-[125px] shrink-0"
              />
              <h1
                class="wsh-hello !m-0 !text-heading-1 !tracking-normal !leading-snug !font-semibold"
              >
                {{ greeting
                }}<template v-if="userName">，{{ userName }}</template>
              </h1>
              <div
                class="wsh-sub !mt-0 !text-label-small !font-normal !leading-relaxed"
              >
                让工作井然有序
              </div>
            </div>
            <!-- 手机端右上角快捷打卡（仅紫色圆按钮，一键上/下班打卡）；桌面隐藏 -->
            <CrmQuickClock compact class="self-center shrink-0 md:hidden" />
          </div>

          <!-- ─── 手机端一级界面：紧凑网格排版（≤767px 独占，桌面隐藏；配色沿用）─── -->
          <div class="wsh-m">
            <!-- 两大主入口：CRM / MES -->
            <div class="m-duo">
              <button
                type="button"
                class="m-big c-crm"
                :class="{ locked: !canOpenCrmCard }"
                :disabled="!canOpenCrmCard"
                @click="go(crmCardTarget)"
              >
                <span
                  class="blob"
                  style="width: 120px; height: 120px; right: -30px; top: -40px"
                />
                <div class="m-big-l"><Icon icon="i-lucide-users" /> CRM</div>
                <div class="m-big-n">
                  客户管理 · {{ crmStats.follow_up_due ?? 0 }} 待跟进
                </div>
                <div v-if="canOpenCrmCard" class="m-big-go">
                  进入 <Icon icon="i-lucide-arrow-right" />
                </div>
                <div v-else class="m-big-go">
                  <Icon icon="i-lucide-lock" /> 未开通
                </div>
              </button>
              <button
                type="button"
                class="m-big c-mes"
                @click="go('mes_dashboard_index')"
              >
                <span
                  class="blob"
                  style="
                    width: 120px;
                    height: 120px;
                    right: -30px;
                    bottom: -40px;
                  "
                />
                <div class="m-big-l"><Icon icon="i-lucide-factory" /> MES</div>
                <div class="m-big-n">生产制造 · 工单排产</div>
                <div class="m-big-go">
                  进入 <Icon icon="i-lucide-arrow-right" />
                </div>
              </button>
            </div>

            <!-- 图标快启 -->
            <div class="m-launch">
              <button
                type="button"
                class="m-lz"
                @click="go('crm_approvals_index')"
              >
                <span class="m-lc g-lime">
                  <Icon icon="i-lucide-clipboard-check" />
                  <span v-if="oaMetric" class="m-badge">{{ oaMetric }}</span>
                </span>
                <span class="m-ll">OA 审批</span>
              </button>
              <button
                type="button"
                class="m-lz"
                @click="go('crm_team_chat_index')"
              >
                <span class="m-lc g-teal">
                  <Icon icon="i-lucide-messages-square" />
                  <span v-if="stats.unread" class="m-badge">
                    {{ stats.unread }}
                  </span>
                </span>
                <span class="m-ll">团队协同</span>
              </button>
              <button
                type="button"
                class="m-lz"
                @click="go('crm_org_structure_index')"
              >
                <span class="m-lc g-sky"><Icon icon="i-lucide-network" /></span>
                <span class="m-ll">HR 人事</span>
              </button>
              <button
                type="button"
                class="m-lz"
                @click="go('crm_doc_center_index')"
              >
                <span class="m-lc g-violet">
                  <Icon icon="i-lucide-folder-open" />
                </span>
                <span class="m-ll">文档中心</span>
              </button>

              <button
                v-if="canAccessTiktok"
                type="button"
                class="m-lz"
                @click="go('tiktok_dashboard_index')"
              >
                <span class="m-lc g-cyan">
                  <Icon icon="i-lucide-shopping-bag" />
                </span>
                <span class="m-ll">TikTok</span>
              </button>
              <button type="button" class="m-lz" @click="soon('ERP 进销存')">
                <span class="m-lc g-gray"><Icon icon="i-lucide-package"/></span>
                <span class="m-ll">ERP</span>
              </button>
            </div>

            <div class="m-section-t">今日概览</div>
            <div class="m-drow">
              <button
                type="button"
                class="m-dcard"
                @click="go('crm_schedule_index')"
              >
                <span class="m-dc g-blue">
                  <Icon icon="i-lucide-calendar-days" />
                </span>
                <div>
                  <div class="m-dn">{{ todayEvents.length }}</div>
                  <div class="m-du">今日日程</div>
                </div>
              </button>
              <button
                type="button"
                class="m-dcard"
                @click="go('crm_org_structure_index')"
              >
                <span class="m-dc g-sky"><Icon icon="i-lucide-network" /></span>
                <div>
                  <div class="m-dn">{{ hrLabel }}</div>
                  <div class="m-du">本周出勤</div>
                </div>
              </button>
            </div>

            <!-- 今日安排 -->
            <div class="m-section-t">
              今日安排 <span class="m-count">{{ todayEvents.length }} 项</span>
            </div>
            <div class="m-agenda">
              <template v-if="todayEvents.length">
                <button
                  v-for="e in todayEvents"
                  :key="e.id + e.starts_at"
                  type="button"
                  class="m-ev"
                  :class="e.color"
                  @click="go('crm_schedule_index')"
                >
                  <div class="m-ev-tm">
                    {{ e.all_day ? '全天' : hhmm(e.starts_at) }}
                  </div>
                  <div class="m-ev-b">
                    <b>{{ e.title }}</b>
                    <small>{{ e.owner_name }}</small>
                  </div>
                </button>
              </template>
              <button
                v-else
                type="button"
                class="m-ev-empty"
                @click="go('crm_schedule_index')"
              >
                今天暂无安排 · 点此新建
              </button>
            </div>
          </div>

          <WorkspaceDesktop
            :card-opacity="displayedCardOpacity"
            :context="{
              userName,
              greeting,
              crmStats,
              leadStats,
              hrDays,
              attendancePercent,
              canAccessCrm,
              canOpenCrmCard,
              isCrmFinanceOnly,
              crmCardTarget,
              canAccessErp,
              canAccessTiktok,
              erpDraftCount,
              oaMetric,
              stats,
              mesTodo,
              monthLabel,
              calCells,
              todayEvents,
              todayNum,
            }"
            @go="go"
            @change-month="changeCalendarMonth"
            @open-order="
              orderNo =>
                router.push(
                  accountScopedRoute(
                    'mes_production_orders_index',
                    {},
                    orderNo ? { q: orderNo } : {}
                  )
                )
            "
          />

          <div
            class="wsh-foot md:!hidden md:flex md:items-center md:justify-center md:gap-3 md:[&_.wsh-beian]:!mt-0 !mt-3 !text-label-small !text-[10px] !font-normal !text-[#73796e]"
          >
            WintouchSpace · Designed &amp; Developed by Amber Law
            <span class="wsh-beian">粤ICP备2026106012号-1</span>
          </div>
        </main>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
.wsh-root {
  position: fixed;
  inset: 0;
  z-index: 50;
  overflow: auto;
  color: #232833;
  background: radial-gradient(
      58vw 52vh at 8% 2%,
      rgba(122, 170, 250, 0.34),
      transparent 56%
    ),
    radial-gradient(
      52vw 46vh at 94% 0%,
      rgba(160, 132, 248, 0.3),
      transparent 54%
    ),
    radial-gradient(
      52vw 52vh at 88% 100%,
      rgba(102, 216, 186, 0.28),
      transparent 56%
    ),
    radial-gradient(
      48vw 46vh at 0% 100%,
      rgba(198, 232, 154, 0.28),
      transparent 56%
    ),
    #e9eff7;
}
.wsh-actions {
  position: fixed;
  z-index: 10;
  top: 20px;
  right: 24px;
  display: flex;
  align-items: center;
  gap: 8px;
}
.wsh-guide,
.wsh-logout {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 7px 12px;
  font-size: 13px;
  border-radius: 12px;
  color: #5a6472;
  background: rgba(255, 255, 255, 0.5);
  backdrop-filter: blur(12px);
  border: 1px solid rgba(255, 255, 255, 0.6);
}
.wsh-guide {
  cursor: pointer;
}
.wsh-guide:hover,
.wsh-logout:hover {
  color: #232833;
}
.wsh-guide-wrap {
  position: relative;
}
.wsh-guide-menu {
  position: absolute;
  top: calc(100% + 6px);
  right: 0;
  min-width: 168px;
  display: flex;
  flex-direction: column;
  padding: 6px;
  gap: 2px;
  border-radius: 12px;
  background: rgba(255, 255, 255, 0.72);
  backdrop-filter: blur(16px);
  border: 1px solid rgba(255, 255, 255, 0.7);
  box-shadow: 0 8px 24px rgba(40, 50, 80, 0.14);
}
.wsh-guide-menu a {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 10px;
  font-size: 13px;
  border-radius: 8px;
  color: #4a5462;
  white-space: nowrap;
}
.wsh-guide-menu a:hover {
  color: #232833;
  background: rgba(99, 102, 241, 0.1);
}
.wsh-guide-backdrop {
  position: fixed;
  inset: 0;
  z-index: 9;
}
.wsh-wrap {
  max-width: 1320px;
  margin: 0 auto;
  padding: 14px 64px 12px;
}
.wsh-top {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  margin-bottom: 9px;
}
.wsh-logo {
  height: 34px;
  width: auto;
  margin-bottom: 7px;
  display: block;
}
.wsh-hello {
  font-size: 21px;
  font-weight: 800;
  letter-spacing: -0.5px;
}
.wsh-sub {
  font-size: 14px;
  color: #6b7482;
  font-weight: 600;
  margin-top: 6px;
}
.wsh-date {
  font-size: 13px;
  font-weight: 700;
  color: #232833;
  padding: 10px 16px;
  border-radius: 14px;
  background: rgba(255, 255, 255, 0.5);
  backdrop-filter: blur(14px) saturate(150%);
  border: 1px solid rgba(255, 255, 255, 0.65);
}

.wsh-layout {
  display: grid;
  grid-template-columns: 1fr 320px;
  gap: 11px;
  align-items: start;
}
.wsh-main {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 11px;
  align-items: start;
}
.wsh-col {
  display: flex;
  flex-direction: column;
  gap: 11px;
}
@media (max-width: 1200px) {
  .wsh-main {
    grid-template-columns: repeat(2, 1fr);
  }
}
@media (max-width: 1080px) {
  .wsh-layout {
    grid-template-columns: 1fr;
  }
}
@media (max-width: 767px) {
  .wsh-wrap {
    padding: 12px 16px 12px;
  }
  .wsh-actions {
    top: 12px;
    right: 12px;
    gap: 6px;
  }
  .wsh-guide,
  .wsh-logout {
    padding: 6px 10px;
    font-size: 12px;
  }
  .wsh-top {
    margin-top: 44px;
  }
  .wsh-main {
    grid-template-columns: 1fr;
  }
  .wsh-rail {
    min-width: 0;
  }
  /* 手机端：隐藏桌面 bento，改用紧凑网格（用 .wsh-wrap 提高优先级，压过后面的默认 .wsh-m{display:none}）*/
  .wsh-layout {
    display: none;
  }
  .wsh-wrap .wsh-m {
    display: block;
  }
}

/* ─── 手机端一级界面（默认隐藏，仅 ≤767px 显示）─── */
.wsh-m {
  display: none;
}
.m-section-t {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin: 18px 2px 10px;
  font-size: 13px;
  font-weight: 800;
  color: #4b535f;
}
.m-count {
  font-size: 12px;
  font-weight: 600;
  color: #9aa0ac;
}
.g-violet {
  background: linear-gradient(150deg, #b3a4f5, #8b78ee);
}
.g-lime {
  background: linear-gradient(150deg, #bfe388, #9fd162);
}
.g-teal {
  background: linear-gradient(150deg, #86ddc6, #3ec3a2);
}
.g-sky {
  background: linear-gradient(150deg, #9cc9f8, #5b9bef);
}
.g-blue {
  background: linear-gradient(150deg, #7db8f7, #5691ec);
}
.g-cyan {
  background: linear-gradient(150deg, #4fd1e6, #22b8d4);
}
.g-gray {
  background: linear-gradient(150deg, #c3ccd8, #9aa7b8);
}
/* 方案 D：双主入口 */
.m-duo {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 10px;
  margin-top: 14px;
}
.m-big {
  text-align: left;
  font-family: inherit;
  cursor: pointer;
  color: #fff;
  border-radius: 18px;
  padding: 14px;
  min-height: 120px;
  position: relative;
  overflow: hidden;
  display: flex;
  flex-direction: column;
  border: 1px solid rgba(255, 255, 255, 0.26);
  box-shadow: 0 16px 38px -20px rgba(60, 90, 150, 0.5);
  transition: transform 0.16s ease;
}
.m-big:active {
  transform: scale(0.98);
}
.m-big.locked {
  opacity: 0.55;
  filter: saturate(0.5);
  cursor: not-allowed;
}
.m-big-l {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 15px;
  font-weight: 800;
  position: relative;
  z-index: 2;
}
.m-big-l :deep([class*='i-lucide-']) {
  width: 17px;
  height: 17px;
}
.m-big-n {
  margin-top: auto;
  font-size: 12px;
  color: rgba(255, 255, 255, 0.9);
  position: relative;
  z-index: 2;
}
.m-big-go {
  align-self: flex-start;
  margin-top: 9px;
  display: inline-flex;
  align-items: center;
  gap: 5px;
  font-size: 12.5px;
  font-weight: 800;
  padding: 6px 12px;
  border-radius: 11px;
  background: rgba(255, 255, 255, 0.24);
  position: relative;
  z-index: 2;
}
.m-big-go :deep([class*='i-lucide-']) {
  width: 14px;
  height: 14px;
}
/* 图标快启 */
.m-launch {
  display: flex;
  gap: 6px;
  margin-top: 16px;
  overflow-x: auto;
  padding-bottom: 2px;
}
.m-launch::-webkit-scrollbar {
  display: none;
}
.m-lz {
  flex: 1 0 auto;
  min-width: 60px;
  background: none;
  border: none;
  font-family: inherit;
  cursor: pointer;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 7px;
}
.m-lc {
  width: 50px;
  height: 50px;
  border-radius: 16px;
  display: grid;
  place-items: center;
  color: #fff;
  position: relative;
  box-shadow: 0 10px 20px -12px rgba(60, 90, 150, 0.55);
}
.m-lc :deep([class*='i-lucide-']) {
  width: 22px;
  height: 22px;
}
.m-badge {
  position: absolute;
  top: -5px;
  right: -5px;
  min-width: 18px;
  height: 18px;
  padding: 0 5px;
  border-radius: 9px;
  background: #ff5a7a;
  color: #fff;
  font-size: 10.5px;
  font-weight: 800;
  display: grid;
  place-items: center;
  border: 2px solid #eef2f9;
}
.m-ll {
  font-size: 11px;
  color: #5a6472;
  font-weight: 700;
  white-space: nowrap;
}
/* 数据条 */
.m-drow {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 10px;
}
.m-dcard {
  text-align: left;
  font-family: inherit;
  cursor: pointer;
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 13px 14px;
  border-radius: 16px;
  background: rgba(255, 255, 255, 0.55);
  border: 1px solid rgba(255, 255, 255, 0.6);
  box-shadow: 0 12px 30px -22px rgba(60, 90, 150, 0.36);
  transition: transform 0.16s ease;
}
.m-dcard:active {
  transform: scale(0.98);
}
.m-dc {
  width: 38px;
  height: 38px;
  border-radius: 11px;
  display: grid;
  place-items: center;
  color: #fff;
  flex: none;
}
.m-dc :deep([class*='i-lucide-']) {
  width: 19px;
  height: 19px;
}
.m-dn {
  font-size: 22px;
  font-weight: 800;
  letter-spacing: -0.5px;
  color: #232833;
  line-height: 1.1;
}
.m-du {
  font-size: 11px;
  color: #9aa0ac;
  font-weight: 600;
}
.m-agenda {
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.m-ev {
  display: flex;
  gap: 12px;
  align-items: center;
  text-align: left;
  font-family: inherit;
  cursor: pointer;
  padding: 11px 13px;
  border-radius: 14px;
  background: rgba(255, 255, 255, 0.55);
  backdrop-filter: blur(20px) saturate(150%);
  border: 1px solid rgba(255, 255, 255, 0.6);
}
.m-ev-tm {
  width: 42px;
  flex: none;
  font-size: 12px;
  font-weight: 800;
  color: #4b535f;
}
.m-ev-b {
  flex: 1;
  min-width: 0;
  border-left: 3px solid #5b9bef;
  padding-left: 11px;
}
.m-ev-b b {
  display: block;
  font-size: 13.5px;
  font-weight: 700;
  color: #232833;
}
.m-ev-b small {
  font-size: 11px;
  color: #9aa0ac;
}
.m-ev.teal .m-ev-b {
  border-color: #3ec3a2;
}
.m-ev.violet .m-ev-b {
  border-color: #8b78ee;
}
.m-ev.rose .m-ev-b {
  border-color: #ef7f9c;
}
.m-ev.lime .m-ev-b {
  border-color: #9fd162;
}
.m-ev.sky .m-ev-b {
  border-color: #38bdf8;
}
.m-ev-empty {
  width: 100%;
  font-family: inherit;
  cursor: pointer;
  padding: 18px 0;
  text-align: center;
  font-size: 12.5px;
  color: #9aa0ac;
  background: rgba(255, 255, 255, 0.45);
  border: 1px dashed rgba(150, 160, 175, 0.4);
  border-radius: 14px;
}

.wsh-card {
  width: 100%;
  text-align: left;
  font-family: inherit;
  color: inherit;
  cursor: pointer;
  border-radius: 16px;
  padding: 12px 14px;
  position: relative;
  overflow: hidden;
  display: block;
  transition:
    transform 0.16s ease,
    box-shadow 0.16s ease;
}
.wsh-card:hover {
  transform: translateY(-3px);
}
.wsh-card.locked {
  opacity: 0.55;
  filter: saturate(0.5);
  cursor: not-allowed;
}
.wsh-card.locked:hover {
  transform: none;
}
.wsh-glass {
  background: rgba(255, 255, 255, 0.55);
  backdrop-filter: blur(22px) saturate(155%);
  border: 1px solid rgba(255, 255, 255, 0.6);
  box-shadow:
    0 16px 40px -22px rgba(60, 90, 150, 0.36),
    inset 0 1px 0 rgba(255, 255, 255, 0.7);
}
.wsh-solid {
  color: #fff;
  border: 1px solid rgba(255, 255, 255, 0.26);
  box-shadow: 0 18px 44px -20px rgba(60, 90, 150, 0.5);
}
.c-crm {
  background: linear-gradient(155deg, #7cb6f7, #4f8fea);
}
.c-mes {
  background: linear-gradient(155deg, #b3a4f5, #8b78ee);
}
.c-tik {
  background: linear-gradient(155deg, #4fd1e6, #22b8d4);
}
.blob {
  position: absolute;
  border-radius: 50%;
  filter: blur(30px);
  opacity: 0.5;
  background: rgba(255, 255, 255, 0.6);
  z-index: 1;
}

.lbl {
  font-size: 12.5px;
  font-weight: 800;
  display: flex;
  align-items: center;
  gap: 6px;
  position: relative;
  z-index: 2;
}
.lbl :deep([class*='i-lucide-']),
.lbl .tk {
  width: 15px;
  height: 15px;
}
.a-teal {
  color: #1f9d80;
}
.a-lime {
  color: #6ba01f;
}
.a-violet {
  color: #7a67dc;
}
.a-sky {
  color: #3f7fe0;
}
.tag {
  margin-left: auto;
  font-size: 10.5px;
  font-weight: 700;
  color: #9aa0ac;
  background: rgba(120, 140, 170, 0.12);
  border-radius: 20px;
  padding: 3px 8px;
}
.big {
  font-size: 25px;
  font-weight: 800;
  letter-spacing: -1px;
  line-height: 1.1;
  margin-top: 5px;
  position: relative;
  z-index: 2;
}
.unit {
  font-size: 13px;
  margin-top: 2px;
  position: relative;
  z-index: 2;
  color: rgba(255, 255, 255, 0.85);
}
.unit.gray {
  color: #9aa0ac;
}
.sub2 {
  font-size: 12.5px;
  color: #9aa0ac;
  margin-top: 8px;
}
.statrow {
  display: flex;
  gap: 14px;
  margin-top: 6px;
  position: relative;
  z-index: 2;
}
.statrow b {
  font-size: 19px;
  font-weight: 800;
  display: block;
  letter-spacing: -0.5px;
}
.statrow span {
  font-size: 11.5px;
  color: rgba(255, 255, 255, 0.8);
}
.cta {
  margin-top: 10px;
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 13px;
  font-weight: 800;
  padding: 8px 14px;
  border-radius: 12px;
  background: rgba(255, 255, 255, 0.22);
  position: relative;
  z-index: 2;
}
.cta :deep([class*='i-lucide-']) {
  width: 15px;
  height: 15px;
}
.cta2 {
  margin-top: auto;
  padding-top: 14px;
  display: inline-flex;
  align-items: center;
  gap: 5px;
  font-size: 12.5px;
  font-weight: 700;
  color: #6b7180;
}
.cta2.muted {
  color: #9aa0ac;
}
.cta2 :deep([class*='i-lucide-']) {
  width: 14px;
  height: 14px;
}

.chart {
  width: 100%;
  height: 58px;
  margin-top: 10px;
}
.chips {
  display: flex;
  gap: 8px;
  margin-top: 14px;
}
.chips span {
  font-size: 12px;
  font-weight: 700;
  color: #5f6570;
  background: rgba(120, 140, 170, 0.1);
  border-radius: 9px;
  padding: 5px 11px;
}

.week {
  display: flex;
  justify-content: space-between;
  margin-top: 10px;
}
.wd {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
}
.wd span {
  font-size: 11px;
  color: #9aa0ac;
  font-weight: 600;
}
.wd .o {
  width: 26px;
  height: 26px;
  border-radius: 50%;
  display: grid;
  place-items: center;
}
.wd .on {
  background: linear-gradient(150deg, #9cc9f8, #5b9bef);
  color: #fff;
}
.wd .off {
  background: #eef2f7;
  color: #c2cad4;
}
.wd .o :deep([class*='i-lucide-']) {
  width: 14px;
  height: 14px;
}

.wsh-ring {
  display: flex;
  align-items: center;
  gap: 14px;
  margin-top: 9px;
  position: relative;
  z-index: 2;
}
.wsh-ring .pct {
  font-size: 15px;
  font-weight: 800;
  fill: #fff;
}
.wsh-ring-t {
  font-size: 20px;
  font-weight: 800;
  letter-spacing: -0.5px;
}
.checks {
  margin-top: 10px;
  display: flex;
  flex-direction: column;
  gap: 6px;
  position: relative;
  z-index: 2;
}
.ck {
  display: flex;
  align-items: center;
  gap: 9px;
  font-size: 13px;
}
.ck .ci {
  width: 18px;
  height: 18px;
  border-radius: 50%;
  display: grid;
  place-items: center;
}
.ck .ci :deep([class*='i-lucide-']) {
  width: 12px;
  height: 12px;
}
.ck.done .ci {
  background: rgba(255, 255, 255, 0.9);
  color: #8b78ee;
}
.ck.wait {
  color: rgba(255, 255, 255, 0.75);
}
.ck.wait .ci {
  background: rgba(255, 255, 255, 0.25);
  color: rgba(255, 255, 255, 0.7);
}

.olist {
  margin-top: 12px;
  display: flex;
  flex-direction: column;
}
.oi {
  display: flex;
  align-items: center;
  gap: 11px;
  padding: 9px 0;
  border-top: 1px solid #eef0f3;
}
.oi:first-child {
  border-top: 0;
}
.oic {
  width: 30px;
  height: 30px;
  border-radius: 9px;
  display: grid;
  place-items: center;
  color: #fff;
  flex: none;
}
.oic :deep([class*='i-lucide-']) {
  width: 15px;
  height: 15px;
}
.bg-lime {
  background: linear-gradient(150deg, #bfe388, #9fd162);
}
.bg-teal {
  background: linear-gradient(150deg, #86ddc6, #3ec3a2);
}
.bg-sky {
  background: linear-gradient(150deg, #9cc9f8, #5b9bef);
}
.bg-violet {
  background: linear-gradient(150deg, #b3a4f5, #8b78ee);
}
.ot {
  font-size: 13px;
  font-weight: 700;
  flex: 1;
  min-width: 0;
}
.ot small {
  display: block;
  font-size: 10.5px;
  color: #9aa0ac;
  font-weight: 500;
  margin-top: 1px;
}
.ost {
  font-size: 11px;
  font-weight: 700;
  color: #6f8a1a;
  background: #eef6d5;
  border-radius: 7px;
  padding: 3px 8px;
}

.avs {
  display: flex;
  margin-top: 16px;
}
.avs .av {
  width: 34px;
  height: 34px;
  border-radius: 50%;
  border: 2px solid #fff;
  margin-left: -9px;
}
.avs .av:first-child {
  margin-left: 0;
}
.av.a1 {
  background: linear-gradient(150deg, #9cc9f8, #5b9bef);
}
.av.a2 {
  background: linear-gradient(150deg, #b3a4f5, #8b78ee);
}
.av.a3 {
  background: linear-gradient(150deg, #86ddc6, #3ec3a2);
}
.av.a4 {
  background: linear-gradient(150deg, #f7b0c0, #f088a0);
}
.avs .more {
  width: 34px;
  height: 34px;
  border-radius: 50%;
  border: 2px solid #fff;
  margin-left: -9px;
  background: #e7effe;
  color: #3f7fe0;
  font-size: 11.5px;
  font-weight: 800;
  display: grid;
  place-items: center;
}
.msg {
  margin-top: 14px;
  background: rgba(255, 255, 255, 0.6);
  border: 1px solid #eef0f3;
  border-radius: 12px;
  padding: 11px 13px;
  font-size: 12.5px;
  color: #9aa0ac;
}
.msg b {
  font-weight: 800;
  color: #232833;
}

/* 日程主栏 */
.wsh-rail {
  border-radius: 16px;
  padding: 12px 14px;
  position: relative;
  overflow: hidden;
  min-height: 0;
  background: rgba(255, 255, 255, 0.58);
  backdrop-filter: blur(24px) saturate(160%);
  border: 1px solid rgba(255, 255, 255, 0.65);
  box-shadow:
    0 20px 50px -22px rgba(60, 90, 150, 0.42),
    inset 0 1px 0 rgba(255, 255, 255, 0.75);
  cursor: pointer;
  transition:
    transform 0.16s ease,
    box-shadow 0.16s ease;
}
.wsh-rail:hover {
  transform: translateY(-2px);
  box-shadow:
    0 26px 56px -20px rgba(60, 90, 150, 0.5),
    inset 0 1px 0 rgba(255, 255, 255, 0.75);
}
.wsh-rail:focus-visible {
  outline: 2px solid #5691ec;
  outline-offset: 2px;
}
.r-aura {
  position: absolute;
  width: 260px;
  height: 200px;
  right: -60px;
  top: -70px;
  border-radius: 50%;
  filter: blur(46px);
  background: radial-gradient(
    circle,
    rgba(122, 170, 250, 0.5),
    transparent 68%
  );
  z-index: 1;
}
.rhead {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  position: relative;
  z-index: 2;
}
.rl {
  font-size: 12.5px;
  font-weight: 800;
  color: #3f7fe0;
  display: flex;
  align-items: center;
  gap: 6px;
}
.rl :deep([class*='i-lucide-']) {
  width: 15px;
  height: 15px;
}
.rhead h2 {
  font-size: 18px;
  font-weight: 800;
  letter-spacing: -0.4px;
  margin-top: 4px;
}
.today {
  text-align: center;
  background: linear-gradient(150deg, #7db8f7, #5691ec);
  color: #fff;
  border-radius: 12px;
  padding: 5px 11px;
  box-shadow: 0 10px 20px -8px rgba(86, 145, 236, 0.6);
}
.today b {
  font-size: 24px;
  font-weight: 800;
  display: block;
  line-height: 1;
}
.today span {
  font-size: 10.5px;
  opacity: 0.9;
}
.cal {
  margin-top: 8px;
  position: relative;
  z-index: 2;
}
.cal .hd {
  display: grid;
  grid-template-columns: repeat(7, 1fr);
  margin-bottom: 8px;
}
.cal .hd span {
  font-size: 11px;
  color: #9aa0ac;
  text-align: center;
  font-weight: 700;
}
.cal .bd {
  display: grid;
  grid-template-columns: repeat(7, 1fr);
  gap: 5px 0;
}
.cal .bd span {
  position: relative;
  font-size: 12px;
  text-align: center;
  padding: 4px 0;
  font-weight: 600;
  color: #404855;
  border-radius: 8px;
}
.cal .bd .mut {
  color: #cbd1da;
}
.cal .bd .now {
  background: linear-gradient(150deg, #7db8f7, #5691ec);
  color: #fff;
  font-weight: 800;
  box-shadow: 0 8px 16px -6px rgba(86, 145, 236, 0.55);
}
.cal .bd .has::after {
  content: '';
  position: absolute;
  left: 50%;
  bottom: 3px;
  transform: translateX(-50%);
  width: 4px;
  height: 4px;
  border-radius: 50%;
  background: #8b78ee;
}
.cal .bd .now.has::after {
  background: #fff;
}
.agenda {
  margin-top: 9px;
  position: relative;
  z-index: 2;
}
.ahd {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
.ahd b {
  font-size: 14px;
  font-weight: 800;
}
.ahd span {
  font-size: 12px;
  color: #9aa0ac;
  font-weight: 600;
}
.ev {
  display: flex;
  gap: 12px;
  margin-top: 7px;
}
.ev .tm {
  width: 44px;
  flex: none;
  font-size: 12px;
  font-weight: 800;
  color: #4b535f;
  padding-top: 2px;
}
.ev .eb {
  flex: 1;
  border-left: 3px solid;
  padding: 2px 0 2px 12px;
}
.ev .eb b {
  font-size: 13.5px;
  font-weight: 700;
  display: block;
}
.ev .eb small {
  font-size: 11.5px;
  color: #9aa0ac;
}
.ev.blue .eb {
  border-color: #5b9bef;
}
.ev.teal .eb {
  border-color: #3ec3a2;
}
.ev.violet .eb {
  border-color: #8b78ee;
}
.ev.rose .eb {
  border-color: #ef7f9c;
}
.ev.lime .eb {
  border-color: #9fd162;
}
.ev.sky .eb {
  border-color: #38bdf8;
}
.ev-empty {
  margin-top: 14px;
  padding: 18px 0;
  text-align: center;
  font-size: 12.5px;
  color: #9aa0ac;
}
.newbtn {
  margin-top: 14px;
  width: 100%;
  font-family: inherit;
  font-size: 13px;
  font-weight: 800;
  color: #fff;
  background: linear-gradient(135deg, #6aa8f2, #4f8fea);
  border: none;
  border-radius: 12px;
  padding: 10px 0;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 7px;
  box-shadow: 0 12px 24px -10px rgba(79, 143, 234, 0.6);
  position: relative;
  z-index: 2;
}
.newbtn :deep([class*='i-lucide-']) {
  width: 16px;
  height: 16px;
}

.wsh-foot {
  text-align: center;
  color: #aeb6c1;
  font-size: 12px;
  margin-top: 12px;
  font-weight: 600;
}
.wsh-beian {
  display: block;
  margin-top: 4px;
  color: #b9c0ca;
  font-size: 11px;
  font-weight: 500;
  letter-spacing: 0.2px;
}
</style>
