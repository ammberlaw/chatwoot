<script setup>
// 从知识库挑文件当附件用的选择器。写邮件和会话回复两处共用同一套：
// 左边文档列表（搜索 / 公司·我的 / 分类），右边该文档下的文件勾选。
// 组件只负责「挑」，挑完的东西交给调用方去发——邮件走 attach_kb，
// 会话走 snapshot_files 换成 signed_id 挂进消息附件。
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import camelcaseKeys from 'camelcase-keys';
import KnowledgeDocsAPI from 'dashboard/api/crm/knowledgeDocs';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  open: { type: Boolean, default: false },
  // 已勾选的文件：[{ docId, docName, fileId, label }]
  picked: { type: Array, default: () => [] },
  // 底部那行说明，两处口径不一样（邮件说「复制进本邮件」，会话说「随消息发出」）。
  footTip: { type: String, default: '' },
});
const emit = defineEmits(['update:open', 'update:picked']);
const { t } = useI18n();

const L = {
  kbTitle: '从知识库选择附件',
  kbDone: '完成',
  kbSearchPlaceholder: '搜索文档名 / 摘要 / 文件名',
  kbCompany: '公司',
  kbPersonal: '我的',
  kbAllCategories: '全部分类',
  kbEmptyNoFiles: '知识库里还没有带文件的文档。',
  kbEmptyNoMatch: '没有匹配的文档，换个搜索词或分类试试。',
  kbPickFilePrompt: '选择左侧一篇文档查看并勾选文件。',
};

const kbDocs = ref([]);
const loading = ref(false);
const loadFailed = ref(false);
const kbSearch = ref('');
const kbCategory = ref('');
const kbScope = ref('');
const kbOpenDocId = ref(null);

const kbScopeChips = [
  { value: '', label: '全部' },
  { value: 'COMPANY', label: L.kbCompany },
  { value: 'PERSONAL', label: L.kbPersonal },
];
const kbCategories = computed(() => [
  ...new Set(kbDocs.value.map(d => d.category).filter(Boolean)),
]);

const categoryOptions = computed(() => [
  { value: '', label: L.kbAllCategories },
  ...kbCategories.value.map(category => ({ value: category, label: category })),
]);

const kbKey = item => `${item.docId}:${item.fileId}`;

const kbFilteredDocs = computed(() => {
  const q = kbSearch.value.trim().toLowerCase();
  return kbDocs.value.filter(d => {
    if (kbScope.value && d.scope !== kbScope.value) return false;
    if (kbCategory.value && d.category !== kbCategory.value) return false;
    if (
      q &&
      !(
        `${d.name} ${d.summary || ''}`.toLowerCase().includes(q) ||
        d.files.some(f => f.filename.toLowerCase().includes(q))
      )
    )
      return false;
    return true;
  });
});

const kbOpenDoc = computed(
  () =>
    kbFilteredDocs.value.find(d => d.id === kbOpenDocId.value) ||
    kbFilteredDocs.value[0] ||
    null
);

// 只挑销售资料库，别把内部制度、考勤规定这类文档挂给客户。
const loadKbDocs = async () => {
  const { data } = await KnowledgeDocsAPI.get({
    library: 'SALES',
    per_page: 200,
  });
  kbDocs.value = camelcaseKeys(data.payload || [], { deep: true })
    .map(d => ({
      id: d.id,
      name: d.name || '(未命名)',
      scope: d.scope || 'PERSONAL',
      category: d.category || '',
      summary: d.summary || '',
      files: (d.files || []).map(f => ({
        fileId: f.id,
        filename: f.filename || '(未命名文件)',
      })),
    }))
    .filter(d => d.files.length > 0);
};

const kbPicked = computed({
  get: () => props.picked,
  set: v => emit('update:picked', v),
});

const toggleKbFile = (doc, file) => {
  const item = {
    docId: doc.id,
    docName: doc.name,
    fileId: file.fileId,
    label: file.filename,
  };
  const exists = kbPicked.value.some(p => kbKey(p) === kbKey(item));
  kbPicked.value = exists
    ? kbPicked.value.filter(p => kbKey(p) !== kbKey(item))
    : [...kbPicked.value, item];
};
const isKbPicked = (docId, fileId) =>
  kbPicked.value.some(p => p.docId === docId && p.fileId === fileId);
const kbPicksForDoc = docId =>
  kbPicked.value.filter(p => p.docId === docId).length;

