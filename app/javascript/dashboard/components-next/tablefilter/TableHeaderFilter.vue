<script setup>
// 表头漏斗筛选（对标金蝶）：点列头的漏斗，选条件 + 填值 → 服务端按这一列筛。
// 筛选在服务端做：列表是分页的，只筛当前这 50 行等于骗人——翻到第二页又出现了。
//
// 浮层 teleport 进最近的 <dialog>（原生 dialog 在顶层，挂 body 会被盖住，
// 见 DatePicker 里同一套写法）。
import { ref, computed, nextTick, onBeforeUnmount } from 'vue';

const props = defineProps({
  // { op, value }；op 为空＝这一列没筛
  modelValue: { type: Object, default: () => ({}) },
  // 'text' 文本列（八种条件）| 'enum' 取值固定的列（只给「等于/不等于/为空/不为空」+ 下拉）
  kind: { type: String, default: 'text' },
  // kind='enum' 时的候选：[{ value, label }]
  options: { type: Array, default: () => [] },
});
const emit = defineEmits(['update:modelValue', 'change']);

const TEXT_OPS = [
  { value: 'contains', label: '包含' },
  { value: 'not_contains', label: '不包含' },
  { value: 'eq', label: '等于' },
  { value: 'ne', label: '不等于' },
  { value: 'starts', label: '以……开始' },
  { value: 'ends', label: '以……结束' },
  { value: 'blank', label: '为空' },
  { value: 'present', label: '不为空' },
];
// 取值固定的列（结算、状态这些）不给条件：一共就两三个值，「等于/不等于/为空/不为空」
// 四选一再选值是绕远路——直接把值列出来，点一个就筛（用户 2026-10-13 反馈）。
const isEnum = computed(() => props.kind === 'enum');
const ops = TEXT_OPS;
// 「为空 / 不为空」不需要填值
const NEEDS_VALUE = op => op && !['blank', 'present'].includes(op);

const active = computed(() => !!props.modelValue?.op);
const open = ref(false);
const triggerEl = ref(null);
const popEl = ref(null);
const popStyle = ref({});
const teleportTarget = ref('body');
const draftOp = ref('contains');
const draftValue = ref('');

const position = () => {
  const r = triggerEl.value?.getBoundingClientRect();
  if (!r) return;
  const w = 224;
  const h = popEl.value?.offsetHeight || 300;
  const below = r.bottom + 6;
  const top =
    below + h > window.innerHeight && r.top - h - 6 > 0 ? r.top - h - 6 : below;
  const left = Math.max(8, Math.min(r.left, window.innerWidth - w - 8));
  popStyle.value = { position: 'fixed', top: `${top}px`, left: `${left}px` };
};

const close = () => {
  open.value = false;
  window.removeEventListener('scroll', position, true);
  window.removeEventListener('resize', position);
};

const toggle = async () => {
  if (open.value) {
    close();
    return;
  }
  draftOp.value = props.modelValue?.op || ops[0].value;
  draftValue.value = props.modelValue?.value ?? '';
  teleportTarget.value = triggerEl.value?.closest('dialog') || 'body';
  open.value = true;
  await nextTick();
  position();
  // 表格是横向滚动的，列头跟着走，浮层得贴着它
  window.addEventListener('scroll', position, true);
  window.addEventListener('resize', position);
};

const apply = () => {
  const next = NEEDS_VALUE(draftOp.value)
    ? { op: draftOp.value, value: String(draftValue.value).trim() }
    : { op: draftOp.value, value: '' };
  // 选了「包含」却没填值＝什么都没筛，当作清空，不然列头亮着漏斗却筛不出东西
  const payload = NEEDS_VALUE(next.op) && !next.value ? {} : next;
  emit('update:modelValue', payload);
  emit('change', payload);
  close();
};

const reset = () => {
  emit('update:modelValue', {});
  emit('change', {});
  close();
};

