<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useCrmKnowledgeDocsStore } from 'dashboard/stores/crm/knowledgeDocs';

import Button from 'dashboard/components-next/button/Button.vue';
import CrmKnowledgeDocCreateDialog from 'dashboard/components-next/CRM/CrmKnowledgeDocCreateDialog.vue';

const { t } = useI18n();
const route = useRoute();
const store = useCrmKnowledgeDocsStore();

const createDialogRef = ref(null);
const activeFilter = ref(route.query.filter || 'company');

const records = computed(() => store.getRecords);
const uiFlags = computed(() => store.getUIFlags);
const isFetching = computed(() => uiFlags.value.fetchingList);
const isCreating = computed(() => uiFlags.value.creatingItem);

const CATEGORIES = {
  PRODUCT_CATALOG: '产品目录',
  FAQ: 'FAQ',
  AFTER_SALES: '售后政策',
  QUOTE_TEMPLATE: '报价模板',
  COMPANY_CERT: '公司资质',
  USER_MANUAL: '操作手册',
  PRODUCT_SPEC: '产品规格书',
  PAYMENT_ACCOUNT: '收款账户',
};

const filterTabs = [
  { key: 'company', label: t('CRM.KNOWLEDGE_DOCS.FILTERS.COMPANY') },
  { key: 'mine', label: t('CRM.KNOWLEDGE_DOCS.FILTERS.MINE') },
];

const fetchRecords = () => {
  store.get({ page: 1, filter: activeFilter.value });
};

const setFilter = key => {
  activeFilter.value = key;
  fetchRecords();
};

const openCreateDialog = () => createDialogRef.value?.open();

const createRecord = async payload => {
  try {
    await store.create(payload);
    createDialogRef.value?.onSuccess();
    useAlert(t('CRM.KNOWLEDGE_DOCS.CREATE.SUCCESS'));
    fetchRecords();
  } catch {
    useAlert(t('CRM.KNOWLEDGE_DOCS.CREATE.ERROR'));
  }
};

onMounted(fetchRecords);
watch(
  () => route.query.filter,
  value => {
    activeFilter.value = value || 'company';
    fetchRecords();
  }
);

const fmtDate = value => (value ? new Date(value).toLocaleDateString() : '—');
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto bg-n-background">
    <div
      class="flex items-center justify-between flex-shrink-0 px-6 py-4 border-b border-n-weak"
    >
      <h1 class="text-xl font-medium text-n-slate-12">
        {{ t('CRM.KNOWLEDGE_DOCS.HEADER') }}
      </h1>
      <Button
        :label="t('CRM.KNOWLEDGE_DOCS.NEW')"
        icon="i-lucide-plus"
        color="blue"
        @click="openCreateDialog"
      />
    </div>

    <div class="flex items-center gap-2 px-6 py-3 border-b border-n-weak">
      <Button
        v-for="tab in filterTabs"
        :key="tab.key"
        :label="tab.label"
        size="sm"
        :variant="activeFilter === tab.key ? 'solid' : 'faded'"
        :color="activeFilter === tab.key ? 'blue' : 'slate'"
        @click="setFilter(tab.key)"
      />
    </div>

    <div class="flex-1 px-6 py-4">
      <div
        v-if="isFetching"
        class="flex items-center justify-center p-8 text-base text-n-slate-11"
      >
        {{ t('CRM.KNOWLEDGE_DOCS.LOADING') }}
      </div>
      <div
        v-else-if="!records.length"
        class="flex items-center justify-center p-8 text-base text-n-slate-11"
      >
        {{ t('CRM.KNOWLEDGE_DOCS.EMPTY') }}
      </div>
      <table v-else class="w-full text-sm text-left border-collapse">
        <thead class="text-n-slate-11">
          <tr class="border-b border-n-weak">
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.KNOWLEDGE_DOCS.TABLE.NAME') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.KNOWLEDGE_DOCS.TABLE.CATEGORY') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.KNOWLEDGE_DOCS.TABLE.SUMMARY') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.KNOWLEDGE_DOCS.TABLE.UPDATED_AT') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="record in records"
            :key="record.id"
            class="border-b border-n-weak hover:bg-n-alpha-1"
          >
            <td class="px-3 py-2 font-medium text-n-slate-12">
              {{ record.name }}
            </td>
            <td class="px-3 py-2">
              <span
                class="px-2 py-0.5 rounded-full text-xs font-medium bg-n-slate-3 text-n-slate-11"
              >
                {{ CATEGORIES[record.category] || '—' }}
              </span>
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ record.summary || '—' }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ fmtDate(record.updatedAt) }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <CrmKnowledgeDocCreateDialog
      ref="createDialogRef"
      :is-loading="isCreating"
      @create="createRecord"
    />
  </div>
</template>
