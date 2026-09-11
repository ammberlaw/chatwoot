<script setup>
import { ref, computed, onMounted, onActivated } from 'vue';
import { useRouter } from 'vue-router';
import PageHeader from '@/components/PageHeader.vue';
import DataState from '@/components/DataState.vue';
import { fetchApprovals, fetchApprovalCounts } from '@/api/crm';
import { APPROVAL_STATUS_LABELS } from '@/constants/crm';
import { shortDateTime } from '@/utils/format';

defineOptions({ name: 'ApprovalsPage' });

// 视图 = 后端 filter 参数；「待我审批」只在当前用户确实是审批人时才显示（counts.approver_view）
const VIEWS = [
  { key: 'todo', label: '待我审批', badge: 'todo', approverOnly: true },
  { key: '', label: '我发起的', badge: 'mine' },
  { key: 'cc', label: '抄送我', badge: 'cc' },
  { key: 'done', label: '我已审批', badge: 'done', approverOnly: true },
];

const STATUS_CLASS = {
  pending: 'bg-n-amber-3 text-n-amber-11',
  approved: 'bg-n-teal-3 text-n-teal-11',
  rejected: 'bg-n-ruby-3 text-n-ruby-11',
  canceled: 'bg-n-alpha-1 text-n-slate-11',
};

const router = useRouter();
const list = ref([]);
const total = ref(0);
const page = ref(1);
const view = ref('todo');
const counts = ref({});
const loading = ref(true);
const loadingMore = ref(false);
const failed = ref(false);
const staleAt = ref(null);

const hasMore = computed(() => list.value.length < total.value);
const views = computed(() =>
  VIEWS.filter(v => !v.approverOnly || counts.value.approver_view !== false)
);

const load = async ({ append = false } = {}) => {
  if (append) {
    loadingMore.value = true;
  } else {
    loading.value = true;
    failed.value = false;
    page.value = 1;
  }
  try {
    const r = await fetchApprovals({
      page: page.value,
      filter: view.value || undefined,
    });
    const rows = r.data?.payload || [];
    list.value = append ? [...list.value, ...rows] : rows;
    total.value = r.data?.meta?.count ?? rows.length;
    staleAt.value = r.fromCache ? r.at : null;
  } catch {
    if (!append) failed.value = true;
  } finally {
    loading.value = false;
    loadingMore.value = false;
  }
};

const loadCounts = async () => {
  try {
    const r = await fetchApprovalCounts();
    counts.value = r.data || {};
    // 不是审批人的成员没有「待我审批」，默认落到「我发起的」
    if (counts.value.approver_view === false && view.value === 'todo') {
      view.value = '';
      await load();
    }
  } catch {
    // 角标失败不影响列表
  }
};

const loadMore = () => {
  page.value += 1;
  load({ append: true });
};

const switchView = key => {
  if (view.value === key) return;
  view.value = key;
  load();
};

const refresh = () => Promise.all([load(), loadCounts()]);

onMounted(refresh);
onActivated(() => {
  if (!loading.value) refresh();
});
</script>

<template>
  <div class="flex flex-col h-full">
    <PageHeader title="审批" :subtitle="total ? `共 ${total} 单` : ''">
      <template #actions>
        <button
          type="button"
          aria-label="发起审批"
          class="grid rounded-full size-9 place-items-center text-n-iris-11 active:bg-n-alpha-1"
          @click="router.push({ name: 'approval-new' })"
        >
          <span class="size-5 i-lucide-plus" />
        </button>
      </template>

      <template #below>
        <div class="flex items-center gap-2 px-4 pb-3 overflow-x-auto [&::-webkit-scrollbar]:hidden">
          <button
            v-for="v in views"
            :key="v.key"
            type="button"
            class="flex items-center flex-none h-8 gap-1.5 px-3 text-sm leading-none rounded-full"
            :class="
              view === v.key
                ? 'bg-n-iris-9 text-white font-medium'
                : 'bg-n-alpha-1 text-n-slate-11'
            "
            @click="switchView(v.key)"
          >
            {{ v.label }}
            <span
              v-if="counts[v.badge]"
              class="px-1.5 text-[11px] rounded-full"
              :class="view === v.key ? 'bg-white/25' : 'bg-n-slate-4 text-n-slate-11'"
            >
              {{ counts[v.badge] }}
            </span>
          </button>
        </div>
      </template>
    </PageHeader>

    <div class="flex-1 min-h-0 px-4 pt-3 overflow-y-auto">
      <DataState
        :loading="loading"
        :failed="failed"
        :empty="!list.length"
        :stale-at="staleAt"
        empty-text="这里没有待处理的单子"
        @retry="load()"
      >
        <ul class="flex flex-col gap-2">
          <li v-for="a in list" :key="a.id">
            <button
              type="button"
              class="w-full p-3 text-left wt-card active:bg-n-alpha-1"
              @click="router.push({ name: 'approval-detail', params: { id: a.id } })"
            >
              <div class="flex items-start gap-2">
                <div class="flex-1 min-w-0">
                  <div class="text-sm font-medium truncate text-n-slate-12">
                    {{ a.title }}
                  </div>
                  <div class="mt-0.5 text-xs truncate text-n-slate-11">
                    {{ a.template_name }} · {{ a.applicant_name }}
                  </div>
                </div>
                <span
                  class="flex-none px-2 py-1 text-xs rounded-lg"
                  :class="STATUS_CLASS[a.status] || 'bg-n-alpha-1 text-n-slate-11'"
                >
                  {{ APPROVAL_STATUS_LABELS[a.status] || a.status }}
                </span>
              </div>
              <div class="mt-1.5 text-xs text-n-slate-10">
                {{ shortDateTime(a.submitted_at || a.created_at) }}
              </div>
            </button>
          </li>
        </ul>

        <button
          v-if="hasMore"
          type="button"
          class="w-full mt-3 wt-btn-ghost"
          :disabled="loadingMore"
          @click="loadMore"
        >
          {{ loadingMore ? '加载中…' : '加载更多' }}
        </button>
        <div class="h-4" />
      </DataState>
    </div>
  </div>
</template>
