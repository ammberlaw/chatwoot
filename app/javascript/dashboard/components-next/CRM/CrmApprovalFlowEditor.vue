<script setup>
import { computed } from 'vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import CrmApplicantPicker from 'dashboard/components-next/CRM/CrmApplicantPicker.vue';
import {
  opsForVar,
  varMeta,
  onVarChange,
  blankApprover,
  blankBranch,
  blankCondition,
  blankCondRow,
  isDefaultBranch,
} from 'dashboard/helper/oaApprovalFlow';

// 审批流程编辑器。自己调用自己：条件分支里的「该情况审批人」又是一段流程，
// 里面还能再放条件分支（钉钉那样先按发起人分组、组内再按请假天数分）。
const props = defineProps({
  // 可用作条件判断的变量 [{ value, label, kind, options? }]
  vars: { type: Array, default: () => [] },
  agents: { type: Array, default: () => [] },
  departments: { type: Array, default: () => [] },
  // 嵌套层级：0=最外层。越深的层用紧凑样式，并到顶后不再给「加条件分支」。
  depth: { type: Number, default: 0 },
  // 列表底部是否自带「添加审批人 / 添加条件分支」（最外层的按钮在页面标题行上，不重复给）。
  showAdd: { type: Boolean, default: false },
});

const flow = defineModel({ type: Array, default: () => [] });

// 再深就看不清谁套谁了；两级（发起人分组→组内分条件）足够覆盖实际审批场景。
const MAX_DEPTH = 2;

const L = {
  condTitle: '条件分支',
  condHint:
    '按分支从上往下判断，命中第一个「条件全部满足」的分支就走它的审批人；都不满足走「其他情况」。例：发起人属于深圳外贸部 → 再按请假天数分。',
  branch: '分支',
  defaultBranch: '其他情况（默认）',
  addBranch: '加分支',
  addCond: '加条件',
  addStep: '添加审批人',
  addCondition: '添加条件分支',
  branchApprovers: '该情况审批人',
  condField: '条件字段',
  compare: '比较',
  condValue: '值',
  and: '且',
  deptLeader: '申请人部门主管',
  specificUser: '指定成员',
  pickMember: '选择成员…',
  pickDept: '选择部门…',
  pickOption: '选择…',
  number: '填数值',
};

const compact = computed(() => props.depth > 0);
const canNest = computed(() => props.depth < MAX_DEPTH);

const kindOf = name => varMeta(props.vars, name).kind;
const ops = name => opsForVar(props.vars, name);
const varOptions = name => varMeta(props.vars, name).options || [];

const addApprover = () => flow.value.push(blankApprover());
const addCondition = () => flow.value.push(blankCondition(props.vars));
const removeStep = i => flow.value.splice(i, 1);

// 新分支插到「其他情况」前面，保证兜底始终在最后。
const addBranch = step => {
  const i = step.branches.findIndex(isDefaultBranch);
  const branch = blankBranch(props.vars);
  if (i >= 0) step.branches.splice(i, 0, branch);
  else step.branches.push(branch);
};
const removeBranch = (step, i) => step.branches.splice(i, 1);
const addCondRow = branch => branch.conditions.push(blankCondRow(props.vars));
const removeCondRow = (branch, i) => branch.conditions.splice(i, 1);
const changeVar = cond => onVarChange(props.vars, cond);
</script>

