<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useCrmCustomersStore } from 'dashboard/stores/crm/customers';

import Button from 'dashboard/components-next/button/Button.vue';
import CrmCustomerCreateDialog from 'dashboard/components-next/CRM/CrmCustomerCreateDialog.vue';

const { t } = useI18n();
const route = useRoute();
const customersStore = useCrmCustomersStore();

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
              {{ t('CRM.CUSTOMERS.TABLE.LEVEL') }}
            </th>
            <th class="px-3 py-2 font-medium">
              {{ t('CRM.CUSTOMERS.TABLE.LAST_FOLLOW_UP') }}
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
              {{ customer.customerLevel || '—' }}
            </td>
            <td class="px-3 py-2 text-n-slate-11">
              {{ formatDate(customer.lastFollowUpAt) }}
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
