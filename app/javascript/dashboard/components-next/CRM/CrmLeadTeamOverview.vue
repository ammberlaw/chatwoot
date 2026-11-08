<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import LeadCampaignsAPI from 'dashboard/api/crm/leadCampaigns';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const { t } = useI18n();
const team = ref(null);
const loading = ref(false);
const failed = ref(false);

const monthlyMetrics = computed(() => [
  { key: 'taken', label: t('CRM.DASHBOARD.LEAD_TEAM.TAKEN') },
  { key: 'claimed', label: t('CRM.DASHBOARD.LEAD_TEAM.CLAIMED') },
  { key: 'discarded', label: t('CRM.DASHBOARD.LEAD_TEAM.DISCARDED') },
  { key: 'unlocked', label: t('CRM.DASHBOARD.LEAD_TEAM.UNLOCKED') },
]);

// 沿用团队接口的当前持有 / 本月产出口径，不传销售看板的期间筛选。
const load = async () => {
  loading.value = true;
  failed.value = false;
  try {
    const { data } = await LeadCampaignsAPI.teamStats();
    team.value = data;
  } catch {
    failed.value = true;
  } finally {
    loading.value = false;
  }
};

const initials = name =>
  name
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map(part => part[0])
    .join('')
    .toUpperCase();

onMounted(load);
</script>

