<script setup>
// 问题反馈：业务员在 AI 助手里说「这是不是 bug」时报上来的单子。
//
// 为什么非有这一页不可：提交只发一条站内通知，刷过去就埋了，既没有清单也没法标
// 「修好了」——生产上攒了 8 条全是待查，最早那条放了一周多没人动。
//
// 每条带着**提交那一刻的现场**（单据、当时状态、卡在哪、在等谁），这才是它比
// 微信截图强的地方：打开就能直接动手，不用再考古一遍。
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
// ⚠️ 这个接口走 buildCrmClient 直连 axios，**没有驼峰化**（没经 _crmStoreFactory 的
// camelize），字段一律按后端的蛇形写：reporter_name / created_at / subject_no…
import IssueReportsAPI from 'dashboard/api/crm/issueReports';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';

const STATUS_LABEL = {
  new: '待查',
  ack: '已受理',
  fixed: '已修复',
  wontfix: '不做',
};
// 待查/已受理用醒目色，收了尾的两档退成灰——一屏扫过去先看见还没处理的。
const STATUS_CLASS = {
  new: 'bg-n-amber-3 text-n-amber-11',
  ack: 'bg-n-iris-3 text-n-iris-11',
  fixed: 'bg-n-alpha-2 text-n-slate-11',
  wontfix: 'bg-n-alpha-2 text-n-slate-10',
};
const STATUS_OPTIONS = Object.entries(STATUS_LABEL).map(([value, label]) => ({
  value,
  label,
}));

const reports = ref([]);
const counts = ref({});
const loading = ref(false);
const savingId = ref(null);
const tab = ref('open');
// 每条的待保存编辑态（状态 + 处理说明），按 id 存，切筛选不丢。
const edits = ref({});

const TABS = [
  { key: 'open', label: '待处理' },
  { key: 'all', label: '全部' },
];

const openCount = computed(
  () => (counts.value.new || 0) + (counts.value.ack || 0)
);
const tabCount = key =>
  key === 'open'
    ? openCount.value
    : Object.values(counts.value).reduce((a, b) => a + b, 0);

const visible = computed(() =>
  tab.value === 'open'
    ? reports.value.filter(r => r.status === 'new' || r.status === 'ack')
    : reports.value
);

const editOf = report => {
  if (!edits.value[report.id]) {
    edits.value[report.id] = {
      status: report.status,
      resolution: report.resolution || '',
    };
  }
  return edits.value[report.id];
};

const load = async () => {
  loading.value = true;
  try {
    const { data } = await IssueReportsAPI.get({ per_page: 200 });
    reports.value = data.payload || [];
    counts.value = data.counts || {};
    edits.value = {};
  } catch {
    reports.value = [];
    useAlert('问题反馈加载失败');
  } finally {
    loading.value = false;
  }
};

const save = async report => {
  const edit = editOf(report);
  savingId.value = report.id;
  try {
    const { data } = await IssueReportsAPI.update(report.id, {
      report: { status: edit.status, resolution: edit.resolution },
    });
    Object.assign(report, data);
    // 计数在后端按整表算，改完重取一次比在前端加减可靠。
    const { data: fresh } = await IssueReportsAPI.get({ per_page: 1 });
    counts.value = fresh.counts || counts.value;
    useAlert('已保存');
  } catch (error) {
    useAlert(error?.response?.data?.error || '保存失败');
  } finally {
    savingId.value = null;
  }
};

const fmtTime = value =>
  value ? new Date(value).toLocaleString('zh-CN', { hour12: false }) : '';

// 现场摘要：没诊断到的字段不摆空行。
const diagnosisLines = report => {
  const d = report.diagnosis || {};
  const lines = [];
  if (report.subject_no)
    lines.push(
      `单据：${[d.doc_type, report.subject_no].filter(Boolean).join(' ')}${report.action_type ? `（想做：${report.action_type}）` : ''}`
    );
  if (d.status_label) lines.push(`当前：${d.status_label}`);
  if (d.blocker) lines.push(`卡在：${d.blocker}`);
  if (d.waiting) {
    const who =
      (d.waiting.names || []).join('、') || '系统里没查到该负责这一步的人';
    lines.push(
      `等：${d.waiting.label}（${who}）${d.waiting.notified === false ? '　⚠️ 系统没给他们发过通知' : ''}`
    );
  }
  return lines;
};

onMounted(load);
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-hidden bg-n-solid-1">
    <header
      class="flex flex-wrap items-center gap-3 px-5 py-6 shrink-0 sm:px-8"
    >
      <h1 class="text-heading-1 text-n-slate-12">问题反馈</h1>
      <div data-tabbar="page" class="my-0">
        <button
          v-for="t in TABS"
          :key="t.key"
          :aria-selected="tab === t.key"
          @click="tab = t.key"
        >
          {{ t.label }} {{ tabCount(t.key) }}
        </button>
      </div>
      <Button
        label="刷新"
        icon="i-lucide-refresh-cw"
        variant="outline"
        color="slate"
        size="sm"
        class="ml-auto"
        :is-loading="loading"
        @click="load"
      />
    </header>

    <div class="flex-1 px-5 pb-6 overflow-auto sm:px-8">
      <p v-if="loading" class="py-10 text-sm text-center text-n-slate-10">
        加载中…
      </p>
      <p
        v-else-if="!visible.length"
        class="py-10 text-sm text-center text-n-slate-10"
      >
        {{ tab === 'open' ? '没有待处理的问题。' : '还没有人报过问题。' }}
      </p>

      <div v-else class="flex flex-col max-w-4xl gap-3">
        <article
          v-for="r in visible"
          :key="r.id"
          class="flex flex-col gap-3 p-4 border rounded-xl border-n-weak"
        >
          <div class="flex flex-wrap items-center gap-2">
            <span
              class="px-2 py-0.5 text-label-small rounded-md shrink-0"
              :class="STATUS_CLASS[r.status]"
            >
              {{ STATUS_LABEL[r.status] || r.status }}
            </span>
            <span class="text-label-small text-n-slate-10">#{{ r.id }}</span>
            <span class="font-medium text-n-slate-12">
              {{ r.reporter_name }}
            </span>
            <span class="ml-auto text-label-small text-n-slate-10">
              {{ fmtTime(r.created_at) }}
            </span>
          </div>

          <p class="text-sm whitespace-pre-wrap text-n-slate-12">
            {{ r.body }}
          </p>

          <div
            v-if="diagnosisLines(r).length"
            class="flex flex-col gap-1 px-3 py-2 rounded-lg bg-n-alpha-1"
          >
            <span
              v-for="(line, i) in diagnosisLines(r)"
              :key="i"
              class="text-label-small text-n-slate-11"
            >
              {{ line }}
            </span>
          </div>

          <p v-if="r.resolved_by_name" class="text-label-small text-n-slate-10">
            {{ r.resolved_by_name }} 于 {{ fmtTime(r.resolved_at) }} 收尾
          </p>

          <div class="flex flex-wrap items-center gap-2">
            <SelectCard
              v-model="editOf(r).status"
              :options="STATUS_OPTIONS"
              trigger-class="w-28"
            />
            <Input
              v-model="editOf(r).resolution"
              class="flex-1 min-w-48 reset-base !h-9"
              placeholder="处理说明"
            />
            <Button
              label="保存"
              icon="i-lucide-check"
              color="iris"
              size="sm"
              :is-loading="savingId === r.id"
              @click="save(r)"
            />
          </div>
        </article>
      </div>
    </div>
  </div>
</template>
