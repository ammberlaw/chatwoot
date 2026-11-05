<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import DocSectionsAPI from 'dashboard/api/crm/docSections';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import WorkspaceMyOrders from './WorkspaceMyOrders.vue';
import WorkspaceCardRecords from './WorkspaceCardRecords.vue';
import wintouchLockup from 'dashboard/assets/images/wintouch/login-card-wordmark-rounded.png';

const props = defineProps({ context: { type: Object, required: true } });
const emit = defineEmits(['go', 'changeMonth', 'openOrder']);
const { t } = useI18n();
const { accountScopedRoute } = useAccount();
const c = computed(() => props.context);
const tr = (key, values) => t(`CRM.WORKSPACE_UI.${key}`, values || {});
const card =
  'min-w-0 rounded-[20px] border border-black/[0.06] bg-white p-5 text-[#202427] shadow-sm min-[1100px]:min-h-0 min-[1100px]:p-4';
const open = route => emit('go', route);
const openCard = (event, route, enabled = true) => {
  if (!enabled || event.target.closest('a, button, input, select, textarea, [role="button"]')) return;
  open(route);
};
const sections = ref([]);
onMounted(async () => {
  try {
    const { data } = await DocSectionsAPI.get();
    sections.value = data.payload || [];
  } catch {
    // The document center still opens when the section list is unavailable.
  }
});
// Five section shortcuts fit the compact three-column document card.
const folders = computed(() =>
  sections.value.length
    ? sections.value.slice(0, 5)
    : [{ id: null, name: tr('ALL_DOCS') }]
);
const workdays = computed(() => c.value.hrDays.filter(day => day.workday));
const presentDays = computed(() => workdays.value.filter(day => day.present));

</script>

