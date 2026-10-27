<script setup>
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useTiktokDepartmentsStore } from 'dashboard/stores/tiktok/departments';
import MembersAPI from 'dashboard/api/crm/members';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';

// TikTok 部门管理（团队式：负责人+成员，卡片样式对齐 CRM 团队）。仅管理员/副管理员。
// 店铺归属在「店铺设置」里分配，这里只读展示。
const store = useTiktokDepartmentsStore();

const L = {
  header: 'TK 部门管理',
  hint: 'TikTok 店铺分组：设负责人、拉成员；负责人 / 成员只看本部门店铺的日报与利润。店铺归属在「店铺设置」里分配。',
  addDept: '新建部门',
  editDept: '编辑部门',
  remove: '删除部门',
  empty: '还没有部门，点「新建部门」开始',
  nameLabel: '部门名称',
  namePlaceholder: '如：菲律宾一组',
  leadLabel: '负责人',
  noLead: '未指定',
  membersLabel: '成员',
  membersHint:
    '一名成员同时只能属于一个部门；勾选已在其他部门的成员即视为转部门。',
  searchPlaceholder: '搜索成员姓名 / 邮箱',
  memberCountSuffix: '人',
  leadBadge: '负责人',
  otherDeptPrefix: '现属：',
  shopsLabel: '店铺',
  noShops: '未分配店铺（到「店铺设置」分配）',
  deleteConfirm: '删除部门「%s」？成员与店铺归属会被释放（数据保留）。',
  nameRequired: '请填写部门名称',
  saved: '已保存',
  error: '操作失败',
};

const departments = ref([]);
const members = ref([]); // [{ userId, name, email }]
const loading = ref(true);

const load = async () => {
  try {
    departments.value = await store.get();
  } catch (e) {
    useAlert(e?.message || L.error);
  } finally {
    loading.value = false;
  }
};

const loadMembers = async () => {
  try {
    const { data } = await MembersAPI.get();
    members.value = (data.payload || []).map(m => ({
      userId: m.user_id,
      name: m.name,
      email: m.email,
    }));
  } catch {
    members.value = [];
  }
};

// 某成员当前所属部门（用于弹窗里「现属：xx」提示）。
const deptOfMember = userId =>
  departments.value.find(d => (d.memberIds || []).includes(userId));

// ---- 新建 / 编辑 ----
const dialogRef = ref(null);
const editingId = ref(null);
const form = ref({ name: '', leaderId: '', memberIds: [] });
const memberSearch = ref('');

const filteredMembers = computed(() => {
  const keyword = memberSearch.value.trim().toLowerCase();
  if (!keyword) return members.value;
  return members.value.filter(m =>
    `${m.name} ${m.email}`.toLowerCase().includes(keyword)
  );
});

// 负责人从勾选的成员里选。
const leadOptions = computed(() => [
  { value: '', label: L.noLead },
  ...form.value.memberIds.map(id => ({
    value: String(id),
    label: members.value.find(m => m.userId === id)?.name || `#${id}`,
  })),
]);

const openAdd = () => {
  editingId.value = null;
  form.value = { name: '', leaderId: '', memberIds: [] };
  memberSearch.value = '';
  dialogRef.value?.open();
};

const openEdit = dept => {
  editingId.value = dept.id;
  form.value = {
    name: dept.name,
    leaderId: dept.leaderId ? String(dept.leaderId) : '',
    memberIds: [...(dept.memberIds || [])],
  };
  memberSearch.value = '';
  dialogRef.value?.open();
};

const toggleMember = id => {
  const list = form.value.memberIds;
  const index = list.indexOf(id);
  if (index >= 0) {
    list.splice(index, 1);
    if (form.value.leaderId === String(id)) form.value.leaderId = '';
  } else {
    list.push(id);
  }
};

const saveDept = async () => {
  const name = form.value.name.trim();
  if (!name) {
    useAlert(L.nameRequired);
    return;
  }
  const payload = {
    name,
    leaderId: form.value.leaderId ? Number(form.value.leaderId) : null,
    memberIds: form.value.memberIds,
  };
  try {
    if (editingId.value)
      await store.update({ id: editingId.value, ...payload });
    else await store.create(payload);
    dialogRef.value?.close();
    await load();
    useAlert(L.saved);
  } catch (e) {
    useAlert(e?.message || L.error);
  }
};

const removeDept = async dept => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(L.deleteConfirm.replace('%s', dept.name))) return;
  try {
    await store.delete(dept.id);
    await load();
    useAlert(L.saved);
  } catch (e) {
    useAlert(e?.message || L.error);
  }
};

const initial = name => (name || '?').trim().charAt(0).toUpperCase();

