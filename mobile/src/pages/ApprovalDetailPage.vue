<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import PageHeader from '@/components/PageHeader.vue';
import DataState from '@/components/DataState.vue';
import AppSheet from '@/components/AppSheet.vue';
import FormField from '@/components/FormField.vue';
import ApprovalFormFields from '@/components/ApprovalFormFields.vue';
import { fetchApproval, actOnApproval, updateApprovalRequest } from '@/api/crm';
import { APPROVAL_STATUS_LABELS } from '@/constants/crm';
import { shortDateTime } from '@/utils/format';

defineOptions({ name: 'ApprovalDetailPage' });

const STATUS_CLASS = {
  pending: 'bg-[color:var(--pb-brand-soft)] text-[color:var(--pb-ink)]',
  approved: 'bg-[color:var(--pb-ink)] text-[color:var(--pb-on-ink)]',
  rejected: 'bg-[#C4383C]/10 text-[#C4383C]',
  canceled: 'bg-[color:var(--pb-fill)] text-[color:var(--pb-ink-2)]',
};
const STEP_ICON = {
  approved: { icon: 'i-lucide-check', cls: 'bg-[color:var(--pb-ink)] text-[color:var(--pb-on-ink)]' },
  rejected: { icon: 'i-lucide-x', cls: 'bg-[#C4383C]/10 text-[#C4383C]' },
  pending: { icon: 'i-lucide-clock', cls: 'bg-[color:var(--pb-fill)] text-[color:var(--pb-ink-3)]' },
};

const route = useRoute();

const req = ref(null);
const loading = ref(true);
const failed = ref(false);
const staleAt = ref(null);

// 弹层同时服务同意/驳回/撤回三种动作，只是文案与接口名不同
const sheet = ref({ open: false, action: '', title: '', comment: '', error: '', saving: false });

// form_fields 给出字段顺序与中文名，form_data 只有裸 key
const formRows = computed(() =>
  (req.value?.form_fields || []).map(f => {
    const v = req.value.form_data?.[f.key];
    return {
      key: f.key,
      label: f.label,
      value:
        v == null || v === ''
          ? '—'
          : f.type === 'datetime'
            ? String(v).replace('T', ' ')
            : String(v),
    };
  })
);

const load = async () => {
  loading.value = true;
  failed.value = false;
  try {
    const r = await fetchApproval(route.params.id);
    req.value = r.data || null;
    staleAt.value = r.fromCache ? r.at : null;
  } catch {
    failed.value = true;
  } finally {
    loading.value = false;
  }
};

const openSheet = (action, title) => {
  sheet.value = { open: true, action, title, comment: '', error: '', saving: false };
};

const confirm = async () => {
  // 驳回必须说明理由，否则申请人不知道该改什么
  if (sheet.value.action === 'reject' && !sheet.value.comment.trim()) {
    sheet.value.error = '请填写驳回理由';
    return;
  }
  sheet.value.saving = true;
  sheet.value.error = '';
  try {
    await actOnApproval(route.params.id, sheet.value.action, sheet.value.comment.trim());
    sheet.value.open = false;
    await load();
  } catch (e) {
    sheet.value.error =
      e.response?.data?.error || e.response?.data?.message || '操作失败，请重试';
  } finally {
    sheet.value.saving = false;
  }
};

// 改单条件与后端 editable_by_applicant? 一致：自己发起、审批中、且还没有人同意/驳回
const editable = computed(
  () =>
    !!req.value?.is_applicant &&
    req.value?.status === 'pending' &&
    (req.value?.steps || []).every(s => s.status === 'pending')
);

const editOpen = ref(false);
const editValues = ref({});
const editTitle = ref('');
const editSaving = ref(false);
const editError = ref('');

const openEdit = () => {
  editValues.value = Object.fromEntries(
    (req.value.form_fields || []).map(f => [f.key, req.value.form_data?.[f.key] ?? ''])
  );
  editTitle.value = req.value.title || '';
  editError.value = '';
  editOpen.value = true;
};

