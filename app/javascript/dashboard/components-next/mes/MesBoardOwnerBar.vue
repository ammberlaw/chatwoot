<script setup>
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useCrmRole } from 'dashboard/composables/useCrmRole';
import { useMesBoardOwners } from 'dashboard/composables/useMesBoardOwners';

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

const current = computed(
  () =>
    ownersByKey.value[props.boardKey] || { managerIds: [], managerNames: [] }
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
    await saveOwners(props.boardKey, draftIds.value);
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
    <span class="text-xs font-medium text-n-slate-11">阶段负责人</span>
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
      ref="dialogRef"
      confirm-button-color="iris"
      title="设置阶段负责人"
      :is-loading="saving"
      @confirm="save"
    >
      <div class="flex flex-col gap-3">
        <p class="text-xs text-n-slate-10">
          勾选的成员会作为本阶段负责人展示，业务据此知道该找谁。
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