onMounted(() => {
  load();
  loadMembers();
});
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-hidden bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div
      class="flex items-start justify-between flex-shrink-0 gap-3 px-4 py-3 border-b sm:items-center sm:px-6 sm:py-4 border-n-weak [.theme-classic_&]:sm:!px-8 [.theme-classic_&]:flex-wrap [.theme-classic_&]:gap-3"
    >
      <div class="min-w-0">
        <h1 class="text-lg font-semibold text-n-slate-12 [.theme-classic_&]:!text-heading-1 [.theme-classic_&]:!font-semibold [.theme-classic_&]:!leading-8">{{ L.header }}</h1>
        <p class="mt-0.5 text-xs text-n-slate-10">{{ L.hint }}</p>
      </div>
      <Button
        :label="L.addDept"
        icon="i-lucide-plus"
        size="sm"
        color="iris"
        class="shrink-0"
        @click="openAdd"
      />
    </div>

    <div class="flex-1 p-4 overflow-y-auto sm:p-6">
      <div v-if="loading" class="p-8 text-sm text-center text-n-slate-11">
        {{ '…' }}
      </div>
      <div
        v-else-if="!departments.length"
        class="flex flex-col items-center justify-center gap-3 py-24 text-n-slate-10"
      >
        <Icon icon="i-lucide-users-round" class="size-12 opacity-40" />
        <p class="text-sm">{{ L.empty }}</p>
      </div>
      <div v-else class="grid grid-cols-1 gap-4 lg:grid-cols-2 2xl:grid-cols-3">
        <div
          v-for="dept in departments"
          :key="dept.id"
          class="flex flex-col gap-3 p-5 border shadow-sm rounded-2xl border-n-weak bg-n-solid-1 group"
        >
          <div class="flex items-start gap-3">
            <div
              class="flex items-center justify-center flex-shrink-0 rounded-xl size-10 bg-n-iris-3 text-n-iris-11"
            >
              <Icon icon="i-lucide-users-round" class="size-5" />
            </div>
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2">
                <h2 class="text-sm font-semibold truncate text-n-slate-12">
                  {{ dept.name }}
                </h2>
                <span
                  class="flex-shrink-0 px-1.5 py-0.5 text-[10px] leading-none rounded-full bg-n-alpha-2 text-n-slate-11 tabular-nums"
                >
                  {{ (dept.members || []).length }}{{ L.memberCountSuffix }}
                </span>
              </div>
            </div>
            <button
              class="flex items-center justify-center flex-shrink-0 rounded-md opacity-0 size-7 group-hover:opacity-100 text-n-slate-10 hover:text-n-iris-11 hover:bg-n-alpha-2"
              :title="L.editDept"
              @click="openEdit(dept)"
            >
              <Icon icon="i-lucide-pencil" class="size-4" />
            </button>
            <button
              class="flex items-center justify-center flex-shrink-0 rounded-md opacity-0 size-7 group-hover:opacity-100 text-n-slate-10 hover:text-n-ruby-11 hover:bg-n-alpha-2"
              :title="L.remove"
              @click="removeDept(dept)"
            >
              <Icon icon="i-lucide-trash-2" class="size-4" />
            </button>
          </div>

          <!-- 成员 -->
          <div class="flex flex-wrap gap-1.5">
            <span
              v-for="member in dept.members || []"
              :key="member.id"
              class="inline-flex items-center gap-1.5 pl-1 pr-2 py-1 text-xs rounded-full"
              :class="
                member.id === dept.leaderId
                  ? 'bg-n-iris-3 text-n-iris-12'
                  : 'bg-n-alpha-1 text-n-slate-11'
              "
            >
              <Avatar
                :name="member.name"
                :src="member.avatar_url || ''"
                :size="16"
                rounded-full
              />
              {{ member.name }}
              <span
                v-if="member.id === dept.leaderId"
                class="text-[9px] font-medium text-n-iris-11"
              >
                {{ L.leadBadge }}
              </span>
            </span>
            <span
              v-if="!(dept.members || []).length"
              class="text-xs text-n-slate-9"
            >
              还没有成员
            </span>
          </div>

          <!-- 店铺（只读） -->
          <div
            class="flex flex-wrap items-center gap-1.5 pt-3 border-t border-n-weak/60"
          >
            <span class="text-[10px] text-n-slate-9">{{ L.shopsLabel }}</span>
            <span
              v-for="name in dept.shopNames || []"
              :key="name"
              class="px-2 py-0.5 text-xs rounded-md text-n-iris-11 bg-n-iris-3"
            >
              {{ name }}
            </span>
            <span
              v-if="!(dept.shopNames || []).length"
              class="text-xs text-n-slate-9"
            >
              {{ L.noShops }}
            </span>
          </div>
        </div>
      </div>
    </div>

    <Dialog
      ref="dialogRef"
      :title="editingId ? L.editDept : L.addDept"
      confirm-button-color="iris"
      @confirm="saveDept"
    >
      <div class="flex flex-col gap-4">
        <Input
          v-model="form.name"
          :label="L.nameLabel"
          :placeholder="L.namePlaceholder"
        />
        <div>
          <label class="block mb-0.5 text-heading-3 text-n-slate-12">
            {{ L.membersLabel }}
          </label>
          <p class="mb-2 text-xs text-n-slate-10">{{ L.membersHint }}</p>
          <Input v-model="memberSearch" :placeholder="L.searchPlaceholder" />
          <div
            class="flex flex-col gap-1 p-2 mt-2 overflow-y-auto border rounded-lg max-h-48 border-n-weak"
          >
            <label
              v-for="m in filteredMembers"
              :key="m.userId"
              class="flex items-center gap-2.5 px-2 py-1.5 rounded-md cursor-pointer hover:bg-n-alpha-1"
            >
              <input
                type="checkbox"
                class="accent-n-brand"
                :checked="form.memberIds.includes(m.userId)"
                @change="toggleMember(m.userId)"
              />
              <span class="flex-1 min-w-0">
                <span class="block text-sm truncate text-n-slate-12">
                  {{ m.name }}
                </span>
                <span class="block text-xs truncate text-n-slate-10">
                  {{ m.email }}
                </span>
              </span>
              <span
                v-if="
                  deptOfMember(m.userId) &&
                  deptOfMember(m.userId).id !== editingId
                "
                class="flex-shrink-0 px-1.5 py-0.5 text-[10px] rounded-full bg-n-amber-3 text-n-amber-12"
              >
                {{ L.otherDeptPrefix }}{{ deptOfMember(m.userId).name }}
              </span>
            </label>
          </div>
        </div>
        <div>
          <label class="block mb-0.5 text-heading-3 text-n-slate-12">
            {{ L.leadLabel }}
          </label>
          <Select v-model="form.leaderId" :options="leadOptions" />
        </div>
      </div>
    </Dialog>
  </div>
</template>
