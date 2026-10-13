<script setup>
// 表头筛选：点列头的小箭头，填个关键字（或选个值）就筛，服务端按这一列过滤。
//
// 筛选在服务端做：列表是分页的，只筛当前这 50 行等于骗人——筛完说「没有」，
// 翻到第二页它又在那儿。
//
// 两种列：
//   text —— 一个输入框 + 重置/确定，按「包含」筛。原来给了八种条件
//            （包含/不包含/等于/以…开始…），实际没人用，反而把浮层撑得老高。
//   enum —— 取值固定的列（结算/状态），直接把值列出来点一下就筛。
//
// 浮层 teleport 进最近的 <dialog>（原生 dialog 在顶层，挂 body 会被盖住，
// 见 DatePicker 里同一套写法）。样式对齐 SelectCard 的紫玻璃卡片。
import { ref, computed, nextTick, onBeforeUnmount } from 'vue';

const props = defineProps({
  // { op, value }；op 为空＝这一列没筛
  modelValue: { type: Object, default: () => ({}) },
  // 'text' | 'enum'
  kind: { type: String, default: 'text' },
  // kind='enum' 时的候选：[{ value, label }]
  options: { type: Array, default: () => [] },
});
const emit = defineEmits(['update:modelValue', 'change']);

const isEnum = computed(() => props.kind === 'enum');
const active = computed(() => !!props.modelValue?.op);

const open = ref(false);
const triggerEl = ref(null);
const popEl = ref(null);
const popStyle = ref({});
const teleportTarget = ref('body');
const draft = ref('');

const position = () => {
  const r = triggerEl.value?.getBoundingClientRect();
  if (!r) return;
  const w = isEnum.value ? 224 : 320;
  const h = popEl.value?.offsetHeight || 160;
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

const inputEl = ref(null);

const toggle = async () => {
  if (open.value) {
    close();
    return;
  }
  draft.value = props.modelValue?.value ?? '';
  teleportTarget.value = triggerEl.value?.closest('dialog') || 'body';
  open.value = true;
  await nextTick();
  position();
  inputEl.value?.focus();
  // 表格是横向滚动的，列头跟着走，浮层得贴着它
  window.addEventListener('scroll', position, true);
  window.addEventListener('resize', position);
};

const commit = payload => {
  emit('update:modelValue', payload);
  emit('change', payload);
  close();
};

// 文本列：空关键字＝不筛（列头亮着却筛不出东西更费解）。
const apply = () => {
  const value = String(draft.value).trim();
  commit(value ? { op: 'contains', value } : {});
};
// 点开别处关闭：文本列把当前输入落实（没有「确定」按钮了），枚举列直接关。
const dismiss = () => (isEnum.value ? close() : apply());
// 枚举列：点哪个值就筛哪个；「全部」＝清掉这一列。
const pickEnum = value => commit(value === '' ? {} : { op: 'eq', value });

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
      <div v-if="open" class="fixed inset-0 z-[9998]" @click="dismiss" />
      <div
        v-if="open"
        ref="popEl"
        class="z-[9999] p-1.5 origin-top overflow-y-auto border shadow-xl max-h-72 rounded-2xl border-white/50 bg-n-solid-1/70 backdrop-blur-2xl backdrop-saturate-150 shadow-n-iris-9/15"
        :class="isEnum ? 'w-56' : 'w-80'"
        :style="popStyle"
        @click.stop
      >
        <ul v-if="isEnum">
          <li>
            <button
              type="button"
              class="flex items-center w-full gap-2 px-3 text-sm text-left transition-colors rounded-lg h-9"
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
              class="flex items-center w-full gap-2 px-3 text-sm text-left transition-colors rounded-lg h-9"
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

        <!-- 文本列：就一个搜索框。回车或点开别处即生效，清空再回车＝取消这一列的筛选。 -->
        <div v-else class="p-1">
          <input
            ref="inputEl"
            v-model="draft"
            type="text"
            placeholder="输入关键字后回车"
            class="w-full h-8 px-2 text-sm border rounded-lg outline-none reset-base border-n-weak bg-n-solid-1 text-n-slate-12"
            @keyup.enter="apply"
          />
        </div>
      </div>
    </teleport>
  </span>
</template>
