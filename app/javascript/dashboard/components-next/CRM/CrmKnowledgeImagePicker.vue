<script setup>
// 从知识库挑产品图，给报价单 / PI 的明细行用。
// 为什么是缩略图网格而不是列表：知识库里 691 张图的文档名都是「一.jpg」「二.jpg」，
// 名字完全认不出是什么产品，只能看图选。分区/分类才是有效的筛选维度
// （设计资料 › 白底主图 / 场景主图 / 详情页，以及 K705-A 这种型号分类）。
import { ref, computed, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { useAlert } from 'dashboard/composables';
import KnowledgeDocAPI from 'dashboard/api/crm/knowledgeDocs';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';

const emit = defineEmits(['pick']);
const { t } = useI18n();
const label = key => t(`CRM.KNOWLEDGE_WORKFLOW.${key}`);
const count = ref(0);
const page = ref(1);
const hasMore = ref(false);
let generation = 0;
let searchTimer;
const opened = ref(false);

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

const visible = computed(() => rows.value);
const categoryOptions = computed(() =>
  opts(categories.value, label('ALL_CATEGORIES'))
);
const load = async (nextPage = 1) => {
  generation += 1;
  const request = generation;
  picked.value = null;
  loading.value = true;
  try {
    const { data } = await KnowledgeDocAPI.imageLibrary({
      library: 'GENERAL',
      q: keyword.value.trim(),
      image_section: sectionFilter.value,
      image_category: categoryFilter.value,
      page: nextPage,
      per_page: 48,
    });
    if (request !== generation) return;
    rows.value = data.payload || [];
    sections.value = data.sections || [];
    categories.value = data.categories || [];
    count.value = data.count || 0;
    page.value = data.page;
    hasMore.value = data.has_more;
  } catch {
    if (request !== generation) return;
    rows.value = [];
    count.value = 0;
    hasMore.value = false;
    useAlert(label('IMAGE_ERROR'));
  } finally {
    if (request === generation) loading.value = false;
  }
};
watch([sectionFilter, categoryFilter, keyword], () => {
  if (!opened.value) return;
  generation += 1;
  picked.value = null;
  clearTimeout(searchTimer);
  searchTimer = setTimeout(() => load(), 250);
});
const close = () => {
  opened.value = false;
  generation += 1;
  clearTimeout(searchTimer);
};
const open = () => {
  clearTimeout(searchTimer);
  opened.value = true;
  dialogRef.value?.open();
  load();
};
onBeforeUnmount(() => {
  generation += 1;
  clearTimeout(searchTimer);
});

const confirm = () => {
  if (!picked.value) return useAlert(label('PICK_IMAGE'));
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
      :title="label('IMAGE_LIBRARY')"
      :confirm-button-label="label('USE_IMAGE')"
      :disable-confirm-button="!picked || loading"
      @confirm="confirm"
      @close="close"
    >
      <div class="flex flex-col gap-3">
        <div class="flex flex-wrap items-center gap-2">
          <SelectCard
            v-model="sectionFilter"
            :options="opts(sections, label('ALL_SECTIONS'))"
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
            :placeholder="label('IMAGE_SEARCH')"
            class="flex-1 min-w-40"
          />
          <span class="text-label-small text-n-slate-11">{{
            t('CRM.KNOWLEDGE_WORKFLOW.IMAGE_COUNT', { count })
          }}</span>
        </div>

        <div class="flex items-center justify-end gap-2">
          <Button
            :label="label('REFRESH')"
            size="sm"
            variant="ghost"
            color="slate"
            :disabled="loading"
            @click="load()"
          />
          <Button
            :label="label('PREVIOUS')"
            size="sm"
            variant="outline"
            color="slate"
            :disabled="loading || page <= 1"
            @click="load(page - 1)"
          />
          <span class="text-label-small">{{ page }}</span>
          <Button
            :label="label('NEXT')"
            size="sm"
            variant="outline"
            color="slate"
            :disabled="loading || !hasMore"
            @click="load(page + 1)"
          />
        </div>
        <p v-if="loading" class="py-10 text-sm text-center text-n-slate-10">
          {{ label('LOADING') }}
        </p>
        <p
          v-else-if="!visible.length"
          class="py-10 text-sm text-center text-n-slate-10"
        >
          {{ label('NO_IMAGES') }}
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