<template>
  <div
    class="mx-auto hidden w-full max-w-[1280px] flex-col px-6 md:flex min-[1100px]:h-dvh min-[1100px]:px-8"
  >
    <header
      class="flex h-[52px] shrink-0 items-center gap-10 pr-48"
    >
      <img :src="wintouchLockup" alt="Wintouch" class="h-auto w-24 shrink-0" />
    </header>
    <main class="flex min-h-0 flex-1 flex-col">
      <div class="flex shrink-0 items-end justify-between gap-4 py-3">
        <div>
          <h1
            class="m-0 text-heading-1 !text-[20px] !font-medium !leading-snug text-[#202427]"
          >
            {{
              c.userName
                ? tr('GREETING', { greeting: c.greeting, name: c.userName })
                : c.greeting
            }}
          </h1>
          <p class="mt-1 text-label-small text-[#646c73]">
            {{ tr('TITLE') }}
          </p>
        </div>
      </div>
      <div
        class="grid min-h-0 flex-1 grid-cols-2 items-start gap-3 min-[1100px]:grid-cols-[1.06fr_1fr_1fr_1.15fr] min-[1100px]:items-stretch"
      >
        <div
          class="grid min-h-0 gap-3 min-[1100px]:h-full"
          :class="
            c.canAccessErp
              ? 'min-[1100px]:grid-rows-[minmax(0,1.6fr)_minmax(0,1fr)_minmax(0,1fr)]'
              : 'min-[1100px]:grid-rows-[minmax(0,1.8fr)_minmax(0,1fr)]'
          "
        >
          <section
            :class="card"
            class="flex min-h-[300px] flex-col !border-[#e2eaf0] !bg-[#f6fafd] min-[1100px]:!min-h-0 cursor-pointer focus-visible:outline focus-visible:outline-2 focus-visible:outline-blue-500"
            role="link"
            :tabindex="c.canOpenCrmCard ? 0 : -1"
            :aria-disabled="!c.canOpenCrmCard"
            :aria-label="tr('CRM')"
            @click="openCard($event, c.crmCardTarget, c.canOpenCrmCard)"
            @keydown.enter.self="c.canOpenCrmCard && open(c.crmCardTarget)"
          >
            <div class="flex items-center justify-between gap-2">
              <h2 class="flex items-baseline gap-2 text-heading-3 !font-medium">
                <span class="text-heading-3 !font-medium text-[#202427]">{{
                  tr('CODE_CRM')
                }}</span
                ><button class="m-0 block p-0 text-left !text-heading-3 !font-medium !text-[#202427]"
                  type="button"
                  :disabled="!c.canOpenCrmCard"
                  @click="open(c.crmCardTarget)"
                >
                  {{ tr('CUSTOMERS') }}
                </button>
              </h2>

            </div>
            <div class="mt-3 flex items-baseline gap-3">
              <strong
                class="text-[24px] font-normal leading-none tabular-nums"
                >{{ c.crmStats.follow_up_due ?? 0 }}</strong
              ><span class="text-label-small text-[#646c73]">{{
                tr('FOLLOW_UP')
              }}</span>
            </div>
            <dl
              class="my-3 grid grid-cols-3 gap-2 text-label-small text-[#737b83]"
            >
              <div>
                <dt class="inline">{{ tr('NEW') }}</dt>
                <dd class="ml-1 inline tabular-nums text-[#202427]">
                  {{ c.crmStats.new_today ?? 0 }}
                </dd>
              </div>
              <div class="border-l border-black/5 pl-2">
                <dt class="inline">{{ tr('REVISIT') }}</dt>
                <dd class="ml-1 inline tabular-nums text-[#202427]">
                  {{ c.crmStats.revisit_week ?? 0 }}
                </dd>
              </div>
              <div class="border-l border-black/5 pl-2">
                <dt class="inline">{{ tr('OVERDUE') }}</dt>
                <dd class="ml-1 inline tabular-nums text-[#202427]">
                  {{ c.crmStats.overdue ?? 0 }}
                </dd>
              </div>
            </dl>
            <WorkspaceCardRecords
              kind="crm"
              :enabled="c.canAccessCrm"
              class="!my-0 !min-h-0 flex-1 [&>div]:!h-full [&>div]:!min-h-0 [&>div]:!py-1 [&_[aria-hidden]]:!bg-[#dcebf6] [&_a]:!min-h-0 [&_a]:!rounded-2xl [&_a]:!p-3 [&_.size-12]:!size-7 [&_.size-12]:!bg-[#eef3f6] [&_.gap-3]:!gap-2 [&_.mt-4]:!mt-2 [&_.font-semibold]:!font-medium [&_.text-heading-3]:!text-heading-3"
            />
            <p
              v-if="!c.canAccessCrm"
              class="mt-2 text-label-small text-[#737b83]"
            >
              {{ c.isCrmFinanceOnly ? tr('SALES_ORDERS') : tr('NO_ACCESS') }}
            </p>
          </section>
          <section
            v-if="c.canAccessErp"
            :class="card"
            class="flex min-h-[160px] flex-col min-[1100px]:!min-h-0 cursor-pointer focus-visible:outline focus-visible:outline-2 focus-visible:outline-blue-500"
            role="link"
            tabindex="0"
            :aria-label="tr('ERP')"
            @click="openCard($event, 'erp_dashboard_index', true)"
            @keydown.enter.self="open('erp_dashboard_index')"
          >
            <div class="flex items-center justify-between gap-2">
              <h2 class="flex items-center gap-2 text-heading-3 !font-medium">
                <Icon icon="i-lucide-chart-no-axes-combined" class="size-4 shrink-0" />
                {{ tr('FINANCE_ERP') }}
              </h2>
              <span aria-hidden="true" class="grid size-7 shrink-0 place-items-center rounded-full border border-black/10"><Icon icon="i-lucide-arrow-up-right" class="size-4" /></span>
            </div>
            <div class="my-auto grid grid-cols-[1.15fr_1fr] items-center gap-3 py-3">
              <button type="button" class="min-w-0 text-left" @click="open('erp_vouchers_index')">
                <strong class="block text-[32px] font-medium leading-none tabular-nums">{{ c.erpDraftCount ?? '—' }}</strong>
                <span class="mt-2 flex items-center gap-1.5 text-label-small text-[#858d80]"><Icon icon="i-lucide-receipt-text" class="size-3.5 shrink-0 text-[#3e9276]" />{{ tr('DRAFT_VOUCHERS') }}</span>
              </button>
              <button type="button" class="min-w-0 border-l border-black/10 py-1 pl-4 text-left" @click="open('erp_reports_index')">
                <span class="block text-label-small text-[#858d80]">{{ tr('VIEW_REPORTS') }}</span>
                <span class="mt-2 flex items-center gap-1.5 text-label-small text-[#858d80]"><Icon icon="i-lucide-chart-pie" class="size-3.5 shrink-0 text-[#3e9276]" />{{ tr('MONTH_REPORTS') }}</span>
              </button>
            </div>
          </section>
          <button
            type="button"
            :class="card"
            class="flex min-h-[164px] flex-col text-left min-[1100px]:!min-h-0"
            @click="open('crm_org_structure_index')"
          >
            <h2 class="flex items-center gap-2 text-heading-3 !font-medium">
              <Icon icon="i-lucide-users" class="size-4 shrink-0" />{{
                tr('HR')
              }}
            </h2>
            <div
              class="my-auto flex w-full items-center justify-between gap-2 py-1"
            >
              <div class="flex items-baseline gap-2">
                <strong
                  class="text-[24px] font-normal leading-none tabular-nums"
                  >{{ presentDays.length }}</strong
                ><span class="text-label-small text-[#858d80]"
                  >/ {{ workdays.length }} {{ tr('WEEK_ATTENDANCE') }}</span
                >
              </div>
              <svg
                viewBox="0 0 80 80"
                class="size-12 shrink-0"
                role="img"
                :aria-label="`${tr('ATTENDANCE_RATE')} ${c.attendancePercent}%`"
              >
                <circle
                  cx="40"
                  cy="40"
                  r="33"
                  fill="none"
                  stroke="#e9ece6"
                  stroke-width="5"
                />
                <circle
                  cx="40"
                  cy="40"
                  r="33"
                  fill="none"
                  stroke="#9fb98a"
                  stroke-width="5"
                  pathLength="100"
                  :stroke-dasharray="`${c.attendancePercent} 100`"
                  transform="rotate(-90 40 40)"
                />
                <text
                  x="40"
                  y="44"
                  text-anchor="middle"
                  class="fill-[#30392c] text-label-small"
                >
                  {{ c.attendancePercent }}%
                </text>
              </svg>
            </div>
            <dl
              class="grid w-full grid-cols-3 border-t border-black/5 pt-2 text-label-small text-[#858d80]"
            >
              <div>
                <dd
                  class="m-0 text-heading-1 !text-[20px] !leading-6 !font-normal tabular-nums text-[#465340]"
                >
                  {{ workdays.length }}
                </dd>
                <dt class="mt-1">{{ tr('EXPECTED') }}</dt>
              </div>
              <div>
                <dd
                  class="m-0 text-heading-1 !text-[20px] !leading-6 !font-normal tabular-nums text-[#465340]"
                >
                  {{ presentDays.length }}
                </dd>
                <dt class="mt-1">{{ tr('PRESENT') }}</dt>
              </div>
              <div>
                <dd class="m-0 text-heading-1 !text-[20px] !leading-6 !font-normal text-[#465340]">
                  —
                </dd>
                <dt class="mt-1">{{ tr('LEAVE') }}</dt>
              </div>
            </dl>
          </button>
        </div>
        <div class="flex min-h-0 flex-col gap-3 min-[1100px]:h-full">
          <WorkspaceMyOrders
            class="!min-h-0 !rounded-[20px] !border-black/[0.06] !bg-white !p-4 !shadow-sm min-[1100px]:h-[35%] [&_.rounded-full.border]:!border-transparent [&_.text-heading-3]:!text-heading-3 [&_button.block]:!bg-[#f6f7f7] [&_button.block]:!p-3 [&_.my-3]:!my-2 [&_button.block_.gap-3]:!gap-2 [&_.mt-3]:!mt-2"
            @overview="open('mes_dashboard_index')"
            @open="emit('openOrder', $event)"
          />
          <section
            :class="card"
            class="min-h-[108px] min-[1100px]:!min-h-0 cursor-pointer focus-visible:outline focus-visible:outline-2 focus-visible:outline-blue-500"
            role="link"
            tabindex="0"
            :aria-label="tr('OA')"
            @click="openCard($event, 'crm_approvals_index', true)"
            @keydown.enter.self="open('crm_approvals_index')"
          >
            <div class="flex items-center justify-between gap-2">
              <h2 class="flex items-center gap-2 whitespace-nowrap text-heading-3 !font-medium">
                <Icon icon="i-lucide-clipboard-check" class="size-4 shrink-0" />
                {{ tr('OA_APPROVAL') }}
              </h2>
              <span aria-hidden="true" class="grid size-7 shrink-0 place-items-center rounded-full border border-black/10"><Icon icon="i-lucide-arrow-up-right" class="size-4" /></span>
            </div>
            <div class="mt-3 flex items-baseline gap-2">
              <strong
                class="text-[28px] font-normal leading-none tabular-nums"
                >{{ c.oaMetric }}</strong
              ><span class="text-label-small text-[#737b83]">{{
                c.stats.approverView
                  ? tr('PENDING_ITEMS')
                  : tr('MY_REQUESTS')
              }}</span>
            </div>
          </section>
        </div>
        <div class="flex min-h-0 flex-col gap-3 min-[1100px]:h-full">
          <button
            type="button"
            :class="card"
            class="flex min-h-[180px] flex-col text-left min-[1100px]:!min-h-0 min-[1100px]:h-[29%]"
            @click="open('crm_team_chat_index')"
          >
            <div class="flex w-full items-center gap-2">
              <Icon icon="i-lucide-messages-square" class="size-4 shrink-0" />
              <h2 class="text-heading-3 !font-medium">{{ tr('TEAM') }}</h2>
            </div>
            <div class="mt-auto w-full pt-4">
              <WorkspaceCardRecords
                kind="team"
                compact
                class="!mt-0 [&_.mb-3]:!mb-0 [&_.size-9]:!size-8"
              />
              <p class="mt-3 text-label-small text-[#8a9288]">
                {{ c.stats.unread ? tr('VIEW_TEAM_MESSAGES') : tr('NO_MESSAGES') }}
              </p>
            </div>
          </button>
          <button
            v-if="c.canAccessTiktok"
            type="button"
            :class="card"
            class="min-h-[132px] text-left min-[1100px]:!min-h-0 min-[1100px]:h-[22%]"
            @click="open('tiktok_dashboard_index')"
          >
            <div class="flex items-center justify-between gap-2">
              <h2 class="text-heading-3 !font-medium">
                <span class="mb-1 flex items-center gap-2 text-heading-3 !font-medium text-[#202427]"><img :src="'/assets/images/dashboard/channels/tiktok.png'" alt="" class="size-4 object-contain" />{{ tr('CODE_TIKTOK') }}</span
                >{{ tr('CROSS_BORDER') }}
              </h2>

            </div>
            <p class="mt-2 text-label-small text-[#737b83]">
              {{ tr('TIKTOK_DESCRIPTION') }}
            </p>
          </button>
          <section
            :class="card"
            class="min-h-[188px] min-[1100px]:!min-h-0 min-[1100px]:h-[32%] cursor-pointer focus-visible:outline focus-visible:outline-2 focus-visible:outline-blue-500"
            role="link"
            tabindex="0"
            :aria-label="tr('DOCS')"
            @click="openCard($event, 'crm_doc_center_index', true)"
            @keydown.enter.self="open('crm_doc_center_index')"
          >
            <div class="flex items-center justify-between gap-2">
              <h2 class="text-heading-3 !font-medium">
                <button class="m-0 block p-0 text-left !text-heading-3 !font-medium !text-[#202427]" type="button" @click="open('crm_doc_center_index')">
                  {{ tr('DOCS') }}
                </button>
              </h2>

            </div>
            <div class="mt-2 grid grid-cols-3 gap-2">
              <router-link
                v-for="(folder, index) in folders"
                :key="folder.id || 'all'"
                :to="
                  accountScopedRoute(
                    'crm_doc_center_index',
                    {},
                    folder.id ? { section: folder.id } : {}
                  )
                "
                class="group flex min-w-0 flex-col items-center gap-2 rounded-lg text-center no-underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-blue-500"
              >
                <div class="relative isolate h-[52px] w-14 shrink-0 transition-transform duration-150 group-hover:-translate-y-1 motion-reduce:transition-none">
                  <span class="absolute inset-x-4 bottom-1 -z-10 h-5 rounded-full bg-blue-500/20 blur-md" aria-hidden="true" />
                  <svg viewBox="0 0 168 156" class="h-full w-full" aria-hidden="true">
                    <defs>
                      <linearGradient :id="`workspace-folder-front-${index}`" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="0%" stop-color="#83bdff" />
                        <stop offset="100%" stop-color="#408cff" />
                      </linearGradient>
                    </defs>
                    <rect x="4" y="20" width="160" height="132" rx="28" fill="#549dff" />
                    <path d="M23 23 56 17l12 82-44 5L14 39q-3-13 9-16Z" fill="#ffd0dd" />
                    <path d="m114 18 30 6q13 2 10 16l-12 64-43-8Z" fill="#ffe79c" />
                    <rect x="46" y="6" width="76" height="109" rx="12" fill="#fff" />
                    <path d="M59 28h50M59 38h50M59 48h50M59 58h24" stroke="#e5e5eb" stroke-width="3.5" stroke-linecap="round" />
                    <path d="M4 95q0-23 24-23h112q24 0 24 23v29q0 28-28 28H32Q4 152 4 124Z" :fill="`url(#workspace-folder-front-${index})`" />
                  </svg>
                  <span class="absolute inset-x-1.5 bottom-2.5 truncate text-left text-label-small !text-[10px] !font-medium !text-white" :title="folder.name">{{ folder.name }}</span>
                </div>
              </router-link>
            </div>
          </section>
        </div>
        <section
          :class="card"
          class="flex min-h-[560px] flex-col min-[1100px]:!min-h-0 min-[1100px]:h-[94%]"
          :aria-label="tr('MY_SCHEDULE')"
        >
          <div class="flex items-center justify-between gap-2">
            <h3 class="text-heading-3 !font-medium">{{ c.monthLabel }}</h3>
            <div class="flex gap-1">
              <button
                type="button"
                :aria-label="tr('PREV_MONTH')"
                class="grid size-7 place-items-center rounded-lg hover:bg-black/5"
                @click="emit('changeMonth', -1)"
              >
                <Icon icon="i-lucide-chevron-left" class="size-4" /></button
              ><button
                type="button"
                :aria-label="tr('NEXT_MONTH')"
                class="grid size-7 place-items-center rounded-lg hover:bg-black/5"
                @click="emit('changeMonth', 1)"
              >
                <Icon icon="i-lucide-chevron-right" class="size-4" />
              </button>
            </div>
          </div>
          <div
            class="mt-3 grid grid-cols-7 text-center text-label-small text-[#737b83]"
          >
            <span v-for="day in tr('WEEKDAYS').split(',')" :key="day">{{
              day
            }}</span>
          </div>
          <div
            class="mt-2 grid grid-cols-7 gap-y-1 text-center text-label-small"
          >
            <span
              v-for="(cell, i) in c.calCells"
              :key="i"
              class="relative grid size-6 place-items-center justify-self-center rounded-lg tabular-nums"
              :class="
                cell.now
                  ? 'bg-[#252b2f] text-white'
                  : cell.mut
                    ? 'text-[#b6bcc2]'
                    : 'text-[#202427]'
              "
              >{{ cell.n
              }}<span
                v-if="cell.has"
                class="absolute bottom-0.5 size-0.5 rounded-full bg-current"
            /></span>
          </div>
          <div
            class="mt-3 flex items-center justify-between border-t border-black/5 pt-3"
          >
            <h3 class="text-heading-3 !font-medium">{{ tr('TODAY') }}</h3>
            <span class="text-label-small text-[#737b83]"
              >{{ c.todayEvents.length }} {{ tr('ITEMS') }}</span
            >
          </div>
          <div class="min-h-0 flex-1 overflow-y-auto py-3">
            <button
              v-for="event in c.todayEvents"
              :key="`${event.id}-${event.starts_at}`"
              type="button"
              class="flex w-full gap-3 border-b border-black/5 py-3 text-left text-label-small"
              @click="open('crm_schedule_index')"
            >
              <time class="shrink-0 text-[#737b83]">{{
                event.all_day ? tr('ALL_DAY') : event.starts_at?.slice(11, 16)
              }}</time
              ><span class="min-w-0"
                ><strong class="line-clamp-2 font-medium">{{
                  event.title
                }}</strong
                ><span class="mt-1 block truncate text-[#737b83]">{{
                  [event.owner_name, ...(event.participant_names || [])]
                    .filter(Boolean)
                    .join('、')
                }}</span></span
              >
            </button>
            <button
              v-if="!c.todayEvents.length"
              type="button"
              class="flex h-full min-h-12 w-full flex-col items-center justify-center gap-3 text-label-small text-[#8a9299]"
              @click="open('crm_schedule_index')"
            >
              <Icon
                icon="i-lucide-calendar-days"
                class="size-6 text-[#b4bcc3]"
              />{{ tr('EMPTY_DAY') }}
            </button>
          </div>
          <button
            type="button"
            class="flex min-h-9 w-full items-center justify-center gap-2 rounded-xl bg-[#252b2f] px-3 py-2 text-label-small text-white hover:bg-black"
            @click="open('crm_schedule_index')"
          >
            <Icon icon="i-lucide-plus" class="size-4" />{{ tr('NEW_EVENT') }}
          </button>
        </section>
      </div>
    </main>
    <footer
      class="h-6 shrink-0 pt-1 text-center text-label-small !text-[10px] text-[#858b90]"
    >
      {{ tr('CREDIT') }}
      <span class="ml-3">{{ tr('REGISTRATION') }}</span>
    </footer>
  </div>
</template>
