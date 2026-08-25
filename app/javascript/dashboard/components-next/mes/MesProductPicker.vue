<script setup>
/* global axios */
import { ref, computed, nextTick } from 'vue';
import { onClickOutside, useEventListener } from '@vueuse/core';

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
// 页面滚动时关闭（fixed 弹层会与触发器错位）；但弹层内部列表滚动不关。
useEventListener(
  'scroll',
  e => {
    if (!open.value) return;
    const t = e.target;
    if (popoverEl.value && t instanceof Node && popoverEl.value.contains(t))
      return;
    open.value = false;
  },
  { capture: true, passive: true }
);
useEventListener('resize', () => {
  if (open.value) open.value = false;
});

const hasValue = computed(() => !!props.displayText);

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
  const width = Math.min(POP_W, window.innerWidth - 16);
  let left = r.left;
  left = Math.max(8, Math.min(left, window.innerWidth - width - 8));
  popStyle.value = {
    position: 'fixed',
    top: `${top}px`,
    left: `${left}px`,
    width: `${width}px`,
  };
};

const toggle = async () => {
  if (open.value) {
    open.value = false;
    return;
  }
  teleportTarget.value = triggerEl.value?.closest('dialog') || 'body';
  open.value = true;
  if (!rows.value.length) fetchRows('');
  await nextTick();
  positionPopover();
  // preventScroll：聚焦搜索框时别让浏览器滚动页面，否则会触发上面的滚动监听把刚开的弹层关掉。
  searchEl.value?.focus({ preventScroll: true });
};

const pick = p => {
  emit('update:modelValue', String(p.id));
  emit('select', p);
  open.value = false;
};
</script>

<template>
  <div :class="triggerClass || 'w-full'">
    <button
      ref="triggerEl"
      type="button"
      class="flex items-center justify-between w-full h-full gap-2 pl-3 pr-2.5 py-2 text-sm text-left rounded-lg outline outline-1 outline-n-weak bg-n-solid-1 hover:outline-n-brand focus:outline-n-brand"
      @click="toggle"
    >
      <span
        class="truncate"
        :class="hasValue ? 'text-n-slate-12' : 'text-n-slate-9'"
      >
        {{ hasValue ? displayText : placeholder }}
      </span>
      <span class="text-n-slate-10 i-lucide-chevron-down size-4 shrink-0" />
    </button>

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
          <!-- 搜索 -->
          <div class="p-2 border-b border-n-weak">
            <div class="relative">
              <span
                class="absolute -translate-y-1/2 i-lucide-search left-2.5 top-1/2 size-4 text-n-slate-10"
              />
              <input
                ref="searchEl"
                v-model="q"
                class="w-full h-9 pl-8 pr-3 text-sm border rounded-lg reset-base mb-0 border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-n-brand"
                placeholder="输入商品编码 / 名称 / 规格搜索"
                @input="onSearch"
              />
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
            <button
              v-for="p in rows"
              v-else
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
              <span class="text-n-slate-11">{{ p.specification || '—' }}</span>
            </button>
          </div>
        </div>
      </transition>
    </teleport>
  </div>
</template>
