<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import PageHeader from '@/components/PageHeader.vue';
import DataState from '@/components/DataState.vue';
import FormField from '@/components/FormField.vue';
import ApprovalFormFields from '@/components/ApprovalFormFields.vue';
import AttachmentField from '@/components/AttachmentField.vue';
import {
  fetchApprovalTemplates,
  fetchMyDepartments,
  createApprovalRequest,
  createApprovalRequestWithFiles,
} from '@/api/crm';

defineOptions({ name: 'ApprovalNewPage' });

const router = useRouter();

const templates = ref([]);
const departments = ref([]);
const picked = ref(null); // 选中的模板，非空即进入填单态
const values = ref({});
const deptId = ref('');
const files = ref([]);
const loading = ref(true);
const failed = ref(false);
const saving = ref(false);
const error = ref('');

// 审批链含「部门主管」才需要指定部门，否则这个字段对用户是噪音
const needsDept = computed(() =>
  (picked.value?.flow || []).some(s => s.type === 'dept_leader')
);

const load = async () => {
  loading.value = true;
  failed.value = false;
  const [t, d] = await Promise.allSettled([
    fetchApprovalTemplates(),
    fetchMyDepartments(),
  ]);
  if (t.status === 'fulfilled') templates.value = t.value.data?.payload || [];
  else failed.value = true;
  if (d.status === 'fulfilled') departments.value = d.value.data?.payload || [];
  loading.value = false;
};

const pick = tpl => {
  picked.value = tpl;
  values.value = Object.fromEntries((tpl.form_fields || []).map(f => [f.key, '']));
  deptId.value = departments.value[0] ? String(departments.value[0].department_id) : '';
  files.value = [];
  error.value = '';
};

const submit = async () => {
  const missing = (picked.value.form_fields || []).find(
    f => f.required && !String(values.value[f.key] ?? '').trim()
  );
  if (missing) {
    error.value = `请填写「${missing.label}」`;
    return;
  }
  saving.value = true;
  error.value = '';
  try {
    const payload = {
      template_id: picked.value.id,
      form_data: values.value,
      department_id: needsDept.value ? deptId.value || null : null,
    };
    const { data } = files.value.length
      ? await createApprovalRequestWithFiles(payload, files.value)
      : await createApprovalRequest(payload);
    // 提完直接看单据状态，返回时回到审批列表
    router.replace(
      data?.id
        ? { name: 'approval-detail', params: { id: data.id } }
        : { name: 'approvals' }
    );
  } catch (e) {
    // 「审批流未找到有效审批人」等配置问题走 422 + error，要原样透出
    error.value =
      e.response?.data?.error ||
      e.response?.data?.message ||
      (e.response ? `提交失败（HTTP ${e.response.status}）` : '网络不可用，提交失败');
  } finally {
    saving.value = false;
  }
};

onMounted(load);
</script>

<template>
  <div class="flex flex-col h-full">
    <PageHeader back :title="picked ? picked.name : '发起审批'">
      <template v-if="picked" #actions>
        <button
          type="button"
          class="px-2 text-sm h-9 text-[color:var(--pb-accent)] active:bg-[color:var(--pb-fill)] rounded-lg"
          @click="picked = null"
        >
          换模板
        </button>
      </template>
    </PageHeader>

    <div class="flex-1 min-h-0 px-4 pt-4 overflow-y-auto">
      <!-- 选模板 -->
      <DataState
        v-if="!picked"
        :loading="loading"
        :failed="failed"
        :empty="!templates.length"
        empty-text="管理员还没有配置审批模板"
        @retry="load"
      >
        <ul class="grid grid-cols-2 gap-3">
          <li v-for="t in templates" :key="t.id">
            <button
              type="button"
              class="flex flex-col items-start w-full h-full p-4 text-left wt-glass wt-press"
              @click="pick(t)"
            >
              <div class="flex items-start w-full">
                <span
                  class="flex-none size-7 text-[color:var(--pb-ink)]"
                  :class="t.icon || 'i-lucide-file-check'"
                />
                <span class="flex-1" />
                <span class="flex-none mt-1 size-4 text-[color:var(--pb-ink-3)] i-lucide-chevron-right" />
              </div>
              <span
                class="mt-3 text-[15px] font-semibold leading-5 text-[color:var(--pb-ink)]"
              >
                {{ t.name }}
              </span>
              <span v-if="t.description" class="mt-0.5 text-[12px] leading-4 text-[color:var(--pb-ink-3)]">
                {{ t.description }}
              </span>
            </button>
          </li>
        </ul>
      </DataState>

      <!-- 填单 -->
      <div v-else class="flex flex-col gap-4">
        <FormField v-if="needsDept && departments.length > 1" label="所在部门" required>
          <select v-model="deptId" class="wt-field">
            <option
              v-for="d in departments"
              :key="d.department_id"
              :value="String(d.department_id)"
            >
              {{ d.department_name }}
            </option>
          </select>
        </FormField>

        <ApprovalFormFields :fields="picked.form_fields" :model-value="values" />

        <AttachmentField v-model="files" />

        <p v-if="error" class="text-sm text-[#C4383C]">{{ error }}</p>
        <div class="h-2" />
      </div>
    </div>

    <div
      v-if="picked"
      class="flex-none px-4 pt-2 pb-2 border-t border-[color:var(--pb-sep)] bg-n-background pb-safeBottom"
    >
      <button type="button" class="w-full wt-btn-primary" :disabled="saving" @click="submit">
        {{ saving ? '提交中…' : '提交' }}
      </button>
    </div>
  </div>
</template>
