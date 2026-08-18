<script setup>
/* global axios */
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAlert } from 'dashboard/composables';
import Auth from 'dashboard/api/auth';
import RequestsAPI from 'dashboard/api/oa/approvalRequests';
import ChatAPI from 'dashboard/api/chat/conversations';
import ScheduleAPI from 'dashboard/api/crm/scheduleEvents';

import Icon from 'dashboard/components-next/icon/Icon.vue';
import wintouchLockup from 'dashboard/assets/images/wintouch/lockup.png';

const router = useRouter();
const { accountScopedRoute, accountId } = useAccount();
const currentUser = useMapGetter('getCurrentUser');

const stats = ref({ todo: 0, mine: 0, approverView: true, unread: 0 });

// 首页卡片真实数据（当前用户视角）。
const homeStats = ref(null);
const crmStats = computed(() => homeStats.value?.crm || {});
const hrDays = computed(() => homeStats.value?.hr?.days || []);
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
// TikTok：管理层/财务/TK 部门成员可见（后端派生 can_access_tiktok）。
const canAccessTiktok = computed(
  () => currentUser.value?.can_access_tiktok === true
);

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
const WEEK = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
const monthLabel = `${now.getFullYear()} 年 ${now.getMonth() + 1} 月`;
const todayNum = now.getDate();
const todayWeek = WEEK[now.getDay()];

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

