<script setup>
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useMapGetter } from 'dashboard/composables/store';
import TeamsAPI from 'dashboard/api/crm/teams';
import AgentAPI from 'dashboard/api/agents';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';

const { isAdmin } = useAdmin();
const currentUser = useMapGetter('getCurrentUser');
const canManage = computed(
  () => isAdmin.value || currentUser.value?.crm_role === 'deputy_admin'
);

const L = {
  header: 'CRM 团队',
  hint: '销售团队分组：设组长、分配组员；团队看板 / 客户与商机的团队筛选、订单归队都以此为准。',
  addTeam: '新建团队',
  editTeam: '编辑团队',
  remove: '解散团队',
  empty: '还没有团队，点「新建团队」开始',
  readonlyEmpty: '你还未加入任何团队',
  nameLabel: '团队名称',
  namePlaceholder: '如：销售一部',
  descLabel: '团队描述（可选）',
  descPlaceholder: '一句话说明团队定位',
  leadLabel: '组长',
  noLead: '未设置',
  membersLabel: '组员',
  membersHint:
    '一名成员同时只能属于一个团队；勾选已在其他团队的成员即视为转队。',
  searchPlaceholder: '搜索成员姓名/邮箱',
  memberCountSuffix: '人',
  leadBadge: '组长',
  otherTeamPrefix: '现属：',
  deleteConfirm: '解散该团队？组员将变为未分队（客户/订单数据不受影响）。',
  nameRequired: '请填写团队名称',
  saved: '已保存',
  error: '操作失败',
};

const teams = ref([]);
const agents = ref([]);
const loading = ref(true);

const fetchTeams = async () => {
  try {
    const { data } = await TeamsAPI.get();
    teams.value = data.payload || [];
  } finally {
    loading.value = false;
  }
};

const fetchAgents = async () => {
  try {
    const { data } = await AgentAPI.get();
    agents.value = data || [];
  } catch {
    agents.value = [];
  }
};

const agentName = id => agents.value.find(a => a.id === id)?.name || '';
const teamOfAgent = id =>
  teams.value.find(team => (team.member_ids || []).includes(id));

// ---- 新建 / 编辑 ----
const dialogRef = ref(null);
const editingId = ref(null);
const form = ref({ name: '', description: '', teamLeadId: '', memberIds: [] });
const memberSearch = ref('');

const filteredAgents = computed(() => {
  const keyword = memberSearch.value.trim().toLowerCase();
  if (!keyword) return agents.value;
  return agents.value.filter(a =>
    `${a.name} ${a.email}`.toLowerCase().includes(keyword)
  );
});

// 组长从勾选的组员里选。
const leadOptions = computed(() => [
  { value: '', label: L.noLead },
  ...form.value.memberIds.map(id => ({
    value: String(id),
    label: agentName(id),
  })),
]);

const openAdd = () => {
  editingId.value = null;
  form.value = { name: '', description: '', teamLeadId: '', memberIds: [] };
  memberSearch.value = '';
  dialogRef.value?.open();
};

const openEdit = team => {
  editingId.value = team.id;
  form.value = {
    name: team.name,
    description: team.description || '',
    teamLeadId: team.team_lead_id ? String(team.team_lead_id) : '',
    memberIds: [...(team.member_ids || [])],
  };
  memberSearch.value = '';
  dialogRef.value?.open();
};

const toggleMember = id => {
  const list = form.value.memberIds;
  const index = list.indexOf(id);
  if (index >= 0) {
    list.splice(index, 1);
    if (form.value.teamLeadId === String(id)) form.value.teamLeadId = '';
  } else {
    list.push(id);
  }
};

const saveTeam = async () => {
  const name = form.value.name.trim();
  if (!name) {
    useAlert(L.nameRequired);
    return;
  }
  const payload = {
    team: {
      name,
      description: form.value.description.trim(),
      team_lead_id: form.value.teamLeadId
        ? Number(form.value.teamLeadId)
        : null,
      member_ids: form.value.memberIds,
    },
  };
  try {
    if (editingId.value) await TeamsAPI.update(editingId.value, payload);
    else await TeamsAPI.create(payload);
    dialogRef.value?.close();
    await fetchTeams();
    useAlert(L.saved);
  } catch {
    useAlert(L.error);
  }
};

const removeTeam = async team => {
  // eslint-disable-next-line no-alert
  if (!window.confirm(L.deleteConfirm)) return;
  try {
    await TeamsAPI.delete(team.id);
    await fetchTeams();
    useAlert(L.saved);
  } catch {
    useAlert(L.error);
  }
};

const initial = name => (name || '?').trim().charAt(0).toUpperCase();

onMounted(() => {
  fetchTeams();
  fetchAgents();
});
</script>

