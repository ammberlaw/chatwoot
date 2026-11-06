<script setup>
// 看板设置：目前只管「谁计入成交排行」。
// 名单只列 CRM 成员（crm=true，口径见 AccountUser#can_access_crm?）：车间、仓管、质检
// 这些岗位从不持有客户，摆进来只是让人在四十来个名字里找人更费劲。
// 为什么 CRM 成员里还要再勾一次：规则怎么写都有例外——副管兼跑业务要算、挂 manager 的
// 生产主管不算、建了号没人用的空号不算。与其堆条件，不如在这里勾。
// 勾选只影响「零成交的人要不要以 ¥0 留在榜上」；有订单的人数据来自真实单据，不受此开关影响。
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import MembersAPI from 'dashboard/api/crm/members';
import Input from 'dashboard/components-next/input/Input.vue';

const members = ref([]);
const loading = ref(false);
const savingId = ref(null);
const keyword = ref('');

const load = async () => {
  loading.value = true;
  try {
    const { data } = await MembersAPI.get({
      active: true,
      crm: true,
      per_page: 200,
    });
    members.value = data.payload || [];
  } catch {
    members.value = [];
    useAlert('成员列表加载失败');
  } finally {
    loading.value = false;
  }
};

const visible = computed(() => {
  const kw = keyword.value.trim().toLowerCase();
  if (!kw) return members.value;
  return members.value.filter(m =>
    `${m.name} ${m.email || ''}`.toLowerCase().includes(kw)
  );
});

const pickedCount = computed(
  () => members.value.filter(m => m.in_sales_rank).length
);

const toggle = async (member, checked) => {
  savingId.value = member.id;
  try {
    const { data } = await MembersAPI.update(member.id, {
      member: { in_sales_rank: checked },
    });
    Object.assign(member, data);
  } catch {
    useAlert('保存失败');
    load();
  } finally {
    savingId.value = null;
  }
};

const roleLabel = m => {
  if (m.is_admin) return '管理员';
  return (
    {
      deputy_admin: '副管理员',
      manager: '部门负责人',
      sales: '业务员',
      hr: '人事',
    }[m.crm_role] || '成员'
  );
};

onMounted(load);
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-hidden bg-n-solid-1">
    <header class="px-5 py-6 sm:px-8">
      <h1 class="text-heading-1 text-n-slate-12">看板设置</h1>
    </header>

    <div class="px-5 sm:px-8">
      <h2 class="text-heading-3 text-n-slate-12">计入成交排行的人</h2>
      <p class="mt-1 text-label-small text-n-slate-11">
        勾上的人当期没成交也会以 ¥0 留在排行里；有订单的人不受此开关影响。
      </p>
      <div class="flex items-center gap-2 mt-4">
        <Input v-model="keyword" placeholder="搜成员" class="w-60" />
        <span class="text-label-small text-n-slate-11">
          已选 {{ pickedCount }} 人
        </span>
      </div>
    </div>

    <div class="flex-1 px-5 py-4 overflow-auto sm:px-8">
      <p v-if="loading" class="py-10 text-sm text-center text-n-slate-10">
        加载中…
      </p>
      <div v-else class="flex flex-col max-w-2xl gap-1">
        <label
          v-for="m in visible"
          :key="m.id"
          class="flex items-center gap-3 px-3 py-2 border rounded-lg cursor-pointer border-n-weak hover:bg-n-alpha-1"
        >
          <input
            type="checkbox"
            class="accent-n-iris-9"
            :checked="m.in_sales_rank"
            :disabled="savingId === m.id"
            @change="toggle(m, $event.target.checked)"
          />
          <span class="font-medium text-n-slate-12">{{ m.name }}</span>
          <span class="ml-auto text-label-small text-n-slate-10">
            {{ roleLabel(m) }}
          </span>
        </label>
      </div>
    </div>
  </div>
</template>
