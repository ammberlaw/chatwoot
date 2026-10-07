<script setup>
/* global axios */
import { computed, reactive, ref, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import CrmMemberAPI from 'dashboard/api/crm/members';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';

defineProps({
  isLoading: { type: Boolean, default: false },
});
const emit = defineEmits(['create', 'update']);
// 业绩保底目标与晋升体系（硬编码档位表）。选档位自动带出：月薪(底薪)/绩效占比/月度业绩底线。
// salary、baseline 单位为「元」；ratio 为绩效占比百分数。
// WITHIN_12M = 入职12个月内（P3 六档）；OVER_12M = 入职满12个月（P4~P9）。
const PAY_GRADE_STAGES = [
  {
    key: 'WITHIN_12M',
    grades: [
      {
        code: 'P3_17',
        label: '季度GMV≥17万 · 底薪5000 · 10% · 保底5万',
        salary: 5000,
        ratio: 10,
        baseline: 50000,
      },
      {
        code: 'P3_20',
        label: '≥20万 · 底薪6000 · 10% · 保底6.67万',
        salary: 6000,
        ratio: 10,
        baseline: 66700,
      },
      {
        code: 'P3_32',
        label: '≥32万 · 底薪7000 · 10% · 保底10.67万',
        salary: 7000,
        ratio: 10,
        baseline: 106700,
      },
      {
        code: 'P3_35',
        label: '≥35万 · 底薪8000 · 10% · 保底11.67万',
        salary: 8000,
        ratio: 10,
        baseline: 116700,
      },
      {
        code: 'P3_45',
        label: '≥45万 · 底薪9000 · 15% · 保底15万',
        salary: 9000,
        ratio: 15,
        baseline: 150000,
      },
      {
        code: 'P3_65',
        label: '≥65万 · 底薪10000 · 15% · 保底21.67万',
        salary: 10000,
        ratio: 15,
        baseline: 216700,
      },
    ],
  },
  {
    key: 'OVER_12M',
    grades: [
      {
        code: 'P4',
        label: 'P4 · ≥100万 · 底薪7000 · 10% · 保底30万',
        salary: 7000,
        ratio: 10,
        baseline: 300000,
      },
      {
        code: 'P5',
        label: 'P5 · ≥150万 · 底薪8000 · 10% · 保底45万',
        salary: 8000,
        ratio: 10,
        baseline: 450000,
      },
      {
        code: 'P6',
        label: 'P6 · ≥225万 · 底薪9000 · 15% · 保底65万',
        salary: 9000,
        ratio: 15,
        baseline: 650000,
      },
      {
        code: 'P7',
        label: 'P7 · ≥300万 · 底薪10000 · 15% · 保底85万',
        salary: 10000,
        ratio: 15,
        baseline: 850000,
      },
      {
        code: 'P8',
        label: 'P8 · ≥375万 · 底薪11000 · 20% · 保底110万',
        salary: 11000,
        ratio: 20,
        baseline: 1100000,
      },
      {
        code: 'P9',
        label: 'P9 · ≥500万 · 底薪12000 · 20% · 保底150万',
        salary: 12000,
        ratio: 20,
        baseline: 1500000,
      },
    ],
  },
];
const ALL_GRADES = PAY_GRADE_STAGES.flatMap(s => s.grades);

const { t } = useI18n();
const { accountId } = useAccount();
const dialogRef = ref(null);
// 有值=编辑该配置，null=新建。
const editingId = ref(null);
const members = ref([]);
// 原生 select → 紫玻璃 SelectCard 选项（含空值项「—」）。
const ownerOptions = computed(() => [
  { value: '', label: '—' },
  ...members.value.map(m => ({ value: m.user_id, label: m.name })),
]);
// user_id -> hire_date（用于按入职时长判断阶段，只显示对应档位）
const hireByUser = ref({});

const form = reactive({
  name: '',
  ownerId: '',
  payGrade: '',
  monthlySalary: '',
  performanceRatio: '10',
  baselineTarget: '',
  rankNote: '',
});

const isFormInvalid = computed(() => !form.name.trim());
const dialogTitle = computed(() =>
  editingId.value
    ? t('CRM.EMPLOYEE_COMPS.EDIT.TITLE')
    : t('CRM.EMPLOYEE_COMPS.CREATE.TITLE')
);

// 选定成员的阶段：入职满12个月=OVER_12M，未满=WITHIN_12M，未知=null（不过滤）。
const ownerStage = computed(() => {
  const hire = hireByUser.value[String(form.ownerId)];
  if (!hire) return null;
  const d = new Date(hire);
  if (Number.isNaN(d.getTime())) return null;
  const now = new Date();
  const months =
    (now.getFullYear() - d.getFullYear()) * 12 +
    (now.getMonth() - d.getMonth());
  return months >= 12 ? 'OVER_12M' : 'WITHIN_12M';
});

// 已知阶段则只显示该阶段档位；未知则两组都显示。
const visibleStages = computed(() =>
  ownerStage.value
    ? PAY_GRADE_STAGES.filter(s => s.key === ownerStage.value)
    : PAY_GRADE_STAGES
);

// 选档位 → 自动带出月薪(底薪)/绩效占比/月度业绩底线（仍可手动微调）。
const applyGrade = () => {
  const g = ALL_GRADES.find(x => x.code === form.payGrade);
  if (!g) return;
  form.monthlySalary = String(g.salary);
  form.performanceRatio = String(g.ratio);
  form.baselineTarget = String(g.baseline);
};

// 换人后档位若不在其阶段内，清掉选择（金额值保留，避免误清手填）。
watch(
  () => form.ownerId,
  () => {
    const stillVisible = visibleStages.value.some(s =>
      s.grades.some(g => g.code === form.payGrade)
    );
    if (form.payGrade && !stillVisible) form.payGrade = '';
  }
);

const resetForm = () => {
  form.name = '';
  form.ownerId = '';
  form.payGrade = '';
  form.monthlySalary = '';
  form.performanceRatio = '10';
  form.baselineTarget = '';
  form.rankNote = '';
};

const open = () => {
  editingId.value = null;
  resetForm();
  dialogRef.value?.open();
};

// 编辑已有配置：回填表单（金额由 micros 还原为元），档位仅作辅助不回填。
const openEdit = record => {
  editingId.value = record.id;
  form.name = record.name || '';
  form.ownerId = record.ownerId || '';
  form.payGrade = '';
  form.monthlySalary =
    record.monthlySalaryMicros != null
      ? String(record.monthlySalaryMicros / 1_000_000)
      : '';
  form.performanceRatio =
    record.performanceRatio != null ? String(record.performanceRatio) : '';
  form.baselineTarget =
    record.baselineTargetMicros != null
      ? String(record.baselineTargetMicros / 1_000_000)
      : '';
  form.rankNote = record.rankNote || '';
  dialogRef.value?.open();
};

const onSuccess = () => {
  resetForm();
  dialogRef.value?.close();
};

const toMicros = v => (v ? Math.round(parseFloat(v) * 1_000_000) : null);

const handleConfirm = () => {
  if (isFormInvalid.value) return;
  const payload = {
    name: form.name.trim(),
    ownerId: form.ownerId || null,
    monthlySalaryMicros: toMicros(form.monthlySalary),
    performanceRatio: form.performanceRatio
      ? Number(form.performanceRatio)
      : null,
    baselineTargetMicros: toMicros(form.baselineTarget),
    rankNote: form.rankNote.trim() || null,
  };
  if (editingId.value) {
    emit('update', { id: editingId.value, ...payload });
  } else {
    emit('create', payload);
  }
};

onMounted(async () => {
  try {
    // 只取在职成员：离职停用的人不该再出现在选人下拉里（后端按 deactivated_at 过滤）。
    const { data } = await CrmMemberAPI.get({ active: true });
    members.value = data.payload || [];
  } catch {
    members.value = [];
  }
  // 拉员工档案的入职日期（同一敏感会话已解锁），用于按阶段过滤档位。
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${accountId.value}/crm/employees`
    );
    hireByUser.value = (data.payload || []).reduce((map, e) => {
      if (e.user_id && e.hire_date) map[String(e.user_id)] = e.hire_date;
      return map;
    }, {});
  } catch {
    hireByUser.value = {};
  }
});

defineExpose({ dialogRef, onSuccess, open, openEdit });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="2xl"
    overflow-y-auto
    :title="dialogTitle"
    :is-loading="isLoading"
    @confirm="handleConfirm"
    @close="resetForm"
  >
    <div class="flex flex-col gap-4">
      <Input
        v-model="form.name"
        :label="t('CRM.EMPLOYEE_COMPS.FORM.NAME')"
        autofocus
      />
      <label class="flex flex-col gap-1 text-sm text-n-slate-12">
        {{ t('CRM.EMPLOYEE_COMPS.FORM.MEMBER') }}
        <SelectCard v-model="form.ownerId" :options="ownerOptions" block />
      </label>
      <label class="flex flex-col gap-1 text-sm text-n-slate-12">
        {{ t('CRM.EMPLOYEE_COMPS.FORM.PAY_GRADE') }}
        <select
          v-model="form.payGrade"
          class="h-10 px-3 rounded-lg border border-n-weak bg-n-solid-1 text-n-slate-12"
          @change="applyGrade"
        >
          <option value="">
            {{ t('CRM.EMPLOYEE_COMPS.FORM.PAY_GRADE_PLACEHOLDER') }}
          </option>
          <optgroup
            v-for="stage in visibleStages"
            :key="stage.key"
            :label="t(`CRM.EMPLOYEE_COMPS.FORM.STAGE_${stage.key}`)"
          >
            <option v-for="g in stage.grades" :key="g.code" :value="g.code">
              {{ g.label }}
            </option>
          </optgroup>
        </select>
        <span class="text-xs text-n-slate-11">
          {{ t('CRM.EMPLOYEE_COMPS.FORM.PAY_GRADE_HINT') }}
        </span>
      </label>
      <div class="grid grid-cols-2 gap-4">
        <Input
          v-model="form.monthlySalary"
          type="number"
          :label="t('CRM.EMPLOYEE_COMPS.FORM.MONTHLY_SALARY')"
        />
        <Input
          v-model="form.performanceRatio"
          type="number"
          :label="t('CRM.EMPLOYEE_COMPS.FORM.PERF_RATIO')"
        />
      </div>
      <div class="grid grid-cols-2 gap-4">
        <Input
          v-model="form.baselineTarget"
          type="number"
          :label="t('CRM.EMPLOYEE_COMPS.FORM.BASELINE_TARGET')"
        />
        <Input
          v-model="form.rankNote"
          :label="t('CRM.EMPLOYEE_COMPS.FORM.RANK_NOTE')"
        />
      </div>
    </div>
  </Dialog>
</template>