<template>
  <div
    class="flex flex-col w-full h-full overflow-hidden bg-n-solid-1/40 backdrop-blur-2xl backdrop-saturate-150 rounded-3xl border border-white/50 shadow-lg shadow-n-iris-9/5"
  >
    <div
      class="flex items-center justify-between flex-shrink-0 px-6 py-4 border-b border-n-weak"
    >
      <div>
        <h1 class="text-lg font-semibold text-n-slate-12">{{ L.header }}</h1>
        <p class="mt-0.5 text-xs text-n-slate-10">{{ L.hint }}</p>
      </div>
      <Button
        v-if="canManage"
        :label="L.addTeam"
        icon="i-lucide-plus"
        size="sm"
        color="iris"
        @click="openAdd"
      />
    </div>

    <div class="flex-1 p-6 overflow-y-auto">
      <div v-if="loading" class="p-8 text-sm text-center text-n-slate-11">
        {{ '…' }}
      </div>
      <div
        v-else-if="!teams.length"
        class="flex flex-col items-center justify-center gap-3 py-24 text-n-slate-10"
      >
        <Icon icon="i-lucide-users-round" class="size-12 opacity-40" />
        <p class="text-sm">{{ canManage ? L.empty : L.readonlyEmpty }}</p>
      </div>
      <div v-else class="grid grid-cols-1 gap-4 lg:grid-cols-2 2xl:grid-cols-3">
        <div
          v-for="team in teams"
          :key="team.id"
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
                  {{ team.name }}
                </h2>
                <span
                  class="flex-shrink-0 px-1.5 py-0.5 text-[10px] leading-none rounded-full bg-n-alpha-2 text-n-slate-11 tabular-nums"
                >
                  {{ (team.members || []).length }}{{ L.memberCountSuffix }}
                </span>
              </div>
              <p class="mt-0.5 text-xs truncate text-n-slate-10">
                {{ team.description || '—' }}
              </p>
            </div>
            <template v-if="canManage">
              <button
                class="flex items-center justify-center flex-shrink-0 rounded-md opacity-0 size-7 group-hover:opacity-100 text-n-slate-10 hover:text-n-iris-11 hover:bg-n-alpha-2"
                :title="L.editTeam"
                @click="openEdit(team)"
              >
                <Icon icon="i-lucide-pencil" class="size-4" />
              </button>
              <button
                class="flex items-center justify-center flex-shrink-0 rounded-md opacity-0 size-7 group-hover:opacity-100 text-n-slate-10 hover:text-n-ruby-11 hover:bg-n-alpha-2"
                :title="L.remove"
                @click="removeTeam(team)"
              >
                <Icon icon="i-lucide-trash-2" class="size-4" />
              </button>
            </template>
          </div>

          <div class="flex flex-wrap gap-1.5">
            <span
              v-for="member in team.members || []"
              :key="member.id"
              class="inline-flex items-center gap-1.5 pl-1 pr-2 py-1 text-xs rounded-full"
              :class="
                member.id === team.team_lead_id
                  ? 'bg-n-iris-3 text-n-iris-12'
                  : 'bg-n-alpha-1 text-n-slate-11'
              "
            >
              <span
                class="flex items-center justify-center rounded-full size-4 text-[9px] font-medium"
                :class="
                  member.id === team.team_lead_id
                    ? 'bg-n-iris-9 text-white'
                    : 'bg-n-alpha-2 text-n-slate-11'
                "
              >
                {{ initial(member.name) }}
              </span>
              {{ member.name }}
              <span
                v-if="member.id === team.team_lead_id"
                class="text-[9px] font-medium text-n-iris-11"
              >
                {{ L.leadBadge }}
              </span>
            </span>
            <span
              v-if="!(team.members || []).length"
              class="text-xs text-n-slate-9"
            >
              {{ L.readonlyEmpty.replace('你', '') }}
            </span>
          </div>
        </div>
      </div>
    </div>

    <Dialog
      ref="dialogRef"
      :title="editingId ? L.editTeam : L.addTeam"
      confirm-button-color="iris"
      @confirm="saveTeam"
    >
      <div class="flex flex-col gap-4">
        <Input
          v-model="form.name"
          :label="L.nameLabel"
          :placeholder="L.namePlaceholder"
        />
        <Input
          v-model="form.description"
          :label="L.descLabel"
          :placeholder="L.descPlaceholder"
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
              v-for="agent in filteredAgents"
              :key="agent.id"
              class="flex items-center gap-2.5 px-2 py-1.5 rounded-md cursor-pointer hover:bg-n-alpha-1"
            >
              <input
                type="checkbox"
                class="accent-n-brand"
                :checked="form.memberIds.includes(agent.id)"
                @change="toggleMember(agent.id)"
              />
              <span class="flex-1 min-w-0">
                <span class="block text-sm truncate text-n-slate-12">
                  {{ agent.name }}
                </span>
                <span class="block text-xs truncate text-n-slate-10">
                  {{ agent.email }}
                </span>
              </span>
              <span
                v-if="
                  teamOfAgent(agent.id) &&
                  teamOfAgent(agent.id).id !== editingId
                "
                class="flex-shrink-0 px-1.5 py-0.5 text-[10px] rounded-full bg-n-amber-3 text-n-amber-12"
              >
                {{ L.otherTeamPrefix }}{{ teamOfAgent(agent.id).name }}
              </span>
            </label>
          </div>
        </div>
        <div>
          <label class="block mb-0.5 text-heading-3 text-n-slate-12">
            {{ L.leadLabel }}
          </label>
          <Select v-model="form.teamLeadId" :options="leadOptions" />
        </div>
      </div>
    </Dialog>
  </div>
</template>
