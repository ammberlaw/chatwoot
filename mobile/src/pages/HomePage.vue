<script setup>
import { ref, computed, onMounted, onActivated } from 'vue';
import { useRouter } from 'vue-router';
import IosRow from '@/components/IosRow.vue';
import LargeTitleBar from '@/components/LargeTitleBar.vue';
import DataState from '@/components/DataState.vue';
import { useAuthStore } from '@/stores/auth';
import {
  fetchHomeStats,
  fetchStats,
  fetchScheduleEvents,
  fetchApprovalCounts,
} from '@/api/crm';
import { money, num, wallTime } from '@/utils/format';
import { ALL_MODULES, HOME_SHORTCUTS, SUBSYSTEMS } from '@/constants/modules';

defineOptions({ name: 'HomePage' });

const router = useRouter();
const auth = useAuthStore();

// 大标题收起用：把滚动容器交给 LargeTitleBar 自己监听
const scroller = ref(null);
const barTitle = '工作台';

const home = ref({});
const stats = ref({});
const events = ref([]);
const approvalCounts = ref({});
const loading = ref(true);
const failed = ref(false);
const staleAt = ref(null);

const greeting = computed(() => {
  const h = new Date().getHours();
  if (h < 6) return '夜深了';
  if (h < 12) return '早上好';
  if (h < 18) return '下午好';
  return '晚上好';
});

const todayLabel = computed(() => {
  const d = new Date();
  return `今天 · ${d.getMonth() + 1}月${d.getDate()}日 周${'日一二三四五六'[d.getDay()]}`;
});

// 顶部状态 chips：参考图里搜索条下面那排胶囊。这里不是筛选器，
// 是三个待办数字，所以用淡彩底 + 数字加粗，不做选中态。
const quickStats = computed(() => [
  { v: num(home.value.crm?.follow_up_due), l: '待跟进', to: { name: 'customers' } },
  // 逾期是唯一一个「颜色有理由」的：它是警示，不是分类
  { v: num(home.value.crm?.overdue), l: '已逾期', alert: true, to: { name: 'customers' } },
  { v: num(approvalCounts.value.todo), l: '待审批', to: { name: 'approvals' } },
]);

const yearly = computed(() => stats.value.period_stats?.yearly || {});
// 2×2 指标卡：标签小灰在上、数字大黑在下
const metrics = computed(() => [
  { l: '成交订单', v: String(yearly.value.order_count ?? 0) },
  { l: '成交客户', v: String(yearly.value.deal_customers ?? 0) },
  { l: '新客户', v: String(yearly.value.new_customers ?? 0) },
]);

const target = computed(() => {
  const t = stats.value.target;
  if (!num(t?.amount_micros)) return null;
  const done = num(t.month_amount_micros);
  const total = num(t.amount_micros);
  return { done, total, percent: Math.min(100, Math.round((done / total) * 100)) };
});

const allModules = ALL_MODULES;

// 两个子系统入口，只列路由里真实存在的
const subsystems = computed(() => SUBSYSTEMS.filter(m => router.hasRoute(m.name)));

// 进度环周长：r=27 → 2πr
const RING = 2 * Math.PI * 27;
// 快捷入口的待办角标。有确切条数就显数字——「有 3 条」和「有」是两回事；
// 只有状态没条数的才退回一个点。用淡黄底整格表示待办会被读成「选中」，不用那种。
const BADGES = computed(() => ({
  approvals: num(approvalCounts.value.todo),
}));

const shortcuts = computed(() =>
  [
    ...HOME_SHORTCUTS.map(n => allModules.find(m => m.name === n))
      .filter(m => m && router.hasRoute(m.name))
      .slice(0, 7),
    { name: 'more', label: '全部', icon: 'i-ri-apps-2-fill' },
  ].map(m => ({ ...m, badge: BADGES.value[m.name] || 0 }))
);

const load = async () => {
  loading.value = true;
  failed.value = false;
  const today = new Date().toISOString().slice(0, 10);
  const [h, s, e, ac] = await Promise.allSettled([
    fetchHomeStats(),
    fetchStats({ scope: 'mine' }),
    fetchScheduleEvents({ from: today, to: today }),
    fetchApprovalCounts(),
  ]);
  if (h.status === 'fulfilled') {
    home.value = h.value.data || {};
    staleAt.value = h.value.fromCache ? h.value.at : null;
  }
  if (s.status === 'fulfilled') stats.value = s.value.data || {};
  if (e.status === 'fulfilled') events.value = e.value.data?.payload || [];
  if (ac.status === 'fulfilled') approvalCounts.value = ac.value.data || {};
  failed.value = [h, s, e, ac].every(r => r.status === 'rejected');
  loading.value = false;
};

onMounted(load);
onActivated(() => {
  if (!loading.value) load();
});
</script>