// 当月日历（周一起），今日高亮，有安排的日子打点。
const calCells = computed(() => {
  const y = now.getFullYear();
  const m = now.getMonth();
  const startDow = (new Date(y, m, 1).getDay() + 6) % 7; // 周一=0
  const daysInMonth = new Date(y, m + 1, 0).getDate();
  const prevDays = new Date(y, m, 0).getDate();
  const cells = [];
  for (let i = 0; i < startDow; i += 1)
    cells.push({ n: prevDays - startDow + 1 + i, mut: true });
  for (let d = 1; d <= daysInMonth; d += 1) {
    const key = `${y}-${pad(m + 1)}-${pad(d)}`;
    cells.push({ n: d, mut: false, now: d === todayNum, has: !!eventsByDate.value[key] });
  }
  let next = 1;
  while (cells.length % 7 !== 0) cells.push({ n: next++, mut: true });
  return cells;
});

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
    const lastDay = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
    const last = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(lastDay)}`;
    const { data } = await ScheduleAPI.get(accountId.value, { from: first, to: last });
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
});
</script>

<template>
  <Teleport to="body">
    <div class="wsh-root">
      <!-- 退出登录 -->
      <button type="button" class="wsh-logout" @click="Auth.logout">
        <Icon icon="i-lucide-power" class="size-4" />
        退出登录
      </button>

      <div class="wsh-wrap">
        <div class="wsh-top">
          <div>
            <img :src="wintouchLockup" alt="Wintouch" class="wsh-logo" />
            <h1 class="wsh-hello">
              {{ greeting }}<template v-if="userName">，{{ userName }}</template>
            </h1>
            <div class="wsh-sub">选择一个系统开始工作</div>
          </div>
        </div>

        <div class="wsh-layout">
          <!-- 左侧三列 bento -->
          <div class="wsh-main">
            <!-- 列1 -->
            <div class="wsh-col">
              <!-- CRM 旗舰 -->
              <button
                type="button"
                class="wsh-card wsh-solid c-crm"
                :class="{ locked: !canAccessCrm }"
                :disabled="!canAccessCrm"
                @click="go('crm_dashboard_index')"
              >
                <span class="blob" style="width:150px;height:150px;right:-30px;top:-40px" />
                <div class="lbl"><Icon icon="i-lucide-users" /> CRM 客户管理</div>
                <div class="big">{{ crmStats.follow_up_due ?? 0 }}</div>
                <div class="unit">位客户 · 今日待跟进</div>
                <div class="statrow">
                  <div><b>{{ crmStats.new_today ?? 0 }}</b><span>今日新增</span></div>
                  <div><b>{{ crmStats.revisit_week ?? 0 }}</b><span>本周回访</span></div>
                  <div><b>{{ crmStats.overdue ?? 0 }}</b><span>待处理</span></div>
                </div>
                <div v-if="canAccessCrm" class="cta">
                  进入工作区 <Icon icon="i-lucide-arrow-right" />
                </div>
                <div v-else class="cta">
                  <Icon icon="i-lucide-lock" /> 未开通 · 联系管理员
                </div>
              </button>

              <!-- ERP（即将上线） -->
              <button type="button" class="wsh-card wsh-glass" @click="soon('ERP 进销存')">
                <div class="lbl a-teal">
                  <Icon icon="i-lucide-package" /> ERP 进销存·财务
                  <span class="tag">即将上线</span>
                </div>
                <div class="sub2">采购 · 库存 · 凭证一体化</div>
                <div class="chips"><span>采购</span><span>库存</span><span>凭证</span><span>报表</span></div>
                <div class="cta2 muted">敬请期待</div>
              </button>

              <!-- HR -->
              <button type="button" class="wsh-card wsh-glass" @click="go('crm_org_structure_index')">
                <div class="lbl a-sky"><Icon icon="i-lucide-network" /> HR 组织人事</div>
                <div class="sub2">组织架构 · 我的考勤</div>
                <div class="big" style="font-size:30px">{{ hrLabel }}</div>
                <div class="unit gray">本周出勤</div>
                <div class="week">
                  <div
                    v-for="(label, i) in ['一', '二', '三', '四', '五', '六', '日']"
                    :key="label"
                    class="wd"
                  >
                    <span>{{ label }}</span>
                    <div class="o" :class="hrDays[i] && hrDays[i].present ? 'on' : 'off'">
                      <Icon
                        :icon="hrDays[i] && hrDays[i].present ? 'i-lucide-check' : 'i-lucide-minus'"
                      />
                    </div>
                  </div>
                </div>
              </button>
            </div>

            <!-- 列2 -->
            <div class="wsh-col">
              <!-- MES 生产制造 -->
              <button type="button" class="wsh-card wsh-solid c-mes" @click="go('mes_dashboard_index')">
                <span class="blob" style="width:140px;height:140px;right:-40px;bottom:-50px" />
                <div class="lbl">
                  <Icon icon="i-lucide-factory" /> MES 生产制造
                </div>
                <div class="big" style="font-size:24px;margin-top:16px">智能生产制造</div>
                <div class="unit">工单 · 排产 · 质检 · 入库</div>
                <div class="cta">
                  进入 MES 生产制造 <Icon icon="i-lucide-arrow-right" />
                </div>
              </button>

              <!-- OA（真实待办数） -->
              <button type="button" class="wsh-card wsh-glass" @click="go('crm_approvals_index')">
                <div class="lbl a-lime"><Icon icon="i-lucide-clipboard-check" /> OA 审批 · 我的待办</div>
                <div class="big" style="font-size:34px">{{ oaMetric }}</div>
                <div class="unit gray">
                  {{ stats.approverView ? '条待我审批' : '条我的申请' }}
                </div>
                <div class="cta2">进入 OA 审批 <Icon icon="i-lucide-arrow-right" /></div>
              </button>
            </div>

            <!-- 列3 -->
            <div class="wsh-col">
              <!-- 团队协同（真实未读） -->
              <button type="button" class="wsh-card wsh-glass" @click="go('crm_team_chat_index')">
                <div class="lbl a-teal"><Icon icon="i-lucide-messages-square" /> 团队协同</div>
                <div class="big" style="font-size:32px">{{ stats.unread }}</div>
                <div class="unit gray">条未读消息</div>
                <div class="cta2">进入团队协同 <Icon icon="i-lucide-arrow-right" /></div>
              </button>

              <!-- TikTok（权限门） -->
              <button
                type="button"
                class="wsh-card wsh-solid c-tik"
                :class="{ locked: !canAccessTiktok }"
                :disabled="!canAccessTiktok"
                @click="go('tiktok_dashboard_index')"
              >
                <span class="blob" style="width:150px;height:150px;right:-40px;top:-50px" />
                <div class="lbl">
                  <svg viewBox="0 0 24 24" fill="currentColor" class="tk"><path d="M12.53.02C13.84 0 15.14.01 16.44 0c.08 1.53.63 3.09 1.75 4.17 1.12 1.11 2.7 1.62 4.24 1.79v4.03c-1.44-.05-2.89-.35-4.2-.97-.57-.26-1.1-.59-1.62-.93-.01 2.92.01 5.84-.02 8.75-.08 1.4-.54 2.79-1.35 3.94-1.31 1.92-3.58 3.17-5.91 3.21-1.43.08-2.86-.31-4.08-1.03-2.02-1.19-3.44-3.37-3.65-5.71-.02-.5-.03-1-.01-1.49.18-1.9 1.12-3.72 2.58-4.96 1.66-1.44 3.98-2.13 6.15-1.72.02 1.48-.04 2.96-.04 4.44-.99-.32-2.15-.23-3.02.37-.63.41-1.11 1.04-1.36 1.75-.21.51-.15 1.07-.14 1.61.24 1.64 1.82 3.02 3.5 2.87 1.12-.01 2.19-.66 2.77-1.61.19-.33.4-.67.41-1.06.1-1.79.06-3.57.07-5.36.01-4.03-.01-8.05.02-12.07z" /></svg>
                  TikTok 经营
                </div>
                <div class="big" style="font-size:24px;margin-top:14px">跨境店铺经营</div>
                <div class="unit">店铺 · 订单 · 数据看板</div>
                <div v-if="!canAccessTiktok" class="cta"><Icon icon="i-lucide-lock" /> 暂无权限</div>
              </button>

              <!-- 文档中心 -->
              <button type="button" class="wsh-card wsh-glass" @click="go('crm_doc_center_index')">
                <div class="lbl a-violet"><Icon icon="i-lucide-book-open" /> 文档中心</div>
                <div class="sub2">制度 · 流程 · 培训 · 知识</div>
                <div class="chips"><span>制度</span><span>流程</span><span>培训</span><span>知识</span></div>
                <div class="cta2">进入文档中心 <Icon icon="i-lucide-arrow-right" /></div>
              </button>
            </div>
          </div>

          <!-- 右侧日程主栏：整块可点进日程 -->
          <div
            class="wsh-rail"
            role="button"
            tabindex="0"
            @click="go('crm_schedule_index')"
            @keydown.enter="go('crm_schedule_index')"
          >
            <span class="r-aura" />
            <div class="rhead">
              <div>
                <div class="rl"><Icon icon="i-lucide-calendar-days" /> 日程 Schedule</div>
                <h2>{{ monthLabel }}</h2>
              </div>
              <div class="today"><b>{{ todayNum }}</b><span>{{ todayWeek }}</span></div>
            </div>

            <div class="cal">
              <div class="hd"><span v-for="d in ['一','二','三','四','五','六','日']" :key="d">{{ d }}</span></div>
              <div class="bd">
                <span v-for="(c, i) in calCells" :key="i" :class="{ mut: c.mut, now: c.now, has: c.has }">{{ c.n }}</span>
              </div>
            </div>

            <div class="agenda">
              <div class="ahd"><b>今日安排</b><span>{{ todayEvents.length }} 项</span></div>
              <template v-if="todayEvents.length">
                <div
                  v-for="e in todayEvents"
                  :key="e.id + e.starts_at"
                  class="ev"
                  :class="e.color"
                >
                  <div class="tm">{{ e.all_day ? '全天' : hhmm(e.starts_at) }}</div>
                  <div class="eb">
                    <b>{{ e.title }}</b>
                    <small>
                      {{ e.owner_name
                      }}<template v-if="e.participant_names && e.participant_names.length"
                        >、{{ e.participant_names.join('、') }}</template
                      >
                    </small>
                  </div>
                </div>
              </template>
              <div v-else class="ev-empty">今天暂无安排</div>
            </div>

            <button type="button" class="newbtn" @click.stop="go('crm_schedule_index')">
              <Icon icon="i-lucide-plus" /> 新建日程
            </button>
          </div>
        </div>

        <div class="wsh-foot">WintouchSpace · Designed &amp; Developed by Amber Law</div>
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
  background:
    radial-gradient(58vw 52vh at 8% 2%, rgba(122, 170, 250, 0.34), transparent 56%),
    radial-gradient(52vw 46vh at 94% 0%, rgba(160, 132, 248, 0.3), transparent 54%),
    radial-gradient(52vw 52vh at 88% 100%, rgba(102, 216, 186, 0.28), transparent 56%),
    radial-gradient(48vw 46vh at 0% 100%, rgba(198, 232, 154, 0.28), transparent 56%),
    #e9eff7;
}
.wsh-logout {
  position: fixed;
  z-index: 10;
  top: 20px;
  right: 24px;
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
.wsh-logout:hover { color: #232833; }
.wsh-wrap { max-width: 1320px; margin: 0 auto; padding: 14px 64px 12px; }
.wsh-top { display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 9px; }
.wsh-logo { height: 34px; width: auto; margin-bottom: 7px; display: block; }
.wsh-hello { font-size: 21px; font-weight: 800; letter-spacing: -0.5px; }
.wsh-sub { font-size: 14px; color: #6b7482; font-weight: 600; margin-top: 6px; }
.wsh-date {
  font-size: 13px; font-weight: 700; color: #232833; padding: 10px 16px;
  border-radius: 14px; background: rgba(255, 255, 255, 0.5);
  backdrop-filter: blur(14px) saturate(150%); border: 1px solid rgba(255, 255, 255, 0.65);
}

.wsh-layout { display: grid; grid-template-columns: 1fr 320px; gap: 11px; align-items: start; }
.wsh-main { display: grid; grid-template-columns: repeat(3, 1fr); gap: 11px; align-items: start; }
.wsh-col { display: flex; flex-direction: column; gap: 11px; }
@media (max-width: 1200px) { .wsh-main { grid-template-columns: repeat(2, 1fr); } }
@media (max-width: 1080px) { .wsh-layout { grid-template-columns: 1fr; } }

.wsh-card {
  width: 100%; text-align: left; font-family: inherit; color: inherit; cursor: pointer;
  border-radius: 16px; padding: 12px 14px; position: relative; overflow: hidden; display: block;
  transition: transform 0.16s ease, box-shadow 0.16s ease;
}
.wsh-card:hover { transform: translateY(-3px); }
.wsh-card.locked { opacity: 0.55; filter: saturate(0.5); cursor: not-allowed; }
.wsh-card.locked:hover { transform: none; }
.wsh-glass {
  background: rgba(255, 255, 255, 0.55); backdrop-filter: blur(22px) saturate(155%);
  border: 1px solid rgba(255, 255, 255, 0.6);
  box-shadow: 0 16px 40px -22px rgba(60, 90, 150, 0.36), inset 0 1px 0 rgba(255, 255, 255, 0.7);
}
.wsh-solid { color: #fff; border: 1px solid rgba(255, 255, 255, 0.26); box-shadow: 0 18px 44px -20px rgba(60, 90, 150, 0.5); }
.c-crm { background: linear-gradient(155deg, #7cb6f7, #4f8fea); }
.c-mes { background: linear-gradient(155deg, #b3a4f5, #8b78ee); }
.c-tik { background: linear-gradient(155deg, #4fd1e6, #22b8d4); }
.blob { position: absolute; border-radius: 50%; filter: blur(30px); opacity: 0.5; background: rgba(255, 255, 255, 0.6); z-index: 1; }

.lbl { font-size: 12.5px; font-weight: 800; display: flex; align-items: center; gap: 6px; position: relative; z-index: 2; }
.lbl :deep([class*='i-lucide-']), .lbl .tk { width: 15px; height: 15px; }
.a-teal { color: #1f9d80; } .a-lime { color: #6ba01f; } .a-violet { color: #7a67dc; } .a-sky { color: #3f7fe0; }
.tag { margin-left: auto; font-size: 10.5px; font-weight: 700; color: #9aa0ac; background: rgba(120, 140, 170, 0.12); border-radius: 20px; padding: 3px 8px; }
.big { font-size: 25px; font-weight: 800; letter-spacing: -1px; line-height: 1.1; margin-top: 5px; position: relative; z-index: 2; }
.unit { font-size: 13px; margin-top: 2px; position: relative; z-index: 2; color: rgba(255, 255, 255, 0.85); }
.unit.gray { color: #9aa0ac; }
.sub2 { font-size: 12.5px; color: #9aa0ac; margin-top: 8px; }
.statrow { display: flex; gap: 14px; margin-top: 6px; position: relative; z-index: 2; }
.statrow b { font-size: 19px; font-weight: 800; display: block; letter-spacing: -0.5px; }
.statrow span { font-size: 11.5px; color: rgba(255, 255, 255, 0.8); }
.cta { margin-top: 10px; display: inline-flex; align-items: center; gap: 6px; font-size: 13px; font-weight: 800; padding: 8px 14px; border-radius: 12px; background: rgba(255, 255, 255, 0.22); position: relative; z-index: 2; }
.cta :deep([class*='i-lucide-']) { width: 15px; height: 15px; }
.cta2 { margin-top: auto; padding-top: 14px; display: inline-flex; align-items: center; gap: 5px; font-size: 12.5px; font-weight: 700; color: #6b7180; }
.cta2.muted { color: #9aa0ac; }
.cta2 :deep([class*='i-lucide-']) { width: 14px; height: 14px; }

.chart { width: 100%; height: 58px; margin-top: 10px; }
.chips { display: flex; gap: 8px; margin-top: 14px; }
.chips span { font-size: 12px; font-weight: 700; color: #5f6570; background: rgba(120, 140, 170, 0.1); border-radius: 9px; padding: 5px 11px; }

.week { display: flex; justify-content: space-between; margin-top: 10px; }
.wd { display: flex; flex-direction: column; align-items: center; gap: 6px; }
.wd span { font-size: 11px; color: #9aa0ac; font-weight: 600; }
.wd .o { width: 26px; height: 26px; border-radius: 50%; display: grid; place-items: center; }
.wd .on { background: linear-gradient(150deg, #9cc9f8, #5b9bef); color: #fff; }
.wd .off { background: #eef2f7; color: #c2cad4; }
.wd .o :deep([class*='i-lucide-']) { width: 14px; height: 14px; }

.wsh-ring { display: flex; align-items: center; gap: 14px; margin-top: 9px; position: relative; z-index: 2; }
.wsh-ring .pct { font-size: 15px; font-weight: 800; fill: #fff; }
.wsh-ring-t { font-size: 20px; font-weight: 800; letter-spacing: -0.5px; }
.checks { margin-top: 10px; display: flex; flex-direction: column; gap: 6px; position: relative; z-index: 2; }
.ck { display: flex; align-items: center; gap: 9px; font-size: 13px; }
.ck .ci { width: 18px; height: 18px; border-radius: 50%; display: grid; place-items: center; }
.ck .ci :deep([class*='i-lucide-']) { width: 12px; height: 12px; }
.ck.done .ci { background: rgba(255, 255, 255, 0.9); color: #8b78ee; }
.ck.wait { color: rgba(255, 255, 255, 0.75); }
.ck.wait .ci { background: rgba(255, 255, 255, 0.25); color: rgba(255, 255, 255, 0.7); }

.olist { margin-top: 12px; display: flex; flex-direction: column; }
.oi { display: flex; align-items: center; gap: 11px; padding: 9px 0; border-top: 1px solid #eef0f3; }
.oi:first-child { border-top: 0; }
.oic { width: 30px; height: 30px; border-radius: 9px; display: grid; place-items: center; color: #fff; flex: none; }
.oic :deep([class*='i-lucide-']) { width: 15px; height: 15px; }
.bg-lime { background: linear-gradient(150deg, #bfe388, #9fd162); }
.bg-teal { background: linear-gradient(150deg, #86ddc6, #3ec3a2); }
.bg-sky { background: linear-gradient(150deg, #9cc9f8, #5b9bef); }
.bg-violet { background: linear-gradient(150deg, #b3a4f5, #8b78ee); }
.ot { font-size: 13px; font-weight: 700; flex: 1; min-width: 0; }
.ot small { display: block; font-size: 10.5px; color: #9aa0ac; font-weight: 500; margin-top: 1px; }
.ost { font-size: 11px; font-weight: 700; color: #6f8a1a; background: #eef6d5; border-radius: 7px; padding: 3px 8px; }

.avs { display: flex; margin-top: 16px; }
.avs .av { width: 34px; height: 34px; border-radius: 50%; border: 2px solid #fff; margin-left: -9px; }
.avs .av:first-child { margin-left: 0; }
.av.a1 { background: linear-gradient(150deg, #9cc9f8, #5b9bef); }
.av.a2 { background: linear-gradient(150deg, #b3a4f5, #8b78ee); }
.av.a3 { background: linear-gradient(150deg, #86ddc6, #3ec3a2); }
.av.a4 { background: linear-gradient(150deg, #f7b0c0, #f088a0); }
.avs .more { width: 34px; height: 34px; border-radius: 50%; border: 2px solid #fff; margin-left: -9px; background: #e7effe; color: #3f7fe0; font-size: 11.5px; font-weight: 800; display: grid; place-items: center; }
.msg { margin-top: 14px; background: rgba(255, 255, 255, 0.6); border: 1px solid #eef0f3; border-radius: 12px; padding: 11px 13px; font-size: 12.5px; color: #9aa0ac; }
.msg b { font-weight: 800; color: #232833; }

/* 日程主栏 */
.wsh-rail {
  border-radius: 16px; padding: 12px 14px; position: relative; overflow: hidden; min-height: 0;
  background: rgba(255, 255, 255, 0.58); backdrop-filter: blur(24px) saturate(160%);
  border: 1px solid rgba(255, 255, 255, 0.65);
  box-shadow: 0 20px 50px -22px rgba(60, 90, 150, 0.42), inset 0 1px 0 rgba(255, 255, 255, 0.75);
  cursor: pointer; transition: transform 0.16s ease, box-shadow 0.16s ease;
}
.wsh-rail:hover { transform: translateY(-2px); box-shadow: 0 26px 56px -20px rgba(60, 90, 150, 0.5), inset 0 1px 0 rgba(255, 255, 255, 0.75); }
.wsh-rail:focus-visible { outline: 2px solid #5691ec; outline-offset: 2px; }
.r-aura { position: absolute; width: 260px; height: 200px; right: -60px; top: -70px; border-radius: 50%; filter: blur(46px); background: radial-gradient(circle, rgba(122, 170, 250, 0.5), transparent 68%); z-index: 1; }
.rhead { display: flex; justify-content: space-between; align-items: flex-start; position: relative; z-index: 2; }
.rl { font-size: 12.5px; font-weight: 800; color: #3f7fe0; display: flex; align-items: center; gap: 6px; }
.rl :deep([class*='i-lucide-']) { width: 15px; height: 15px; }
.rhead h2 { font-size: 18px; font-weight: 800; letter-spacing: -0.4px; margin-top: 4px; }
.today { text-align: center; background: linear-gradient(150deg, #7db8f7, #5691ec); color: #fff; border-radius: 12px; padding: 5px 11px; box-shadow: 0 10px 20px -8px rgba(86, 145, 236, 0.6); }
.today b { font-size: 24px; font-weight: 800; display: block; line-height: 1; }
.today span { font-size: 10.5px; opacity: 0.9; }
.cal { margin-top: 8px; position: relative; z-index: 2; }
.cal .hd { display: grid; grid-template-columns: repeat(7, 1fr); margin-bottom: 8px; }
.cal .hd span { font-size: 11px; color: #9aa0ac; text-align: center; font-weight: 700; }
.cal .bd { display: grid; grid-template-columns: repeat(7, 1fr); gap: 5px 0; }
.cal .bd span { position: relative; font-size: 12px; text-align: center; padding: 4px 0; font-weight: 600; color: #404855; border-radius: 8px; }
.cal .bd .mut { color: #cbd1da; }
.cal .bd .now { background: linear-gradient(150deg, #7db8f7, #5691ec); color: #fff; font-weight: 800; box-shadow: 0 8px 16px -6px rgba(86, 145, 236, 0.55); }
.cal .bd .has::after { content: ''; position: absolute; left: 50%; bottom: 3px; transform: translateX(-50%); width: 4px; height: 4px; border-radius: 50%; background: #8b78ee; }
.cal .bd .now.has::after { background: #fff; }
.agenda { margin-top: 9px; position: relative; z-index: 2; }
.ahd { display: flex; justify-content: space-between; align-items: center; }
.ahd b { font-size: 14px; font-weight: 800; }
.ahd span { font-size: 12px; color: #9aa0ac; font-weight: 600; }
.ev { display: flex; gap: 12px; margin-top: 7px; }
.ev .tm { width: 44px; flex: none; font-size: 12px; font-weight: 800; color: #4b535f; padding-top: 2px; }
.ev .eb { flex: 1; border-left: 3px solid; padding: 2px 0 2px 12px; }
.ev .eb b { font-size: 13.5px; font-weight: 700; display: block; }
.ev .eb small { font-size: 11.5px; color: #9aa0ac; }
.ev.blue .eb { border-color: #5b9bef; } .ev.teal .eb { border-color: #3ec3a2; }
.ev.violet .eb { border-color: #8b78ee; } .ev.rose .eb { border-color: #ef7f9c; }
.ev.lime .eb { border-color: #9fd162; } .ev.sky .eb { border-color: #38bdf8; }
.ev-empty { margin-top: 14px; padding: 18px 0; text-align: center; font-size: 12.5px; color: #9aa0ac; }
.newbtn { margin-top: 14px; width: 100%; font-family: inherit; font-size: 13px; font-weight: 800; color: #fff; background: linear-gradient(135deg, #6aa8f2, #4f8fea); border: none; border-radius: 12px; padding: 10px 0; cursor: pointer; display: flex; align-items: center; justify-content: center; gap: 7px; box-shadow: 0 12px 24px -10px rgba(79, 143, 234, 0.6); position: relative; z-index: 2; }
.newbtn :deep([class*='i-lucide-']) { width: 16px; height: 16px; }

.wsh-foot { text-align: center; color: #aeb6c1; font-size: 12px; margin-top: 12px; font-weight: 600; }
</style>
