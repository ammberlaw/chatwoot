<script setup>
/* global axios */
import { ref, reactive, computed, nextTick } from 'vue';
import { onClickOutside, useEventListener } from '@vueuse/core';
import { useMesRole } from 'dashboard/composables/useMesRole';

// 金蝶式产品档案选择器：多列表格下拉（商品编码 / 商品名称 / 规格型号）+ 顶部搜索。
// 弹层 Teleport 到 body + fixed 定位，在对话框/滚动容器里不被裁切。
// 选中回传完整产品对象供调用方回填料号/名称/规格/单位。
const props = defineProps({
  modelValue: { type: [String, Number], default: '' }, // 已选产品 id
  accountId: { type: [String, Number], required: true },
  displayText: { type: String, default: '' }, // 触发器显示文本（已选料号/名称）
  placeholder: { type: String, default: '选物料（可搜编码/名称/规格）' },
  triggerClass: { type: String, default: '' },
});
const emit = defineEmits(['update:modelValue', 'select']);

const POP_W = 640;

const open = ref(false);
const triggerEl = ref(null);
const popoverEl = ref(null);
const searchEl = ref(null);
const popStyle = ref({});
// 若在原生 <dialog>（showModal 顶层）内，弹层要 Teleport 进该 dialog 才不被顶层遮住；否则回退 body。
const teleportTarget = ref('body');

const q = ref('');
const rows = ref([]);
const loading = ref(false);

onClickOutside(triggerEl, () => { open.value = false; }, { ignore: [popoverEl] }); // prettier-ignore

const fetchRows = async (keyword = '') => {
  loading.value = true;
  try {
    const { data } = await axios.get(
      `/api/v1/accounts/${props.accountId}/mes/products`,
      { params: { q: keyword || undefined, per_page: 50, filter: 'active' } }
    );
    rows.value = data?.payload || data || [];
  } catch {
    rows.value = [];
  } finally {
    loading.value = false;
  }
};

let timer = null;
const onSearch = () => {
  clearTimeout(timer);
  timer = setTimeout(() => fetchRows(q.value.trim()), 300);
};

const positionPopover = () => {
  const el = triggerEl.value;
  if (!el) return;
  const r = el.getBoundingClientRect();
  const popH = popoverEl.value?.offsetHeight || 360;
  const below = r.bottom + 6;
  const top =
    below + popH > window.innerHeight && r.top - popH - 6 > 0
      ? r.top - popH - 6
      : below;
  // 弹层若在对话框内，限制在对话框边界内，避免比对话框宽而溢出错位；否则回退到视口。
  const dialog = el.closest('dialog');
  const b = dialog
    ? dialog.getBoundingClientRect()
    : { left: 8, right: window.innerWidth - 8 };
  const width = Math.min(POP_W, b.right - b.left - 16);
  let left = r.left;
  left = Math.max(b.left + 8, Math.min(left, b.right - width - 8));
  popStyle.value = {
    position: 'fixed',
    top: `${top}px`,
    left: `${left}px`,
    width: `${width}px`,
  };
};

// 页面滚动时跟着重新定位，而不是关掉。
//
// 原来是一滚就关：但聚焦搜索框本身就可能带动外层容器滚一下，于是下拉「开了就秒关」——
// 想往搜索框里粘贴编码根本来不及。现在改成重算位置；只有触发器被滚出可视区才关
// （那时下拉浮在半空没有意义）。弹层内部列表滚动照旧不处理。
const syncPopover = () => {
  if (!open.value) return;
  const r = triggerEl.value?.getBoundingClientRect();
  if (!r || r.bottom < 0 || r.top > window.innerHeight) {
    open.value = false;
    return;
  }
  positionPopover();
};

useEventListener(
  'scroll',
  e => {
    if (!open.value) return;
    const t = e.target;
    if (popoverEl.value && t instanceof Node && popoverEl.value.contains(t))
      return;
    syncPopover();
  },
  { capture: true, passive: true }
);
useEventListener('resize', syncPopover);

const close = () => {
  open.value = false;
};