<template>
  <section data-lead-team-overview :aria-busy="loading" class="min-w-0">
    <header class="mb-2 flex flex-wrap items-center justify-between gap-2">
      <div class="flex min-w-0 items-center gap-3">
        <span
          class="h-6 w-1.5 shrink-0 rounded-full bg-wintouch-yellow"
          aria-hidden="true"
        />
        <div class="flex min-w-0 flex-wrap items-center gap-x-3 gap-y-1">
          <div class="flex flex-wrap items-center gap-2.5">
            <h2 class="mb-0 text-heading-2 text-n-slate-12">
              {{ t('CRM.DASHBOARD.LEAD_TEAM.TITLE') }}
            </h2>
            <span
              class="rounded-full bg-n-slate-3 px-2 py-0.5 text-label-small text-n-slate-11"
            >
              {{ t('CRM.DASHBOARD.LEAD_TEAM.TEAM_LABEL') }}
            </span>
          </div>
          <p class="mb-0 text-label-small text-n-slate-11">
            {{ t('CRM.DASHBOARD.LEAD_TEAM.SUBTITLE') }}
          </p>
        </div>
        <button
          v-tooltip.top="{
            content: t('CRM.DASHBOARD.LEAD_TEAM.PERIOD_HINT'),
            triggers: ['hover', 'focus'],
          }"
          type="button"
          :aria-label="t('CRM.DASHBOARD.LEAD_TEAM.PERIOD_HINT')"
          class="reset-base inline-flex size-8 shrink-0 items-center justify-center rounded-full p-0 text-n-slate-10 transition-colors hover:bg-n-alpha-1 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-wintouch-ink/50 motion-reduce:transition-none"
        >
          <Icon icon="i-lucide-info" class="size-4" />
        </button>
      </div>
      <div class="flex shrink-0 items-center gap-3">
        <span v-if="team" class="text-label-small text-n-slate-11">{{
          t('CRM.DASHBOARD.LEAD_TEAM.PEOPLE', { count: team.summary.people })
        }}</span>
        <Button
          v-tooltip.top="t('CRM.DASHBOARD.LEAD_TEAM.REFRESH')"
          :aria-label="t('CRM.DASHBOARD.LEAD_TEAM.REFRESH')"
          icon="i-lucide-refresh-cw"
          size="sm"
          variant="ghost"
          color="slate"
          :disabled="loading"
          :is-loading="loading"
          @click="load"
        />
      </div>
    </header>

    <div
      v-if="loading && !team"
      role="status"
      class="flex min-h-48 items-center justify-center gap-2 rounded-3xl border border-n-weak/70 bg-n-solid-1 px-5 py-8 text-label-small text-n-slate-11"
    >
      <Icon
        icon="i-lucide-loader-circle"
        class="size-4 animate-spin motion-reduce:animate-none"
      />
      {{ t('CRM.DASHBOARD.LEAD_TEAM.LOADING') }}
    </div>
    <div
      v-else-if="failed"
      role="alert"
      class="flex min-h-48 flex-col items-center justify-center gap-3 rounded-3xl border border-n-weak/70 bg-n-solid-1 px-5 py-8 text-center"
    >
      <Icon icon="i-lucide-cloud-off" class="size-6 text-n-slate-10" />
      <p class="mb-0 text-label-small text-n-slate-11">
        {{ t('CRM.DASHBOARD.LEAD_TEAM.FAILED') }}
      </p>
      <Button
        :label="t('CRM.DASHBOARD.LEAD_TEAM.RETRY')"
        size="sm"
        :disabled="loading"
        @click="load"
      />
    </div>
    <template v-else-if="team">
      <div class="grid grid-cols-2 overflow-hidden rounded-2xl sm:grid-cols-4">
        <dl
          class="m-0 flex min-w-0 items-center justify-between gap-3 bg-wintouch-yellow px-4 py-2.5 text-wintouch-ink"
        >
          <dt class="text-label-small">
            {{ t('CRM.DASHBOARD.LEAD_TEAM.HOLDING') }}
          </dt>
          <dd class="m-0 text-3xl font-semibold leading-none tabular-nums">
            {{ team.summary.holding }}
          </dd>
        </dl>
        <dl
          class="m-0 flex min-w-0 items-center justify-between gap-3 border-l border-wintouch-ink/15 bg-wintouch-yellow px-4 py-2.5 text-wintouch-ink"
        >
          <dt class="text-label-small">
            {{ t('CRM.DASHBOARD.LEAD_TEAM.STALE', { days: team.stale_days }) }}
          </dt>
          <dd class="m-0 text-2xl font-semibold leading-none tabular-nums">
            {{ team.summary.stale }}
          </dd>
        </dl>
        <dl
          class="m-0 flex min-w-0 items-center justify-between gap-3 bg-wintouch-ink px-4 py-2.5 text-white"
        >
          <dt class="text-label-small text-white/70">
            {{ t('CRM.DASHBOARD.LEAD_TEAM.CLAIMED') }}
          </dt>
          <dd class="m-0 text-2xl font-semibold leading-none tabular-nums">
            {{ team.summary.claimed }}
          </dd>
        </dl>
        <dl
          class="m-0 flex min-w-0 items-center justify-between gap-3 border-l border-white/15 bg-wintouch-ink px-4 py-2.5 text-white"
        >
          <dt class="text-label-small text-white/70">
            {{ t('CRM.DASHBOARD.LEAD_TEAM.UNLOCKED') }}
          </dt>
          <dd class="m-0 text-2xl font-semibold leading-none tabular-nums">
            {{ team.summary.unlocked }}
          </dd>
        </dl>
      </div>
      <div
        v-if="team.rows.length"
        role="region"
        :aria-label="t('CRM.DASHBOARD.LEAD_TEAM.DETAILS')"
        tabindex="0"
        class="mt-2 max-h-64 overflow-y-auto overscroll-contain rounded-2xl focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-wintouch-ink/50"
      >
        <ul class="reset-base m-0 flex list-none flex-col gap-1 p-0">
          <li
            v-for="(row, index) in team.rows"
            :key="row.user_id"
            class="min-w-0"
          >
            <article
              class="grid grid-cols-2 items-center gap-x-3 gap-y-3 rounded-xl border border-n-weak/60 bg-n-solid-1 px-4 py-2 sm:grid-cols-4 lg:grid-cols-[minmax(10rem,1.6fr)_repeat(6,minmax(3.5rem,0.7fr))_minmax(5.5rem,1fr)]"
            >
              <div
                class="col-span-2 flex min-w-0 items-center gap-2 sm:col-span-4 lg:col-span-1"
              >
                <span
                  class="flex size-8 shrink-0 items-center justify-center rounded-lg text-label-small"
                  :class="
                    index % 2
                      ? 'bg-wintouch-yellow text-wintouch-ink'
                      : 'bg-wintouch-ink text-wintouch-yellow'
                  "
                  aria-hidden="true"
                >
                  {{ initials(row.name) }}
                </span>
                <h3
                  class="mb-0 text-heading-3 text-n-slate-12 [overflow-wrap:anywhere]"
                >
                  {{ row.name }}
                </h3>
              </div>
              <dl class="m-0 min-w-0">
                <dt class="text-label-small text-n-slate-11">
                  {{ t('CRM.DASHBOARD.LEAD_TEAM.HOLDING') }}
                </dt>
                <dd
                  class="m-0 mt-0.5 text-lg font-semibold leading-none tabular-nums text-n-slate-12"
                >
                  {{ row.holding }}
                </dd>
              </dl>
              <dl class="m-0 min-w-0">
                <dt class="text-label-small text-n-slate-11">
                  {{
                    t('CRM.DASHBOARD.LEAD_TEAM.STALE_SHORT', {
                      days: team.stale_days,
                    })
                  }}
                </dt>
                <dd
                  class="m-0 mt-0.5 inline-flex min-w-6 justify-center rounded-full px-1.5 text-label font-semibold tabular-nums"
                  :class="
                    row.stale > 0
                      ? 'bg-n-amber-3 text-n-amber-11'
                      : 'text-n-slate-11'
                  "
                >
                  {{ row.stale }}
                </dd>
              </dl>
              <dl
                v-for="metric in monthlyMetrics"
                :key="metric.key"
                class="m-0 min-w-0"
              >
                <dt class="text-label-small text-n-slate-11">
                  {{ metric.label }}
                </dt>
                <dd
                  class="m-0 mt-0.5 text-lg font-semibold leading-none tabular-nums"
                  :class="
                    metric.key === 'claimed' && row.claimed > 0
                      ? 'text-n-teal-11'
                      : 'text-n-slate-12'
                  "
                >
                  {{ row[metric.key] }}
                </dd>
              </dl>
              <dl class="col-span-2 m-0 min-w-0 lg:col-span-1">
                <dt class="text-label-small text-n-slate-11">
                  {{ t('CRM.DASHBOARD.LEAD_TEAM.CONVERT') }}
                </dt>
                <dd class="m-0 mt-0.5 flex items-center gap-1">
                  <strong
                    class="rounded-full bg-wintouch-ink px-2 text-label-small font-semibold tabular-nums text-white"
                  >
                    {{
                      row.convert == null
                        ? t('CRM.DASHBOARD.DESIGN.UNSET')
                        : `${row.convert}%`
                    }}
                  </strong>
                  <button
                    v-tooltip.top="{
                      content: t('CRM.DASHBOARD.LEAD_TEAM.CONVERT_HINT'),
                      triggers: ['hover', 'focus'],
                    }"
                    type="button"
                    :aria-label="t('CRM.DASHBOARD.LEAD_TEAM.CONVERT_HINT')"
                    class="reset-base inline-flex size-6 shrink-0 items-center justify-center rounded-full p-0 text-n-slate-10 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-wintouch-ink/50"
                  >
                    <Icon icon="i-lucide-info" class="size-3.5" />
                  </button>
                </dd>
              </dl>
            </article>
          </li>
        </ul>
      </div>
      <div
        v-else
        class="mt-2 rounded-2xl border border-dashed border-n-weak bg-n-solid-1 px-4 py-6 text-center text-label-small text-n-slate-11"
      >
        {{ t('CRM.DASHBOARD.LEAD_TEAM.EMPTY') }}
      </div>
    </template>
  </section>
</template>
