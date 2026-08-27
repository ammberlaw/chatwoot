<script setup>
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useCrmRole } from 'dashboard/composables/useCrmRole';
import {
  useMesBoardOwners,
  boardOwnerKey,
} from 'dashboard/composables/useMesBoardOwners';
import {
  useMesProductLine,
  productLineLabel,
} from 'dashboard/composables/useMesProductLine';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const props = defineProps({
  boardKey: { type: String, required: true },
});

const { isAdmin, isCrmDeputyAdmin } = useCrmRole();
const canManage = computed(() => isAdmin.value || isCrmDeputyAdmin.value);

const { ownersByKey, members, loadOwners, ensureMembers, saveOwners } =
  useMesBoardOwners();
// 阶段负责人按当前切换的产品线配置/展示（全部产线 = 通用负责人）。
const { activeProductLine } = useMesProductLine();
const lineLabel = computed(
  () => productLineLabel(activeProductLine.value) || '全部产线'
);

const current = computed(
  () =>
    ownersByKey.value[
      boardOwnerKey(props.boardKey, activeProductLine.value)
    ] || {
      managerIds: [],
      managerNames: [],
    }
);

const dialogRef = ref(null);
const draftIds = ref([]);
const search = ref('');
const saving = ref(false);
const candidates = computed(() => {
  const kw = search.value.trim().toLowerCase();
  if (!kw) return members.value;
  return members.value.filter(m =>
    `${m.name} ${m.email}`.toLowerCase().includes(kw)
  );
});

const openDialog = async () => {
  await ensureMembers();
  draftIds.value = [...current.value.managerIds];
  search.value = '';
  dialogRef.value?.open();
};
const toggle = userId => {
  const idx = draftIds.value.indexOf(userId);
  if (idx >= 0) draftIds.value.splice(idx, 1);
  else draftIds.value.push(userId);
};
const save = async () => {
  saving.value = true;
  try {
    await saveOwners(props.boardKey, draftIds.value, activeProductLine.value);
    dialogRef.value?.close();
    useAlert('负责人已更新');
  } catch {
    useAlert('保存失败');
  } finally {
    saving.value = false;
  }
};

onMounted(loadOwners);
</script>

<template>
  <div
    class="flex flex-wrap items-center gap-2 px-6 py-2 border-b border-n-weak bg-n-alpha-1/40"
  >
    <span class="text-xs font-medium text-n-slate-11">
      阶段负责人
      <span class="text-n-iris-11">· {{ lineLabel }}</span>
    </span>
    <template v-if="current.managerNames.length">
      <span
        v-for="name in current.managerNames"
        :key="name"
        class="inline-flex items-center gap-1 px-2 py-0.5 text-xs rounded-full bg-n-iris-3 text-n-iris-12"
      >
        <span class="i-lucide-user-round size-3" />
        {{ name }}
      </span>
    </template>
    <span v-else class="text-xs text-n-slate-10">未设置</span>
    <Button
      v-if="canManage"
      size="xs"
      variant="ghost"
      color="slate"
      icon="i-lucide-pencil"
      label="设置负责人"
      @click="openDialog"
    />

    <Dialog
      :dismissible="false"
      ref="dialogRef"
      confirm-button-color="iris"
      :title="`设置阶段负责人 · ${lineLabel}`"
      :is-loading="saving"
      @confirm="save"
    >
      <div class="flex flex-col gap-3">
        <p class="text-xs text-n-slate-10">
          正在设置
          <b class="text-n-iris-11">{{ lineLabel }}</b>
          的本阶段负责人：该产品线的单进到此阶段时，只通知这些人、只进他们的待办。
          <template v-if="activeProductLine">
            未单独配置该线时，回落到「全部产线」的通用负责人。
          </template>
        </p>
        <Input v-model="search" placeholder="搜索成员姓名 / 邮箱" />
        <div
          class="flex flex-col gap-1 p-2 overflow-y-auto border rounded-lg max-h-64 border-n-weak"
        >
          <label
            v-for="m in candidates"
            :key="m.user_id"
            class="flex items-center gap-2.5 px-2 py-1.5 rounded-md cursor-pointer hover:bg-n-alpha-1"
          >
            <input
              type="checkbox"
              class="accent-n-brand"
              :checked="draftIds.includes(m.user_id)"
              @change="toggle(m.user_id)"
            />
            <span class="flex-1 min-w-0">
              <span class="block text-sm truncate text-n-slate-12">
                {{ m.name }}
              </span>
              <span class="block text-xs truncate text-n-slate-10">
                {{ m.email }}
              </span>
            </span>
          </label>
        </div>
      </div>
    </Dialog>
  </div>
</template>
