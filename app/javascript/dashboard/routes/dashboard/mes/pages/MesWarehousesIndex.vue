<script setup>
import { ref, computed, reactive, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useMesWarehousesStore } from 'dashboard/stores/mes/warehouses';

import Button from 'dashboard/components-next/button/Button.vue';
import { useMesRole } from 'dashboard/composables/useMesRole';
import Input from 'dashboard/components-next/input/Input.vue';
import SelectCard from 'dashboard/components-next/select/SelectCard.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const store = useMesWarehousesStore();
const { mesCan } = useMesRole();
const records = computed(() => store.getRecords);
const isFetching = computed(() => store.getUIFlags.fetchingList);
const saving = computed(() => store.getUIFlags.creatingItem);

const KINDS = [
  { value: 'RAW', label: '原料仓' },
  { value: 'WIP', label: '在制品仓' },
  { value: 'FINISHED', label: '成品仓' },
  { value: 'SCRAP', label: '废料仓' },
];
const kindLabel = v => KINDS.find(k => k.value === v)?.label || '—';

const dialogRef = ref(null);
const form = reactive({ code: '', name: '', kind: 'RAW' });
const invalid = computed(() => !form.code.trim() || !form.name.trim());

const openCreate = () => {
  Object.assign(form, { code: '', name: '', kind: 'RAW' });
  dialogRef.value?.open();
};
const submit = async () => {
  if (invalid.value) return;
  const ok = await store.create({ ...form });
  if (ok) {
    useAlert(`已新增仓库 ${ok.name}`);
    dialogRef.value?.close();
  }
};

onMounted(() => store.get());
</script>

<template>
  <div class="flex flex-col w-full h-full">
    <div class="flex items-center justify-between px-4 py-3 sm:px-6 sm:py-4">
      <h1 class="text-xl font-semibold text-n-slate-12">仓库</h1>
      <Button
        v-if="mesCan('master')"
        label="新增仓库"
        color="iris"
        size="sm"
        @click="openCreate"
      />
    </div>

    <div class="flex-1 min-h-0 px-4 pb-4 overflow-auto sm:px-6 sm:pb-6">
      <div v-if="isFetching" class="py-10 text-center text-n-slate-11">
        加载中…
      </div>
      <template v-else>
        <div class="flex flex-col gap-2 md:hidden">
          <div
            v-for="w in records"
            :key="w.id"
            class="p-3 border rounded-xl border-white/60 bg-n-solid-1/75 backdrop-blur-xl active:bg-n-alpha-1"
          >
            <div class="flex items-center gap-2">
              <span class="font-medium text-n-slate-12 truncate">{{
                w.name
              }}</span>
              <span
                class="shrink-0 text-xs px-2 py-0.5 rounded-md bg-n-alpha-1 text-n-slate-11"
                >{{ kindLabel(w.kind) }}</span
              >
            </div>
            <div class="mt-1 text-xs text-n-slate-11">编码：{{ w.code }}</div>
          </div>
        </div>
        <table class="hidden md:table w-full text-sm">
          <thead>
            <tr class="text-left text-n-slate-11 border-b border-n-weak">
              <th class="px-3 py-3 font-medium">编码</th>
              <th class="px-3 py-3 font-medium">名称</th>
              <th class="px-3 py-3 font-medium">类型</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="w in records" :key="w.id" class="border-b border-n-weak">
              <td class="px-3 py-3 text-n-slate-11">{{ w.code }}</td>
              <td class="px-3 py-3 font-medium text-n-slate-12">
                {{ w.name }}
              </td>
              <td class="px-3 py-3 text-n-slate-11">{{ kindLabel(w.kind) }}</td>
            </tr>
          </tbody>
        </table>
      </template>
    </div>

    <Dialog
      ref="dialogRef"
      width="lg"
      confirm-button-color="iris"
      title="新增仓库"
      :is-loading="saving"
      :disable-confirm-button="invalid"
      @confirm="submit"
    >
      <div class="flex flex-col gap-4">
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              编码 <span class="text-n-ruby-11">*</span>
            </label>
            <Input v-model="form.code" autofocus />
          </div>
          <div class="flex flex-col gap-1">
            <label class="text-heading-3 text-n-slate-12">
              名称 <span class="text-n-ruby-11">*</span>
            </label>
            <Input v-model="form.name" />
          </div>
        </div>
        <div class="flex flex-col gap-1">
          <label class="text-heading-3 text-n-slate-12">类型</label>
          <SelectCard
            size="form"
            :model-value="form.kind"
            :options="KINDS"
            @update:model-value="v => (form.kind = v)"
          />
        </div>
      </div>
    </Dialog>
  </div>
</template>
