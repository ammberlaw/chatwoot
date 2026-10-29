<script setup>
import { ref, watch } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';

import CrmCustomerAPI from 'dashboard/api/crm/customers';
import CrmSalesOrderAPI from 'dashboard/api/crm/salesOrders';
import CrmAgentAPI from 'dashboard/api/crm/crmAgents';
import MesSupplierAPI from 'dashboard/api/mes/suppliers';
import OrgDepartmentAPI from 'dashboard/api/org/departments';

// 分录行的核算维度录入：按传入的 dimensions 渲染对应下拉。
// 客户/供应商/订单走接口搜索（数据量大），部门/业务员一次拉全本地过滤。
//
// ⚠️ 搜索必须显式传 per_page：不传就被后端截断在 15 条，下拉里只剩几行、
// 还没法往下翻，搜不到的就当不存在（和车间退料单那次是同一个坑）。
const SEARCH_PER_PAGE = 50;
const props = defineProps({
  dimensions: { type: Array, default: () => [] },
  requiredDimension: { type: String, default: '' },
});

const row = defineModel({ type: Object, required: true });

const LABELS = {
  customer: '客户',
  supplier: '供应商',
  order: '订单',
  department: '部门',
  member: '业务员',
};

const accountId = useMapGetter('getCurrentAccountId');

const customerOptions = ref([]);
const supplierOptions = ref([]);
const orderOptions = ref([]);
const departmentOptions = ref([]);
const memberOptions = ref([]);

const searchCustomers = async q => {
  const { data } = await CrmCustomerAPI.get({
    q,
    page: 1,
    per_page: SEARCH_PER_PAGE,
  });
  customerOptions.value = (data?.payload || []).map(c => ({
    value: c.id,
    label: c.name,
  }));
};
const searchSuppliers = async q => {
  const { data } = await MesSupplierAPI.get({
    q,
    active: 'true',
    per_page: SEARCH_PER_PAGE,
  });
  supplierOptions.value = (data?.payload || []).map(s => ({
    value: s.id,
    label: s.name,
  }));
};
const searchOrders = async q => {
  const { data } = await CrmSalesOrderAPI.get({
    q,
    page: 1,
    per_page: SEARCH_PER_PAGE,
  });
  orderOptions.value = (data?.payload || []).map(o => ({
    value: o.id,
    label: `${o.order_no} ${o.name || ''}`.trim(),
  }));
};
const loadDepartments = async () => {
  if (departmentOptions.value.length) return;
  const { data } = await OrgDepartmentAPI.get();
  departmentOptions.value = (data?.payload || []).map(d => ({
    value: d.id,
    label: d.name,
  }));
};
const loadMembers = async () => {
  if (memberOptions.value.length) return;
  const { data } = await CrmAgentAPI.get(accountId.value);
  memberOptions.value = (data?.payload || []).map(m => ({
    value: m.id,
    label: m.crm_name || m.name,
  }));
};

watch(
  () => props.dimensions,
  dims => {
    if (dims.includes('department')) loadDepartments();
    if (dims.includes('member')) loadMembers();
  },
  { immediate: true }
);

const isRequired = dim => dim === props.requiredDimension;
</script>

<template>
  <div v-if="dimensions.length" class="flex flex-wrap items-center gap-2">
    <template v-for="dim in dimensions" :key="dim">
      <div class="flex items-center gap-1.5">
        <span class="text-xs whitespace-nowrap text-n-slate-11">
          {{ LABELS[dim] }}
          <span v-if="isRequired(dim)" class="text-n-ruby-11">*</span>
        </span>
        <div class="w-44">
          <ComboBox
            v-if="dim === 'customer'"
            v-model="row.crmCustomerId"
            :options="customerOptions"
            :display-label="row.crmCustomerName"
            use-api-results
            placeholder="搜客户"
            @search="searchCustomers"
          />
          <ComboBox
            v-else-if="dim === 'supplier'"
            v-model="row.mesSupplierId"
            :options="supplierOptions"
            :display-label="row.mesSupplierName"
            use-api-results
            placeholder="搜供应商"
            @search="searchSuppliers"
          />
          <ComboBox
            v-else-if="dim === 'order'"
            v-model="row.crmSalesOrderId"
            :options="orderOptions"
            :display-label="row.crmSalesOrderNo"
            use-api-results
            placeholder="搜订单号"
            @search="searchOrders"
          />
          <ComboBox
            v-else-if="dim === 'department'"
            v-model="row.departmentId"
            :options="departmentOptions"
            placeholder="选部门"
          />
          <ComboBox
            v-else
            v-model="row.memberId"
            :options="memberOptions"
            placeholder="选业务员"
          />
        </div>
      </div>
    </template>
  </div>
</template>