// 触发器本身就是搜索框：聚焦/点击即展开（幂等，focus 和 click 会各触发一次）。
const openPopover = async () => {
  if (open.value) return;
  teleportTarget.value = triggerEl.value?.closest('dialog') || 'body';
  // 带着已选料号进搜索态，别清空：清空的话一点进来代码就"不见了"，
  // 录单的人以为白填了、再点一下又回来——看着像在乱跳。
  q.value = props.displayText || '';
  open.value = true;
  if (!rows.value.length) fetchRows('');
  await nextTick();
  positionPopover();
  // 全选：打字/粘贴直接替换已选的料号，不用先手动清空。
  searchEl.value?.select?.();
};

const onType = e => {
  q.value = e.target.value;
  if (!open.value) openPopover();
  onSearch();
};

const pick = p => {
  emit('update:modelValue', String(p.id));
  emit('select', p);
  open.value = false;
};

// 打完料号直接回车选中第一条——不用再挪手去点鼠标。
const pickFirst = () => {
  if (!open.value) {
    openPopover();
    return;
  }
  if (rows.value.length) pick(rows.value[0]);
};

// —— 就地新建产品：搜不到时不用跳去产品档案，直接在下拉里建（仅工程/PMC 有产品档案权限者可见）——
const { mesCan } = useMesRole();
const canCreate = computed(() => mesCan('product'));
const creating = ref(false);
const saving = ref(false);
const createError = ref('');
const draft = reactive({ sku: '', name: '', specification: '', unit: '' });