// 每次打开都重拉一遍并清掉筛选：知识库是别人也在改的，拿上次缓存的列表容易看到已删的文件。
watch(
  () => props.open,
  async isOpen => {
    if (!isOpen) return;
    kbOpenDocId.value = null;
    kbSearch.value = '';
    kbCategory.value = '';
    kbScope.value = '';
    loading.value = true;
    loadFailed.value = false;
    try {
      await loadKbDocs();
    } catch {
      loadFailed.value = true;
    } finally {
      loading.value = false;
    }
  }
);
</script>

<template>
  <div
    v-if="open"
    class="fixed inset-0 z-10 flex items-center justify-center bg-black/40 p-4"
    @click.self="emit('update:open', false)"
    @keydown.esc.stop="emit('update:open', false)"
  >
    <section
      role="dialog"
      aria-modal="true"
      aria-labelledby="kb-file-picker-title"
      class="flex h-[600px] max-h-[88dvh] w-[900px] max-w-full flex-col overflow-hidden rounded-2xl border border-n-weak bg-n-solid-1 shadow-xl"
    >
      <header
        class="flex shrink-0 items-center justify-between gap-4 border-b border-n-weak px-5 py-4"
      >
        <h2
          id="kb-file-picker-title"
          class="m-0 text-heading-2 text-n-slate-12"
        >
          {{ L.kbTitle }}
        </h2>
        <Button
          icon="i-lucide-x"
          :aria-label="t('CRM.KB_PICKER.CLOSE')"
          variant="ghost"
          color="slate"
          @click="emit('update:open', false)"
        />
      </header>

      <div
        class="flex shrink-0 flex-col gap-3 border-b border-n-weak px-5 py-4"
      >
        <div class="relative">
          <Icon
            icon="i-lucide-search"
            class="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-n-slate-10"
          />
          <input
            v-model="kbSearch"
            :aria-label="L.kbSearchPlaceholder"
            :placeholder="L.kbSearchPlaceholder"
            class="reset-base m-0 h-10 w-full rounded-lg border border-n-weak bg-n-alpha-1 py-0 pl-9 pr-3 text-label !font-normal text-n-slate-12 placeholder:text-n-slate-10 focus-visible:ring-1 focus-visible:ring-n-iris-9"
          />
        </div>
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div class="flex items-center gap-1 rounded-lg bg-n-alpha-1 p-1">
            <button
              v-for="chip in kbScopeChips"
              :key="chip.value"
              type="button"
              :aria-pressed="kbScope === chip.value"
              class="h-8 rounded-md px-4 text-label-small transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-iris-9"
              :class="
                kbScope === chip.value
                  ? 'bg-n-solid-1 text-n-slate-12 shadow-sm'
                  : 'text-n-slate-11 hover:text-n-slate-12'
              "
              @click="kbScope = chip.value"
            >
              {{ chip.label }}
            </button>
          </div>
          <SelectCard
            v-model="kbCategory"
            :options="categoryOptions"
            searchable
            :search-placeholder="t('CRM.KB_PICKER.SEARCH_CATEGORY')"
            trigger-class="w-52 max-w-full"
          />
        </div>
      </div>

      <div
        v-if="loading || loadFailed"
        role="status"
        class="flex flex-1 items-center justify-center p-6 text-label text-n-slate-11"
      >
        {{ t(loading ? 'CRM.KB_PICKER.LOADING' : 'CRM.KB_PICKER.LOAD_ERROR') }}
      </div>
      <div v-else class="flex min-h-0 flex-1">
        <div
          class="flex w-2/5 min-w-0 shrink-0 flex-col border-r border-n-weak bg-n-alpha-1 sm:w-[300px]"
        >
          <div
            class="flex shrink-0 items-center justify-between px-4 py-3 text-label-small text-n-slate-11"
          >
            <span>{{ t('CRM.KB_PICKER.DOCUMENTS') }}</span>
            <span class="tabular-nums">{{ kbFilteredDocs.length }}</span>
          </div>
          <div class="min-h-0 flex-1 overflow-y-auto px-2 pb-2">
            <p
              v-if="!kbFilteredDocs.length"
              class="p-3 text-label-small text-n-slate-11"
            >
              {{ kbDocs.length ? L.kbEmptyNoMatch : L.kbEmptyNoFiles }}
            </p>
            <button
              v-for="doc in kbFilteredDocs"
              :key="doc.id"
              type="button"
              :aria-pressed="kbOpenDoc?.id === doc.id"
              :title="doc.name"
              class="mb-1 block w-full rounded-lg border px-3 py-3 text-left transition-colors"
              :class="
                kbOpenDoc?.id === doc.id
                  ? 'border-n-weak bg-n-solid-1'
                  : 'border-transparent hover:bg-n-alpha-2'
              "
              @click="kbOpenDocId = doc.id"
            >
              <div
                class="flex items-start gap-2 text-label !font-normal text-n-slate-12"
              >
                <Icon
                  :icon="
                    doc.scope === 'COMPANY'
                      ? 'i-lucide-building-2'
                      : 'i-lucide-user'
                  "
                  class="mt-0.5 size-4 shrink-0 text-n-slate-10"
                />
                <span class="min-w-0 flex-1 break-words line-clamp-2">{{
                  doc.name
                }}</span>
                <span
                  v-if="kbPicksForDoc(doc.id)"
                  class="shrink-0 rounded-md bg-n-iris-3 px-1.5 text-label-small tabular-nums text-n-iris-11"
                  >{{ kbPicksForDoc(doc.id) }}</span
                >
              </div>
              <p
                class="mb-0 mt-2 truncate pl-6 text-label-small text-n-slate-11"
              >
                {{ `${doc.category || '未分类'} · ${doc.files.length} 个文件` }}
              </p>
            </button>
          </div>
        </div>

        <div class="flex min-w-0 flex-1 flex-col">
          <p v-if="!kbOpenDoc" class="p-5 text-label text-n-slate-11">
            {{ L.kbPickFilePrompt }}
          </p>
          <template v-else>
            <div class="shrink-0 border-b border-n-weak px-5 py-4">
              <h3 class="m-0 break-words text-heading-3 text-n-slate-12">
                {{ kbOpenDoc.name }}
              </h3>
              <p
                v-if="kbOpenDoc.summary"
                class="mb-0 mt-2 max-h-20 overflow-y-auto text-label-small !font-normal leading-relaxed text-n-slate-11"
              >
                {{ kbOpenDoc.summary }}
              </p>
              <p class="mb-0 mt-2 text-label-small text-n-slate-10">
                {{ t('CRM.KB_PICKER.SELECT_FILES') }}
              </p>
            </div>
            <div class="min-h-0 flex-1 space-y-2 overflow-y-auto p-4">
              <button
                v-for="file in kbOpenDoc.files"
                :key="file.fileId"
                type="button"
                :aria-pressed="isKbPicked(kbOpenDoc.id, file.fileId)"
                class="flex w-full items-start gap-3 rounded-lg border p-3 text-left transition-colors focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-iris-9"
                :class="
                  isKbPicked(kbOpenDoc.id, file.fileId)
                    ? 'border-n-iris-8 bg-n-iris-2 text-n-slate-12'
                    : 'border-n-weak text-n-slate-12 hover:bg-n-alpha-1'
                "
                @click="toggleKbFile(kbOpenDoc, file)"
              >
                <Icon
                  :icon="
                    isKbPicked(kbOpenDoc.id, file.fileId)
                      ? 'i-lucide-check-square'
                      : 'i-lucide-square'
                  "
                  class="mt-0.5 size-4 shrink-0"
                  :class="
                    isKbPicked(kbOpenDoc.id, file.fileId)
                      ? 'text-n-iris-11'
                      : 'text-n-slate-10'
                  "
                />
                <Icon
                  icon="i-lucide-file-text"
                  class="mt-0.5 hidden size-4 shrink-0 text-n-slate-10 sm:block"
                />
                <span
                  class="min-w-0 break-all text-label !font-normal leading-relaxed"
                  >{{ file.filename }}</span
                >
              </button>
            </div>
          </template>
        </div>
      </div>

      <footer
        class="flex shrink-0 flex-wrap items-center justify-between gap-3 border-t border-n-weak px-5 py-4"
      >
        <div class="min-w-0 flex-1">
          <p class="m-0 text-label text-n-slate-12">
            {{ t('CRM.KB_PICKER.PICKED', { count: kbPicked.length }) }}
          </p>
          <p
            v-if="footTip"
            class="mb-0 mt-1 text-label-small !font-normal text-n-slate-11"
          >
            {{ footTip }}
          </p>
        </div>
        <Button :label="L.kbDone" @click="emit('update:open', false)" />
      </footer>
    </section>
  </div>
</template>
