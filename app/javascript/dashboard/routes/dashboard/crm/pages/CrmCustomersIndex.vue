<script setup>
/* global axios */
import { ref, computed, onMounted, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useCrmCustomersStore } from 'dashboard/stores/crm/customers';

import Button from 'dashboard/components-next/button/Button.vue';
import CrmCustomerCreateDialog from 'dashboard/components-next/CRM/CrmCustomerCreateDialog.vue';

const { t } = useI18n();
const route = useRoute();
const { accountId } = useAccount();
const customersStore = useCrmCustomersStore();

const actingId = ref(null);

const createDialogRef = ref(null);
const activeFilter = ref(route.query.filter || 'all');

const customers = computed(() => customersStore.getCustomers);
const uiFlags = computed(() => customersStore.getUIFlags);
const isFetching = computed(() => uiFlags.value.fetchingList);
const isCreating = computed(() => uiFlags.value.creatingItem);

const filterTabs = [
  { key: 'all', label: t('CRM.CUSTOMERS.FILTERS.ALL') },
  { key: 'mine', label: t('CRM.CUSTOMERS.FILTERS.MINE') },
  { key: 'private', label: t('CRM.CUSTOMERS.FILTERS.PRIVATE') },
  { key: 'public_pool', label: t('CRM.CUSTOMERS.FILTERS.PUBLIC_POOL') },
  { key: 'unassigned', label: t('CRM.CUSTOMERS.FILTERS.UNASSIGNED') },
];

const fetchCustomers = () => {
  const filter = activeFilter.value === 'all' ? undefined : activeFilter.value;
  customersStore.get({ page: 1, filter });
};

const setFilter = key => {
  activeFilter.value = key;
  fetchCustomers();
};

const openCreateDialog = () => createDialogRef.value?.open();
const openEditDialog = record => createDialogRef.value?.open(record);

const createCustomer = async customer => {
  try {
    await customersStore.create(customer);
    createDialogRef.value?.onSuccess();
    useAlert(t('CRM.CUSTOMERS.CREATE.SUCCESS'));
  } catch {
    useAlert(t('CRM.CUSTOMERS.CREATE.ERROR'));
  }
};

const updateCustomer = async customer => {
  try {
    await customersStore.update(customer);
    createDialogRef.value?.onSuccess();
    useAlert(t('CRM.CUSTOMERS.EDIT.SUCCESS'));
  } catch {
    useAlert(t('CRM.CUSTOMERS.EDIT.ERROR'));
  }
};

const formatDate = value =>
  value ? new Date(value).toLocaleDateString() : '—';

const crmApi = () => `/api/v1/accounts/${accountId.value}/crm/customers`;

// 认领：公海客户归我私海；转公海：私海客户放回公海。行按钮，阻止冒泡避免触发编辑。
const claimCustomer = async customer => {
  actingId.value = customer.id;
  try {
    await axios.post(`${crmApi()}/${customer.id}/claim`);
    useAlert(t('CRM.CUSTOMERS.POOL.CLAIM_SUCCESS'));
    fetchCustomers();
  } catch (e) {
    useAlert(e.response?.data?.message || t('CRM.CUSTOMERS.POOL.CLAIM_ERROR'));
  } finally {
    actingId.value = null;
  }
};

const releaseCustomer = async customer => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(t('CRM.CUSTOMERS.POOL.RELEASE_CONFIRM', { name: customer.name }))) {
    return;
  }
  actingId.value = customer.id;
  try {
    await axios.post(`${crmApi()}/${customer.id}/release`);
    useAlert(t('CRM.CUSTOMERS.POOL.RELEASE_SUCCESS'));
    fetchCustomers();
  } catch (e) {
    useAlert(e.response?.data?.message || t('CRM.CUSTOMERS.POOL.RELEASE_ERROR'));
  } finally {
    actingId.value = null;
  }
};

const SOURCE_LABELS = {
  ALIBABA: '阿里巴巴',
  WEBSITE: '官网',
  EXHIBITION: '展会',
  REFERRAL: '转介绍',
  EMAIL: '邮件开发',
  SOCIAL_MEDIA: '社媒',
  OTHER: '其他',
};

const GRADE_META = {
  COMPLETE: { label: '完善', class: 'text-n-teal-11' },
  GOOD: { label: '良好', class: 'text-n-blue-11' },
  FAIR: { label: '一般', class: 'text-n-amber-11' },
  POOR: { label: '待完善', class: 'text-n-ruby-11' },
};