// 枚举列：点哪个值就按「等于」筛哪个；点「全部」＝清掉这一列的筛选。
const pickEnum = value => {
  const payload = value === '' ? {} : { op: 'eq', value };
  emit('update:modelValue', payload);
  emit('change', payload);
  close();
};

onBeforeUnmount(close);
</script>

<template>
  <span class="relative inline-flex">
    <button
      ref="triggerEl"
      type="button"
      class="inline-flex items-center justify-center rounded size-5 transition-colors hover:bg-n-alpha-2 hover:text-n-slate-12"
      :class="active ? 'text-n-iris-11' : 'text-n-slate-11'"
      :aria-label="active ? '已筛选，点击修改' : '筛选这一列'"
      @click.stop="toggle"
    >
      <span class="i-lucide-chevron-down size-4 shrink-0" />
    </button>

    <teleport :to="teleportTarget">
      <div v-if="open" class="fixed inset-0 z-10" @click="close" />
      <div
        v-if="open"
        ref="popEl"
        class="z-[9999] w-56 p-1.5 origin-top overflow-y-auto border shadow-xl max-h-72 rounded-2xl border-white/50 bg-n-solid-1/70 backdrop-blur-2xl backdrop-saturate-150 shadow-n-iris-9/15"
        :style="popStyle"
        @click.stop
      >
        <!-- 取值固定的列：直接列值，点一下就筛 -->
        <ul v-if="isEnum">
          <li>
            <button
              type="button"
              class="flex items-center justify-between w-full gap-2 px-3 text-sm text-left transition-colors rounded-lg h-9"
              :class="
                active
                  ? 'text-n-slate-11 hover:bg-n-iris-3'
                  : 'bg-n-iris-9 text-white font-medium shadow-sm shadow-n-iris-9/30'
              "
              @click="pickEnum('')"
            >
              <span class="whitespace-nowrap">全部</span>
            </button>
          </li>
          <li v-for="o in options" :key="String(o.value)">
            <button
              type="button"
              class="flex items-center justify-between w-full gap-2 px-3 text-sm text-left transition-colors rounded-lg h-9"
              :class="
                active && String(modelValue.value) === String(o.value)
                  ? 'bg-n-iris-9 text-white font-medium shadow-sm shadow-n-iris-9/30'
                  : 'text-n-slate-12 hover:bg-n-iris-3'
              "
              @click="pickEnum(String(o.value))"
            >
              <span class="whitespace-nowrap">{{ o.label }}</span>
            </button>
          </li>
        </ul>

        <ul v-else>
          <li v-for="op in ops" :key="op.value">
            <button
              type="button"
              class="flex items-center justify-between w-full gap-2 px-3 text-sm text-left transition-colors rounded-lg h-9"
              :class="
                draftOp === op.value
                  ? 'bg-n-iris-9 text-white font-medium shadow-sm shadow-n-iris-9/30'
                  : 'text-n-slate-12 hover:bg-n-iris-3'
              "
              @click="draftOp = op.value"
            >
              <span class="whitespace-nowrap">{{ op.label }}</span>
            </button>
          </li>
        </ul>

        <input
          v-if="!isEnum && NEEDS_VALUE(draftOp)"
          v-model="draftValue"
          type="text"
          class="reset-base w-full h-9 px-2 mt-2 text-sm border rounded border-n-weak bg-n-alpha-1 text-n-slate-12"
          @keyup.enter="apply"
        />

        <div v-if="!isEnum" class="flex items-center gap-2 mt-2">
          <button
            type="button"
            class="flex-1 h-8 text-sm rounded border border-n-weak text-n-slate-11 hover:bg-n-alpha-1"
            @click="reset"
          >
            重置
          </button>
          <button
            type="button"
            class="flex-1 h-8 text-sm text-white rounded bg-n-iris-9 hover:bg-n-iris-10"
            @click="apply"
          >
            确定
          </button>
        </div>
      </div>
    </teleport>
  </span>
</template>
