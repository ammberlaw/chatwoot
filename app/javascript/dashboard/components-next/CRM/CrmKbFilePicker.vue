<script setup>
// 从知识库挑文件当附件用的选择器。写邮件和会话回复两处共用同一套：
// 左边文档列表（搜索 / 公司·我的 / 分类），右边该文档下的文件勾选。
// 组件只负责「挑」，挑完的东西交给调用方去发——邮件走 attach_kb，
// 会话走 snapshot_files 换成 signed_id 挂进消息附件。
import { ref, computed, watch } from 'vue';
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
    await loadKbDocs();
  }
);
</script>

<template>
  <!-- 知识库选择器 -->
  <div
    v-if="open"
    class="fixed inset-0 z-10 flex items-center justify-center bg-black/40"
    @click.self="emit('update:open', false)"
  >
    <div
      class="w-[780px] max-w-[94vw] h-[560px] max-h-[88vh] flex flex-col overflow-hidden border rounded-xl border-n-weak bg-n-solid-1"
    >
      <div
        class="flex items-center justify-between px-4 py-3 border-b border-n-weak"
      >
        <strong class="text-n-slate-12">{{ L.kbTitle }}</strong>
        <button
          class="text-sm text-n-iris-11"
          @click="emit('update:open', false)"
        >
          {{ L.kbDone
          }}{{ kbPicked.length ? `（已选 ${kbPicked.length}）` : '' }}
        </button>
      </div>

      <!-- 过滤 -->
      <div class="px-4 py-2.5 border-b bg-n-alpha-1 border-n-weak">
        <input
          v-model="kbSearch"
          class="w-full h-9 px-3 mb-2 text-sm border rounded-lg reset-base border-n-weak bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus-visible:ring-1 focus-visible:ring-n-iris-9"
          :placeholder="L.kbSearchPlaceholder"
        />
        <div class="flex flex-wrap items-center gap-1.5">
          <button
            v-for="chip in kbScopeChips"
            :key="chip.value"
            class="px-2.5 py-1 text-xs border rounded-full"
            :class="
              kbScope === chip.value
                ? 'border-n-iris-9 bg-n-iris-9 text-white'
                : 'border-n-weak text-n-slate-11'
            "
            @click="kbScope = chip.value"
          >
            {{ chip.label }}
          </button>
          <span class="w-px h-4 mx-1 bg-n-weak" />
          <button
            class="px-2.5 py-1 text-xs border rounded-full"
            :class="
              kbCategory === ''
                ? 'border-n-iris-9 bg-n-iris-9 text-white'
                : 'border-n-weak text-n-slate-11'
            "
            @click="kbCategory = ''"
          >
            {{ L.kbAllCategories }}
          </button>
          <button
            v-for="cat in kbCategories"
            :key="cat"
            class="px-2.5 py-1 text-xs border rounded-full"
            :class="
              kbCategory === cat
                ? 'border-n-iris-9 bg-n-iris-9 text-white'
                : 'border-n-weak text-n-slate-11'
            "
            @click="kbCategory = cat"
          >
            {{ cat }}
          </button>
        </div>
      </div>

      <!-- 文档列表 + 文件面板 -->
      <div class="flex flex-1 min-h-0">
        <div class="w-[280px] shrink-0 overflow-y-auto border-r border-n-weak">
          <div
            v-if="!kbFilteredDocs.length"
            class="p-3 text-xs text-n-slate-10"
          >
            {{ kbDocs.length ? L.kbEmptyNoMatch : L.kbEmptyNoFiles }}
          </div>
          <button
            v-for="doc in kbFilteredDocs"
            :key="doc.id"
            class="block w-full px-3.5 py-2.5 text-left border-b border-n-weak"
            :class="
              kbOpenDoc?.id === doc.id ? 'bg-n-iris-2' : 'hover:bg-n-alpha-1'
            "
            @click="kbOpenDocId = doc.id"
          >
            <div class="flex items-center gap-1.5 text-[13px] text-n-slate-12">
              <Icon
                :icon="
                  doc.scope === 'COMPANY'
                    ? 'i-lucide-building-2'
                    : 'i-lucide-user'
                "
                class="size-3.5 text-n-slate-10"
              />
              <span class="truncate">{{ doc.name }}</span>
              <span
                v-if="kbPicksForDoc(doc.id)"
                class="ml-auto min-w-4 h-4 px-1 text-[11px] text-white rounded-full bg-n-iris-9 inline-flex items-center justify-center"
              >
                {{ kbPicksForDoc(doc.id) }}
              </span>
            </div>
            <div class="mt-0.5 text-[11px] text-n-slate-10">
              {{ `${doc.category || '未分类'} · ${doc.files.length} 个文件` }}
            </div>
          </button>
        </div>

        <div class="flex-1 overflow-y-auto">
          <div v-if="!kbOpenDoc" class="p-3 text-xs text-n-slate-10">
            {{ L.kbPickFilePrompt }}
          </div>
          <template v-else>
            <div
              class="px-3.5 py-2.5 border-b border-n-weak text-[13px] text-n-slate-11"
            >
              {{ kbOpenDoc.name }}
              <div
                v-if="kbOpenDoc.summary"
                class="mt-1 text-[11px] leading-relaxed text-n-slate-10"
              >
                {{ kbOpenDoc.summary }}
              </div>
            </div>
            <div class="flex flex-col gap-1.5 p-3">
              <button
                v-for="file in kbOpenDoc.files"
                :key="file.fileId"
                class="flex items-center gap-2 px-3 py-2 text-[13px] border rounded-lg"
                :class="
                  isKbPicked(kbOpenDoc.id, file.fileId)
                    ? 'border-n-iris-9 text-n-iris-11 bg-n-iris-2'
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
                  class="size-4"
                />
                <Icon icon="i-lucide-file-text" class="size-4" />
                {{ file.filename }}
              </button>
            </div>
          </template>
        </div>
      </div>

      <div
        class="flex items-center gap-2 px-4 py-2.5 border-t bg-n-alpha-1 border-n-weak"
      >
        <span class="flex-1 text-xs text-n-slate-10">{{ footTip }}</span>
        <button
          class="px-4 py-1.5 text-sm font-medium text-white rounded-full bg-gradient-to-br from-n-iris-9 to-n-accent-grad hover:brightness-105"
          @click="emit('update:open', false)"
        >
          {{ L.kbDone }}
        </button>
      </div>
    </div>
  </div>
</template>
