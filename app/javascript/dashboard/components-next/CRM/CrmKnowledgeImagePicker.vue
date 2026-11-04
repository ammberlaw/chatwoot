<script setup>
// 从知识库挑产品图，给报价单 / PI 的明细行用。
// 为什么是缩略图网格而不是列表：知识库里 691 张图的文档名都是「一.jpg」「二.jpg」，
// 名字完全认不出是什么产品，只能看图选。分区/分类才是有效的筛选维度
// （设计资料 › 白底主图 / 场景主图 / 详情页，以及 K705-A 这种型号分类）。
import { ref, computed } from 'vue';
import { useAlert } from 'dashboard/composables';
import KnowledgeDocAPI from 'dashboard/api/crm/knowledgeDocs';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';

const emit = defineEmits(['pick']);

const dialogRef = ref(null);
const loading = ref(false);
const rows = ref([]);
const sections = ref([]);
const categories = ref([]);
const sectionFilter = ref('');
const categoryFilter = ref('');
const keyword = ref('');
const picked = ref(null);

const opts = (list, allLabel) => [
  { value: '', label: allLabel },
  ...list.map(v => ({ value: v, label: v })),
];

const visible = computed(() =>
  rows.value.filter(r => {
    if (sectionFilter.value && r.section_name !== sectionFilter.value)
      return false;
    if (categoryFilter.value && r.category !== categoryFilter.value)
      return false;
    const kw = keyword.value.trim().toLowerCase();
    if (!kw) return true;
    return `${r.name} ${r.category || ''}`.toLowerCase().includes(kw);
  })
);

// 选了分区后，分类下拉只列这个分区下有的——691 张图摊开一百多个分类，
// 不收窄的话下拉本身就没法看。
const categoryOptions = computed(() => {
  const pool = sectionFilter.value
    ? rows.value.filter(r => r.section_name === sectionFilter.value)
    : rows.value;
  return opts(
    [...new Set(pool.map(r => r.category).filter(Boolean))].sort(),
    '全部分类'
  );
});

const open = async () => {
  picked.value = null;
  keyword.value = '';
  dialogRef.value?.open();
  if (rows.value.length) return;
  loading.value = true;
  try {
    const { data } = await KnowledgeDocAPI.imageLibrary({ library: 'GENERAL' });
    rows.value = data.payload || [];
    sections.value = data.sections || [];
    categories.value = data.categories || [];
  } catch {
    rows.value = [];
    useAlert('知识库图片加载失败');
  } finally {
    loading.value = false;
  }
};

const confirm = () => {
  if (!picked.value) return useAlert('请先选一张图');
  emit('pick', picked.value);
  dialogRef.value?.close();
  return undefined;
};

defineExpose({ open });
</script>

<template>
  <span>
    <slot name="trigger" :open="open" />

    <Dialog
      ref="dialogRef"
      overflow-y-auto
      width="xl"
      title="从知识库选图"
      confirm-button-label="选用这张"
      :disable-confirm-button="!picked"
      @confirm="confirm"
    >
      <div class="flex flex-col gap-3">
        <div class="flex flex-wrap items-center gap-2">
          <SelectCard
            v-model="sectionFilter"
            :options="opts(sections, '全部分区')"
            trigger-class="w-36 !h-9"
            @update:model-value="categoryFilter = ''"
          />
          <SelectCard
            v-model="categoryFilter"
            :options="categoryOptions"
            trigger-class="w-44 !h-9"
          />
          <Input
            v-model="keyword"
            placeholder="搜图片名 / 分类"
            class="flex-1 min-w-40"
          />
          <span class="text-label-small text-n-slate-11"
            >{{ visible.length }} 张</span
          >
        </div>

        <p v-if="loading" class="py-10 text-sm text-center text-n-slate-10">
          正在加载知识库图片…
        </p>
        <p
          v-else-if="!visible.length"
          class="py-10 text-sm text-center text-n-slate-10"
        >
          没有符合条件的图片
        </p>
        <div
          v-else
          class="grid grid-cols-3 gap-3 overflow-y-auto sm:grid-cols-4 lg:grid-cols-6 max-h-[52vh]"
        >
          <button
            v-for="r in visible"
            :key="r.attachment_id"
            type="button"
            class="flex flex-col gap-1 p-1 border rounded-lg text-left"
            :class="
              picked && picked.attachment_id === r.attachment_id
                ? 'border-n-slate-12 bg-n-alpha-2'
                : 'border-n-weak hover:border-n-slate-10'
            "
            @click="picked = r"
          >
            <img
              :src="r.url"
              :alt="r.name"
              loading="lazy"
              class="object-contain w-full rounded aspect-square bg-n-alpha-1"
            />
            <span class="truncate text-label-small text-n-slate-11">
              {{ r.category || r.name }}
            </span>
          </button>
        </div>
      </div>
    </Dialog>
  </span>
</template>