const startCreate = async () => {
  createError.value = '';
  // 把搜索词带进名称，省得重打
  Object.assign(draft, {
    sku: '',
    name: q.value.trim(),
    specification: '',
    unit: '',
  });
  creating.value = true;
  await nextTick();
  positionPopover();
};
const cancelCreate = async () => {
  creating.value = false;
  createError.value = '';
  await nextTick();
  positionPopover();
};
const submitCreate = async () => {
  if (!draft.sku.trim() || !draft.name.trim() || saving.value) return;
  saving.value = true;
  createError.value = '';
  try {
    const { data } = await axios.post(
      `/api/v1/accounts/${props.accountId}/mes/products`,
      {
        product: {
          sku: draft.sku.trim(),
          name: draft.name.trim(),
          specification: draft.specification.trim() || undefined,
          unit: draft.unit.trim() || undefined,
          is_active: true,
        },
      }
    );
    creating.value = false;
    pick({ ...data, on_hand: 0 }); // 新建即选用并回填料号/名称/规格/单位
  } catch (e) {
    createError.value =
      e?.response?.data?.error || '创建失败（商品编码可能已存在）';
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <div :class="triggerClass || 'w-full'">
    <!-- 触发器用真 <input> 而不是 <button>：浏览器只给可编辑元素「复制/粘贴」右键菜单，
         也只往可编辑元素粘贴。原来是按钮，所以 Cmd/Ctrl+V 没地方落、右键菜单是空的，
         只能用鼠标一项项点。现在合上时显示已选料号，聚焦即变搜索框。 -->
    <div
      ref="triggerEl"
      class="flex items-center w-full h-full gap-2 pl-3 pr-2.5 py-2 text-sm rounded-lg outline outline-1 outline-n-weak bg-n-solid-1 hover:outline-n-brand focus-within:outline-n-brand"
    >
      <input
        ref="searchEl"
        type="text"
        class="flex-1 min-w-0 p-0 mb-0 text-sm bg-transparent border-0 rounded-none outline-none reset-base text-n-slate-12 placeholder:text-n-slate-9"
        :value="open ? q : displayText"
        :placeholder="placeholder"
        :title="displayText || placeholder"
        @focus="openPopover"
        @click="openPopover"
        @input="onType"
        @keydown.enter.prevent="pickFirst"
        @keydown.esc.prevent="close"
      />
      <span class="text-n-slate-10 i-lucide-chevron-down size-4 shrink-0" />
    </div>

    <teleport :to="teleportTarget">
      <transition
        enter-active-class="transition duration-150 ease-out"
        enter-from-class="opacity-0 scale-95 -translate-y-1"
        enter-to-class="opacity-100 scale-100 translate-y-0"
        leave-active-class="transition duration-100 ease-in"
        leave-from-class="opacity-100 scale-100"
        leave-to-class="opacity-0 scale-95"
      >
        <div
          v-if="open"
          ref="popoverEl"
          data-glass-popover
          :style="popStyle"
          class="z-[9999] flex flex-col origin-top overflow-hidden border shadow-xl rounded-2xl border-white/50 bg-n-solid-1/80 backdrop-blur-2xl backdrop-saturate-150 shadow-n-iris-9/15"
        >
          <!-- 就地新建产品（仅有产品档案权限者可见）：搜不到就直接建，不用跳出去 -->
          <div v-if="canCreate" class="border-b border-n-weak">
            <button
              v-if="!creating"
              type="button"
              class="flex items-center w-full gap-1.5 px-3 py-2 text-sm text-left text-n-iris-11 hover:bg-n-iris-3/50"
              @click="startCreate"
            >
              <span class="i-lucide-plus size-4" />
              找不到？新建产品
            </button>
            <div v-else class="flex flex-col gap-2 p-2">
              <div class="grid grid-cols-4 gap-2">
                <input
                  v-model="draft.sku"
                  class="h-9 px-2 text-sm border rounded-lg reset-base mb-0 border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-n-brand"
                  placeholder="商品编码 *"
                />
                <input
                  v-model="draft.name"
                  class="h-9 px-2 text-sm border rounded-lg reset-base mb-0 border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-n-brand"
                  placeholder="商品名称 *"
                />
                <input
                  v-model="draft.specification"
                  class="h-9 px-2 text-sm border rounded-lg reset-base mb-0 border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-n-brand"
                  placeholder="规格型号"
                />
                <input
                  v-model="draft.unit"
                  class="h-9 px-2 text-sm border rounded-lg reset-base mb-0 border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-n-brand"
                  placeholder="单位"
                />
              </div>
              <p v-if="createError" class="text-xs text-n-ruby-11">
                {{ createError }}
              </p>
              <div class="flex justify-end gap-2">
                <button
                  type="button"
                  class="h-8 px-3 text-sm rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
                  @click="cancelCreate"
                >
                  取消
                </button>
                <button
                  type="button"
                  class="h-8 px-4 text-sm font-medium text-white rounded-lg bg-n-iris-9 hover:bg-n-iris-10 disabled:opacity-50"
                  :disabled="saving || !draft.sku.trim() || !draft.name.trim()"
                  @click="submitCreate"
                >
                  {{ saving ? '创建中…' : '创建并选用' }}
                </button>
              </div>
            </div>
          </div>

          <!-- 表头 -->
          <div
            class="grid grid-cols-[8.5rem_7.5rem_1fr] gap-2 px-3 py-1.5 text-xs font-medium border-b text-n-slate-11 border-n-weak bg-n-alpha-1"
          >
            <span>商品编码</span>
            <span>商品名称</span>
            <span>规格型号</span>
          </div>

          <!-- 行 -->
          <div class="overflow-y-auto max-h-72">
            <div
              v-if="loading"
              class="px-3 py-6 text-sm text-center text-n-slate-10"
            >
              加载中…
            </div>
            <div
              v-else-if="!rows.length"
              class="px-3 py-6 text-sm text-center text-n-slate-10"
            >
              无匹配物料，换个关键词试试
            </div>
            <template v-else>
              <button
                v-for="p in rows"
                :key="p.id"
                type="button"
                class="grid w-full grid-cols-[8.5rem_7.5rem_1fr] gap-2 px-3 py-2 text-sm text-left border-b border-n-weak/60 hover:bg-n-alpha-2"
                :class="
                  String(p.id) === String(modelValue)
                    ? 'bg-n-iris-3/60 text-n-iris-12'
                    : 'text-n-slate-12'
                "
                @click="pick(p)"
              >
                <span class="font-medium truncate">{{ p.sku || '—' }}</span>
                <span class="truncate">{{ p.name || '—' }}</span>
                <span class="text-n-slate-11">{{
                  p.specification || '—'
                }}</span>
              </button>
            </template>
          </div>
        </div>
      </transition>
    </teleport>
  </div>
</template>