<template>
  <div class="relative flex flex-col h-full">
    <LargeTitleBar :title="barTitle" :scroller="scroller" :range="64" />

    <div ref="scroller" class="flex-1 min-h-0 px-4 overflow-y-auto pt-safeTop">
      <!-- 小号大写的引题在上、粗标题在下（参考图的层级语言）-->
      <header class="flex items-start gap-3 pt-4 pb-4">
        <div class="flex-1 min-w-0">
          <h1 class="text-[25px] font-bold leading-[30px] tracking-[-0.5px] text-[color:var(--pb-ink)]">
            {{ greeting }}，{{ auth.user?.name || auth.user?.email || '' }}
          </h1>
          <p class="mt-1 text-[14px] leading-[19px] text-[color:var(--pb-ink-2)]">
            {{ todayLabel }}
          </p>
        </div>
        <button
          type="button"
          aria-label="账号与设置"
          class="grid flex-none mt-0.5 rounded-full size-9 place-items-center text-[color:var(--pb-ink)] transition-opacity active:opacity-50"
          @click="router.push({ name: 'more' })"
        >
          <!-- 参考图右上角是一枚细线字形，不是白色实心圆钮 -->
          <span class="size-[22px] i-ri-more-fill" />
        </button>
      </header>

      <DataState :loading="loading" :failed="failed" :stale-at="staleAt" @retry="load">
        <!-- 一张卡三栏，中间是 0.5px 细分隔线——iOS 统计条的标准形 -->
        <div class="flex mt-1 pb-well">
          <button
            v-for="(s, i) in quickStats"
            :key="s.l"
            type="button"
            class="relative flex-1 py-[18px] transition-opacity active:opacity-60"
            @click="router.push(s.to)"
          >
            <!-- 分隔线不通高：上下各内缩，只在文字那一段出现（参考图就是这样） -->
            <span
              v-if="i"
              class="absolute left-0 top-[22%] h-[56%] w-px bg-[color:var(--pb-sep)]"
            />
            <div
              class="text-[22px] font-bold leading-7 tracking-[-0.3px] text-[color:var(--pb-ink)]"
            >
              {{ s.v }}
            </div>
            <div
              class="mt-1 flex items-center justify-center gap-1 text-[13px] leading-[18px] text-[color:var(--pb-ink-2)]"
            >
              <!-- 有逾期才亮的小黄点。整块涂黄会糊成一片荧光笔痕，点就够了 -->
              <span
                v-if="s.alert && s.v"
                class="flex-none rounded-full size-[6px] brand-fill"
              />
              {{ s.l }}
            </div>
          </button>
        </div>

        <!-- 主角卡：整屏唯一的重色块。黑底 + 品牌黄。
             右边那圈原来是纯装饰（在黑底上糊成一团褐色），换成本月目标的进度环——
             同样的位置、同样的形，但它现在是信息不是花纹。 -->
        <div class="relative mt-4">
          <!-- 垫在玻璃后面的色块：黄在右上（对应黄数字和黄进度环）、靛在左下 -->
          <div class="absolute inset-0 pb-hero-back" />
          <div class="relative px-5 py-4 pb-hero">
            <div class="flex items-center gap-4">
              <div class="flex-1 min-w-0">
                <p class="text-[13px] leading-[18px] text-[color:var(--pb-hero-ink-2)]">
                  本年成交额
                </p>
                <div
                  class="mt-0.5 text-[30px] font-bold leading-9 tracking-[-0.6px] text-[color:var(--pb-brand)]"
                >
                  {{ money(yearly.amount_micros) }}
                </div>
              </div>

              <!-- 进度环收小，百分比和标题都压进环里，不再单独占一行 -->
              <div v-if="target" class="flex-none text-center">
                <div class="relative size-[64px]">
                  <svg viewBox="0 0 64 64" class="size-full -rotate-90">
                    <circle cx="32" cy="32" r="27" fill="none" stroke="rgb(255 255 255 / 0.14)" stroke-width="5" />
                    <circle
                      cx="32"
                      cy="32"
                      r="27"
                      fill="none"
                      stroke="var(--pb-brand)"
                      stroke-width="5"
                      stroke-linecap="round"
                      :stroke-dasharray="RING"
                      :stroke-dashoffset="RING * (1 - target.percent / 100)"
                    />
                  </svg>
                  <div class="absolute inset-0 grid place-items-center">
                    <span class="text-[16px] font-bold leading-none text-white">
                      {{ target.percent }}%
                    </span>
                  </div>
                </div>
                <!-- 标题放环外：塞进环里只能用 9px，小到读不出来 -->
                <p class="mt-1 text-[11px] leading-4 text-[color:var(--pb-hero-ink-2)]">本月目标</p>
              </div>
            </div>

            <div class="flex pt-3 mt-3 border-t border-[color:var(--pb-hero-line)]">
              <div v-for="(m, i) in metrics" :key="m.l" class="flex-1" :class="i ? 'pl-3' : ''">
                <div
                  class="text-[17px] font-semibold leading-[22px] tracking-[-0.43px] text-[color:var(--pb-hero-ink)]"
                >
                  {{ m.v }}
                </div>
                <div class="mt-0.5 text-[12px] leading-4 text-[color:var(--pb-hero-ink-2)]">
                  {{ m.l }}
                </div>
              </div>
            </div>
          </div>
        </div>

        <!-- MES / ERP：和 CRM 同级的两个子系统，给一对大卡，不混进下面的快捷入口 -->
        <div v-if="subsystems.length" class="grid grid-cols-2 gap-3 mt-4">
          <button
            v-for="m in subsystems"
            :key="m.name"
            type="button"
            class="p-4 text-left wt-card wt-press"
            @click="router.push({ name: m.name })"
          >
            <div class="flex items-start gap-2">
              <span class="flex-none block size-7 text-[color:var(--pb-ink)]" :class="m.icon" />
              <span class="flex-1" />
              <span class="flex-none mt-1 size-4 text-[color:var(--pb-ink-3)] i-lucide-chevron-right" />
            </div>
            <span
              class="block mt-3 text-[17px] font-semibold leading-[22px] tracking-[-0.43px] text-[color:var(--pb-ink)]"
            >
              {{ m.label }}
            </span>
            <span class="block mt-0.5 text-[13px] leading-[18px] text-[color:var(--pb-ink-3)]">
              {{ m.desc }}
            </span>
          </button>
        </div>

        <!-- 常用：紧凑图标格。大卡一屏只放得下 3.5 个，太占竖向空间；
             收成 64px 的格子一屏能露 5 个，扫一眼就看完 -->
        <div class="flex items-center justify-between pt-6 pb-2">
          <h2 class="text-[13px] font-medium leading-[18px] text-[color:var(--pb-ink-3)]">常用功能</h2>
          <button type="button" class="flex items-center gap-0.5 wt-link" @click="router.push({ name: 'more' })">
            <span class="text-[13px] leading-[18px] text-[color:var(--pb-ink-3)]">全部</span>
            <span class="size-4 text-[color:var(--pb-ink-3)] i-lucide-chevron-right" />
          </button>
        </div>
        <!-- overflow-x-auto 会连纵向一起裁：角标顶出按钮边界就被切掉。
             上下各留 8px 内边距给它，再用负外边距把视觉位置抵回来。 -->
        <div
          class="flex gap-3 px-4 py-2 -mx-4 -my-2 overflow-x-auto [&::-webkit-scrollbar]:hidden"
        >
          <button
            v-for="m in shortcuts"
            :key="m.name"
            type="button"
            class="flex flex-col items-center flex-none gap-1.5 w-[64px] wt-press"
            @click="router.push({ name: m.name })"
          >
            <span class="relative">
              <span
                class="grid rounded-[14px] size-[52px] place-items-center bg-[color:var(--pb-card)] shadow-[0_6px_18px_-14px_rgb(24_24_40/0.4)]"
              >
                <span class="size-6 text-[color:var(--pb-ink)]" :class="m.icon" />
              </span>
              <!-- 角标：黄底黑字。黑字打在黄上对比度 11:1，没有「黄不写字」的问题 -->
              <span
                v-if="m.badge"
                class="absolute -right-1.5 -top-1.5 min-w-[18px] px-1 rounded-full brand-fill text-[11px] font-bold leading-[18px] text-center text-black"
              >
                {{ m.badge > 99 ? '99+' : m.badge }}
              </span>
            </span>
            <span class="w-full text-[11px] leading-4 text-center truncate text-[color:var(--pb-ink-2)]">
              {{ m.label }}
            </span>
          </button>
        </div>

        <h2 class="sec-title">今日日程</h2>
        <div v-if="events.length" class="overflow-hidden ios-group wt-glass">
          <IosRow v-for="(ev, i) in events" :key="`${ev.id}-${i}`">
            <div
              class="truncate text-[15px] leading-5"
              :class="ev.done ? 'line-through text-[color:var(--pb-ink-3)]' : 'text-[color:var(--pb-ink)]'"
            >
              {{ ev.title }}
            </div>
            <div class="mt-0.5 truncate text-[13px] leading-[18px] text-[color:var(--pb-ink-3)]">
              {{
                [ev.all_day ? '全天' : wallTime(ev.starts_at), ev.customer_name, ev.location]
                  .filter(Boolean)
                  .join(' · ')
              }}
            </div>
          </IosRow>
        </div>
        <p v-else class="px-1 text-[15px] leading-5 text-[color:var(--pb-ink-3)]">今天没有安排</p>

        <div class="h-36" />
      </DataState>
    </div>
  </div>
</template>