<template>
  <div class="flex flex-col gap-2">
    <template v-for="(s, i) in flow" :key="s.seq">
      <!-- 条件分支节点 -->
      <div
        v-if="s.type === 'condition'"
        class="p-2 border rounded-lg border-n-iris-6 bg-n-iris-2/40"
      >
        <div class="flex items-center gap-2 mb-1">
          <span
            class="flex items-center justify-center rounded-full bg-n-iris-4 text-n-iris-11"
            :class="compact ? 'size-5 text-[10px]' : 'size-6 text-[11px]'"
          >
            {{ i + 1 }}
          </span>
          <span class="text-xs font-medium text-n-iris-11">
            {{ L.condTitle }}
          </span>
          <span class="flex-1" />
          <button
            class="text-xs text-n-iris-11 hover:underline"
            @click="addBranch(s)"
          >
            + {{ L.addBranch }}
          </button>
          <button
            class="text-n-slate-10 hover:text-n-ruby-11"
            @click="removeStep(i)"
          >
            <Icon icon="i-lucide-x" class="size-4" />
          </button>
        </div>
        <p v-if="!compact" class="mb-1.5 text-[11px] text-n-slate-10">
          {{ L.condHint }}
        </p>
        <div class="flex flex-col gap-1.5">
          <div
            v-for="(b, bi) in s.branches"
            :key="b.seq"
            class="p-2 border rounded-md bg-n-solid-1 border-n-weak"
          >
            <div class="flex items-center gap-2 mb-1">
              <span class="text-[11px] font-medium text-n-slate-11">
                {{
                  isDefaultBranch(b) ? L.defaultBranch : `${L.branch} ${bi + 1}`
                }}
              </span>
              <span class="flex-1" />
              <button
                v-if="s.branches.length > 1"
                class="text-n-slate-10 hover:text-n-ruby-11"
                @click="removeBranch(s, bi)"
              >
                <Icon icon="i-lucide-trash-2" class="size-3.5" />
              </button>
            </div>
            <!-- 条件行（默认分支无条件） -->
            <div v-if="!isDefaultBranch(b)" class="flex flex-col gap-1 mb-1.5">
              <div class="flex items-center gap-1 text-[11px] text-n-slate-10">
                <span class="w-5 shrink-0" />
                <span class="flex-1">{{ L.condField }}</span>
                <span class="w-14 shrink-0 text-center">{{ L.compare }}</span>
                <span class="flex-1">{{ L.condValue }}</span>
                <span class="w-5 shrink-0" />
              </div>
              <div
                v-for="(c, ci) in b.conditions"
                :key="c.seq"
                class="flex gap-1"
                :class="
                  kindOf(c.var) === 'applicant' ? 'items-start' : 'items-center'
                "
              >
                <span
                  class="w-5 shrink-0 text-[11px] text-center text-n-slate-9"
                  :class="kindOf(c.var) === 'applicant' ? 'mt-2' : ''"
                >
                  {{ ci > 0 ? L.and : '' }}
                </span>
                <select
                  v-model="c.var"
                  class="flex-1 min-w-0 h-8 px-2 text-xs border rounded reset-base border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none focus:ring-0"
                  @change="changeVar(c)"
                >
                  <option v-for="v in vars" :key="v.value" :value="v.value">
                    {{ v.label }}
                  </option>
                </select>
                <select
                  v-model="c.op"
                  class="w-14 shrink-0 h-8 px-1 text-xs text-center border rounded reset-base border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none focus:ring-0"
                >
                  <option
                    v-for="o in ops(c.var)"
                    :key="o.value"
                    :value="o.value"
                  >
                    {{ o.label }}
                  </option>
                </select>
                <CrmApplicantPicker
                  v-if="kindOf(c.var) === 'applicant'"
                  v-model="c.value"
                  :departments="departments"
                  :agents="agents"
                  class="flex-1 min-w-0"
                />
                <select
                  v-else-if="kindOf(c.var) === 'dept'"
                  v-model="c.value"
                  class="flex-1 min-w-0 h-8 px-2 text-xs border rounded reset-base border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none focus:ring-0"
                >
                  <option value="">{{ L.pickDept }}</option>
                  <option
                    v-for="d in departments"
                    :key="d.id"
                    :value="String(d.id)"
                  >
                    {{ d.name }}
                  </option>
                </select>
                <select
                  v-else-if="kindOf(c.var) === 'enum'"
                  v-model="c.value"
                  class="flex-1 min-w-0 h-8 px-2 text-xs border rounded reset-base border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none focus:ring-0"
                >
                  <option value="">{{ L.pickOption }}</option>
                  <option
                    v-for="opt in varOptions(c.var)"
                    :key="opt"
                    :value="opt"
                  >
                    {{ opt }}
                  </option>
                </select>
                <input
                  v-else
                  v-model="c.value"
                  type="number"
                  :placeholder="L.number"
                  class="flex-1 min-w-0 h-8 px-2 text-xs border rounded reset-base border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none focus:ring-0"
                />
                <button
                  class="w-5 shrink-0 text-n-slate-10 hover:text-n-ruby-11"
                  :class="[
                    b.conditions.length > 1 ? '' : 'invisible',
                    kindOf(c.var) === 'applicant' ? 'mt-2' : '',
                  ]"
                  @click="removeCondRow(b, ci)"
                >
                  <Icon icon="i-lucide-x" class="size-3.5" />
                </button>
              </div>
              <button
                class="self-start text-[11px] text-n-iris-11 hover:underline"
                @click="addCondRow(b)"
              >
                + {{ L.addCond }}
              </button>
            </div>
            <!-- 该分支的审批人：又是一段流程，里面还能再分条件 -->
            <div class="pl-2 border-l-2 border-n-iris-5">
              <div class="text-[11px] text-n-slate-10 mb-1">
                {{ L.branchApprovers }}
              </div>
              <CrmApprovalFlowEditor
                v-model="b.flow"
                :vars="vars"
                :agents="agents"
                :departments="departments"
                :depth="depth + 1"
                show-add
              />
            </div>
          </div>
        </div>
      </div>
      <!-- 普通审批人步骤 -->
      <div
        v-else
        class="flex items-center"
        :class="
          compact ? 'gap-1.5' : 'gap-2 p-2 border rounded-lg border-n-weak'
        "
      >
        <span
          class="flex items-center justify-center rounded-full text-n-iris-11"
          :class="
            compact
              ? 'size-5 bg-n-iris-3 text-[10px]'
              : 'size-6 bg-n-iris-4 text-[11px]'
          "
        >
          {{ i + 1 }}
        </span>
        <!-- 全局 SCSS 给 select 撑满宽度，这里不钉死宽度的话，选了「指定成员」后
             成员下拉会被挤成一条缝，看不清选的是谁。 -->
        <select
          v-model="s.type"
          class="w-32 shrink-0 h-8 px-2 text-xs border rounded reset-base border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none focus:ring-0"
        >
          <option value="dept_leader">{{ L.deptLeader }}</option>
          <option value="user">{{ L.specificUser }}</option>
        </select>
        <select
          v-if="s.type === 'user'"
          v-model="s.userId"
          class="flex-1 min-w-0 h-8 px-2 text-xs border rounded reset-base border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none focus:ring-0"
        >
          <option value="">{{ L.pickMember }}</option>
          <option v-for="a in agents" :key="a.id" :value="String(a.id)">
            {{ a.name }}
          </option>
        </select>
        <span v-else class="flex-1" />
        <button
          v-if="!compact || flow.length > 1"
          class="text-n-slate-10 hover:text-n-ruby-11"
          @click="removeStep(i)"
        >
          <Icon icon="i-lucide-x" :class="compact ? 'size-3.5' : 'size-4'" />
        </button>
      </div>
    </template>
    <div v-if="showAdd" class="flex items-center gap-3">
      <button
        class="text-[11px] text-n-iris-11 hover:underline"
        @click="addApprover"
      >
        + {{ L.addStep }}
      </button>
      <button
        v-if="canNest"
        class="inline-flex items-center gap-1 text-[11px] text-n-iris-11 hover:underline"
        @click="addCondition"
      >
        <Icon icon="i-lucide-git-branch" class="size-3" />
        {{ L.addCondition }}
      </button>
    </div>
  </div>
</template>
