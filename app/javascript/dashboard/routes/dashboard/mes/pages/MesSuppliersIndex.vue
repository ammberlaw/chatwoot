<script setup>
import { ref, computed, reactive, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useMesSuppliersStore } from 'dashboard/stores/mes/suppliers';

import Button from 'dashboard/components-next/button/Button.vue';
import { useMesRole } from 'dashboard/composables/useMesRole';
import Input from 'dashboard/components-next/input/Input.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const store = useMesSuppliersStore();
const { mesCan } = useMesRole();
const records = computed(() => store.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);
const saving = computed(() => store.getUIFlags.creatingItem);

const dialogRef = ref(null);
const form = reactive({
  name: '',
  contactName: '',
  phone: '',
  email: '',
  address: '',
  remark: '',
});
const invalid = computed(() => !form.name.trim());

const openCreate = () => {
  Object.assign(form, {
    name: '',
    contactName: '',
    phone: '',
    email: '',
    address: '',
    remark: '',
  });
  dialogRef.value?.open();
};
const submit = async () => {
  if (invalid.value) return;
  const ok = await store.create({ ...form });
  if (ok) {
    useAlert(`已新增供应商 ${ok.supplierNo}`);
    dialogRef.value?.close();
  }
};

onMounted(() => store.get());
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div class="flex items-center justify-between px-6 py-4">
      <h1 class="text-xl font-semibold text-n-slate-12">供应商</h1>
      <Button v-if="mesCan('master')" label="新增供应商" color="iris" size="sm" @click="openCreate" />
    </div>

    <div class="flex-1 min-h-0 px-6 pb-6 overflow-auto">
      <div v-if="isFetching" class="py-10 text-center text-n-slate-11">加载中…</div>
      <table v-else class="w-full text-sm">
        <thead>
          <tr class="text-left text-n-slate-11 border-b border-n-weak">
            <th class="px-3 py-3 font-medium">编号</th>
            <th class="px-3 py-3 font-medium">名称</th>
            <th class="px-3 py-3 font-medium">联系人</th>
            <th class="px-3 py-3 font-medium">电话</th>
            <th class="px-3 py-3 font-medium">邮箱</th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="s in records"
            :key="s.id"
            class="border-b border-n-weak"
          >
            <td class="px-3 py-3 text-n-slate-11">{{ s.supplierNo }}</td>
            <td class="px-3 py-3 font-medium text-n-slate-12">{{ s.name }}</td>
            <td class="px-3 py-3 text-n-slate-11">{{ s.contactName || '—' }}</td>
            <td class="px-3 py-3 text-n-slate-11">{{ s.phone || '—' }}</td>
            <td class="px-3 py-3 text-n-slate-11">{{ s.email || '—' }}</td>
          </tr>
          <tr v-if="!records.length">
            <td colspan="5" class="px-3 py-10 text-center text-n-slate-11">
              还没有供应商。
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <Dialog
      ref="dialogRef"
      width="lg"
      confirm-button-color="iris"
      title="新增供应商"
      :is-loading="saving"
      :disable-confirm-button="invalid"
      @confirm="submit"
    >
      <div class="flex flex-col gap-4">
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">
            名称 <span class="text-n-ruby-11">*</span>
          </label>
          <Input v-model="form.name" autofocus />
        </div>
        <div class="grid grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">联系人</label>
            <Input v-model="form.contactName" />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">电话</label>
            <Input v-model="form.phone" />
          </div>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">邮箱</label>
          <Input v-model="form.email" />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">地址</label>
          <Input v-model="form.address" />
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">备注</label>
          <Input v-model="form.remark" />
        </div>
      </div>
    </Dialog>
  </div>
</template>