const saveEdit = async () => {
  const missing = (req.value.form_fields || []).find(
    f => f.required && !String(editValues.value[f.key] ?? '').trim()
  );
  if (missing) {
    editError.value = `请填写「${missing.label}」`;
    return;
  }
  editSaving.value = true;
  editError.value = '';
  try {
    await updateApprovalRequest(route.params.id, {
      title: editTitle.value.trim() || undefined,
      department_id: req.value.department_id || undefined,
      form_data: editValues.value,
    });
    editOpen.value = false;
    await load();
  } catch (e) {
    editError.value =
      e.response?.data?.error || e.response?.data?.message || '保存失败，请重试';
  } finally {
    editSaving.value = false;
  }
};

const kb = size =>
  size >= 1048576 ? `${(size / 1048576).toFixed(1)} MB` : `${Math.round(size / 1024)} KB`;

onMounted(load);
</script>

<template>
  <div class="flex flex-col h-full">
    <PageHeader back :title="req?.template_name || '审批'">
      <template v-if="editable" #actions>
        <button
          type="button"
          aria-label="修改单据"
          class="grid rounded-full size-9 place-items-center text-[color:var(--pb-accent)] active:bg-[color:var(--pb-fill)]"
          @click="openEdit"
        >
          <span class="size-5 i-lucide-pencil" />
        </button>
      </template>
    </PageHeader>

    <div class="flex-1 min-h-0 px-4 pt-3 overflow-y-auto">
      <DataState
        :loading="loading"
        :failed="failed"
        :empty="!req"
        :stale-at="staleAt"
        empty-text="审批单不存在或无权查看"
        @retry="load"
      >
        <div class="flex items-start gap-3">
          <h1 class="flex-1 text-base font-semibold leading-snug text-[color:var(--pb-ink)]">
            {{ req.title }}
          </h1>
          <span
            class="flex-none px-2 py-1 text-xs rounded-lg"
            :class="STATUS_CLASS[req.status] || 'bg-[color:var(--pb-fill)] text-[color:var(--pb-ink-2)]'"
          >
            {{ APPROVAL_STATUS_LABELS[req.status] || req.status }}
          </span>
        </div>
        <p class="mt-1 text-xs text-[color:var(--pb-ink-3)]">
          {{ req.applicant_name }}
          <template v-if="req.department_name"> · {{ req.department_name }}</template>
          · {{ shortDateTime(req.submitted_at || req.created_at) }}
        </p>

        <!-- 表单内容 -->
        <div v-if="formRows.length" class="mt-3 overflow-hidden wt-card">
          <div
            v-for="row in formRows"
            :key="row.key"
            class="flex items-start gap-3 px-3 py-2.5 border-b last:border-b-0 border-[color:var(--pb-sep)]"
          >
            <span class="flex-none w-20 text-xs text-[color:var(--pb-ink-3)]">{{ row.label }}</span>
            <span class="flex-1 text-sm break-words whitespace-pre-line text-[color:var(--pb-ink)]">
              {{ row.value }}
            </span>
          </div>
        </div>

        <!-- 附件 -->
        <ul v-if="req.files?.length" class="flex flex-col gap-2 mt-3">
          <li v-for="f in req.files" :key="f.id">
            <a
              :href="f.url"
              target="_blank"
              rel="noopener"
              class="flex items-center gap-3 p-3 wt-card active:bg-[color:var(--pb-fill)]"
            >
              <span class="flex-none size-4 text-[color:var(--pb-ink-3)] i-lucide-paperclip" />
              <span class="flex-1 text-sm truncate text-[color:var(--pb-accent)]">{{ f.filename }}</span>
              <span class="flex-none text-xs text-[color:var(--pb-ink-3)]">{{ kb(f.byte_size) }}</span>
            </a>
          </li>
        </ul>

        <!-- 审批流 -->
        <h2 class="mt-4 mb-2 text-xs font-semibold tracking-wide text-[color:var(--pb-ink-3)]">审批流程</h2>
        <ul class="overflow-hidden wt-card">
          <li
            v-for="s in req.steps"
            :key="s.id"
            class="flex items-start gap-3 px-3 py-3 border-b last:border-b-0 border-[color:var(--pb-sep)]"
          >
            <span
              class="grid flex-none rounded-full size-6 place-items-center"
              :class="(STEP_ICON[s.status] || STEP_ICON.pending).cls"
            >
              <span class="size-3.5" :class="(STEP_ICON[s.status] || STEP_ICON.pending).icon" />
            </span>
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2">
                <span class="text-sm font-medium truncate text-[color:var(--pb-ink)]">
                  {{ s.approver_name || '未指定' }}
                </span>
                <span v-if="s.is_current" class="text-xs text-[color:var(--pb-brand-ink)]">审批中</span>
              </div>
              <p v-if="s.comment" class="mt-0.5 text-sm break-words text-[color:var(--pb-ink-2)]">
                {{ s.comment }}
              </p>
              <p v-if="s.acted_at" class="mt-0.5 text-xs text-[color:var(--pb-ink-3)]">
                {{ shortDateTime(s.acted_at) }}
              </p>
            </div>
          </li>
        </ul>

        <p v-if="req.cc_names?.length" class="mt-3 text-xs text-[color:var(--pb-ink-3)]">
          抄送 {{ req.cc_names.join('、') }}
        </p>

        <div class="h-6" />
      </DataState>
    </div>

    <!-- 待我审批时露同意/驳回；自己发起且还在审批中时露撤回 -->
    <div
      v-if="req?.can_act || (req?.is_applicant && req?.status === 'pending')"
      class="flex flex-none gap-2 px-4 pt-2 pb-2 border-t border-[color:var(--pb-sep)] bg-n-background pb-safeBottom"
    >
      <template v-if="req.can_act">
        <button
          type="button"
          class="flex-1 wt-btn text-[#C4383C] bg-[#C4383C]/10 active:bg-[#C4383C]/15"
          @click="openSheet('reject', '驳回审批')"
        >
          驳回
        </button>
        <button
          type="button"
          class="flex-1 wt-btn-primary"
          @click="openSheet('approve', '同意审批')"
        >
          同意
        </button>
      </template>
      <button
        v-else
        type="button"
        class="w-full wt-btn-ghost"
        @click="openSheet('cancel', '撤回审批')"
      >
        撤回
      </button>
    </div>

    <AppSheet :open="editOpen" title="修改单据" @close="editOpen = false">
      <div class="flex flex-col gap-4">
        <FormField label="标题">
          <input v-model="editTitle" type="text" class="wt-field" />
        </FormField>
        <ApprovalFormFields :fields="req?.form_fields || []" :model-value="editValues" />
        <p v-if="editError" class="text-sm text-[#C4383C]">{{ editError }}</p>
      </div>
      <template #footer>
        <button
          type="button"
          class="w-full wt-btn-primary"
          :disabled="editSaving"
          @click="saveEdit"
        >
          {{ editSaving ? '保存中…' : '保存' }}
        </button>
      </template>
    </AppSheet>

    <AppSheet :open="sheet.open" :title="sheet.title" @close="sheet.open = false">
      <FormField label="意见" :required="sheet.action === 'reject'">
        <textarea
          v-model="sheet.comment"
          rows="4"
          :placeholder="sheet.action === 'reject' ? '说明驳回原因' : '选填'"
          class="wt-field"
        />
      </FormField>
      <p v-if="sheet.error" class="mt-3 text-sm text-[#C4383C]">{{ sheet.error }}</p>
      <template #footer>
        <button
          type="button"
          class="w-full wt-btn-primary"
          :disabled="sheet.saving"
          @click="confirm"
        >
          {{ sheet.saving ? '提交中…' : '确认' }}
        </button>
      </template>
    </AppSheet>
  </div>
</template>