const gradeInfo = customer => {
  const meta = GRADE_META[customer.completenessGrade] || {
    label: '—',
    class: 'text-n-slate-10',
  };
  const score = customer.infoCompletenessScore;
  return { ...meta, score: score != null ? score : null };
};

const sourceLabel = source => (source ? SOURCE_LABELS[source] || source : '—');

const money = micros =>
  micros ? `¥${Math.round(micros / 1_000_000).toLocaleString()}` : '¥0';

onMounted(() => {
  fetchCustomers();
  if (route.query.new) openCreateDialog();
});
watch(
  () => [route.query.filter, route.query.new],
  () => {
    activeFilter.value = route.query.filter || 'all';
    fetchCustomers();
    if (route.query.new) openCreateDialog();
  }
);
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto bg-n-background">
    <div
      class="flex items-center justify-between flex-shrink-0 px-6 py-4 border-b border-n-weak"
    >
      <h1 class="text-xl font-medium text-n-slate-12">
        {{ t('CRM.CUSTOMERS.HEADER') }}
      </h1>
      <Button
        :label="t('CRM.CUSTOMERS.NEW')"
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
        {{ t('CRM.CUSTOMERS.LOADING') }}
      </div>
      <div
        v-else-if="!customers.length"
        class="flex items-center justify-center p-8 text-base text-n-slate-11"
      >
        {{ t('CRM.CUSTOMERS.EMPTY') }}
      </div>
      <table v-else class="w-full text-sm text-left border-collapse">
        <thead class="text-n-slate-11">
          <tr class="border-b border-n-weak">
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.CUSTOMERS.TABLE.NAME') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.CUSTOMERS.TABLE.CODE') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.CUSTOMERS.TABLE.COUNTRY') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.CUSTOMERS.TABLE.STATUS') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.CUSTOMERS.TABLE.SOURCE') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.CUSTOMERS.TABLE.GRADE') }}
            </th>
            <th class="px-3 py-2 font-medium text-right">
              {{ t('CRM.CUSTOMERS.TABLE.DEAL_AMOUNT') }}
            </th>
            <th class="px-3 py-2 font-medium text-right">
              {{ t('CRM.CUSTOMERS.TABLE.DEAL_COUNT') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.CUSTOMERS.TABLE.OWNER') }}
            </th>
            <th class="px-3 py-2 font-medium text-right">
              {{ t('CRM.CUSTOMERS.TABLE.ACTION') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="customer in customers"
            :key="customer.id"
            class="cursor-pointer border-b border-n-weak hover:bg-n-alpha-1"
            @click="openEditDialog(customer)"
          >
            <td class="px-3 py-2 text-n-slate-12">{{ customer.name }}</td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ customer.customerCode || '—' }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ customer.tradeCountry || '—' }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ customer.customerStatus || '—' }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ sourceLabel(customer.sourceChannel) }}
            </td>
            <td class="px-3 py-2">
              <span :class="gradeInfo(customer).class">
                {{ gradeInfo(customer).label }}
                <span
                  v-if="gradeInfo(customer).score != null"
                  class="text-n-slate-10"
                >
                  {{ gradeInfo(customer).score }}
                </span>
              </span>
            </td>
            <td class="px-3 py-2 text-right text-n-slate-11">
              {{ money(customer.dealTotalAmountMicros) }}
            </td>
            <td class="px-3 py-2 text-right text-n-slate-11">
              {{ customer.dealOrderCount || 0 }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              <span v-if="customer.isInPublicPool" class="text-n-sky-11">🌊 公海</span>
              <span v-else-if="customer.accountOwnerName">
                {{ customer.accountOwnerName }}
              </span>
              <span v-else class="text-n-slate-10">未分配</span>
            </td>
            <td class="px-3 py-2 text-right" @click.stop>
              <Button
                v-if="customer.isInPublicPool"
                :label="t('CRM.CUSTOMERS.POOL.CLAIM')"
                size="sm"
                color="blue"
                :is-loading="actingId === customer.id"
                @click="claimCustomer(customer)"
              />
              <Button
                v-else
                :label="t('CRM.CUSTOMERS.POOL.RELEASE')"
                size="sm"
                variant="faded"
                color="slate"
                :is-loading="actingId === customer.id"
                @click="releaseCustomer(customer)"
              />
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <CrmCustomerCreateDialog
      ref="createDialogRef"
      :is-loading="isCreating"
      @create="createCustomer"
      @update="updateCustomer"
    />
  </div>
</template>
