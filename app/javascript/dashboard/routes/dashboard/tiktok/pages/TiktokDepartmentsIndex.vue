<script setup>
import { ref, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useTiktokDepartmentsStore } from 'dashboard/stores/tiktok/departments';
import MembersAPI from 'dashboard/api/crm/members';
import Button from 'dashboard/components-next/button/Button.vue';

// TikTok 部门管理（团队式：负责人+成员）。仅管理员/副管理员。
// 店铺归属在「店铺设置」里分配，这里只读展示。
const store = useTiktokDepartmentsStore();
const departments = ref([]);
const members = ref([]); // [{ userId, name }]
const loading = ref(false);
const draftName = ref('');
const draftLeader = ref('');

const memberName = id =>
  members.value.find(m => m.userId === id)?.name || `#${id}`;

const load = async () => {
  loading.value = true;
  try {
    departments.value = await store.get();
  } catch (e) {
    useAlert(e?.message || '加载失败');
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
    }));
  } catch (e) {
    members.value = [];
  }
};

const run = async (fn, okMsg) => {
  try {
    await fn();
    await load();
    if (okMsg) useAlert(okMsg);
  } catch (e) {
    useAlert(e?.message || '操作失败');
  }
};

const addDepartment = () => {
  const name = draftName.value.trim();
  if (!name) return;
  run(async () => {
    await store.create({
      name,
      leaderId: draftLeader.value || null,
      memberIds: [],
    });
    draftName.value = '';
    draftLeader.value = '';
  }, '已新建部门');
};

const rename = dept => {
  // eslint-disable-next-line no-alert
  const name = window.prompt('部门名称', dept.name);
  if (!name || !name.trim() || name.trim() === dept.name) return;
  run(() => store.update({ id: dept.id, name: name.trim() }), '已重命名');
};

const setLeader = (dept, leaderId) =>
  run(() => store.update({ id: dept.id, leaderId: leaderId || null }));

const addMember = (dept, userId) => {
  if (!userId) return;
  const ids = [...new Set([...(dept.memberIds || []), Number(userId)])];
  run(() => store.update({ id: dept.id, memberIds: ids }));
};

const removeMember = (dept, userId) => {
  const ids = (dept.memberIds || []).filter(id => id !== userId);
  run(() => store.update({ id: dept.id, memberIds: ids }));
};

const remove = dept => {
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(
      `删除部门「${dept.name}」？成员与店铺归属会被释放（数据保留）。`
    )
  ) {
    return;
  }
  run(() => store.delete(dept.id), '已删除');
};

onMounted(() => {
  load();
  loadMembers();
});
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto">
    <div class="w-full max-w-3xl px-8 py-6 mx-auto">
      <h1 class="mb-1 text-xl font-semibold text-n-slate-12">TK 部门管理</h1>
      <p class="mb-5 text-sm text-n-slate-11">
        建部门、设负责人、拉成员。店铺归属在「店铺设置」里分配。负责人/成员只看本部门数据。
      </p>

      <!-- 新建部门 -->
      <div class="flex items-center gap-2 mb-6">
        <input
          v-model="draftName"
          class="flex-1 h-10 pl-3 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak focus:outline-n-brand bg-n-solid-1 text-n-slate-12"
          placeholder="新部门名称（如 菲律宾一组）"
          @keyup.enter="addDepartment"
        />
        <select
          v-model="draftLeader"
          class="w-44 h-10 pl-3 !pr-8 text-sm rounded-lg shrink-0 reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
        >
          <option value="">选负责人（可选）</option>
          <option v-for="m in members" :key="m.userId" :value="m.userId">
            {{ m.name }}
          </option>
        </select>
        <Button
          color="iris"
          icon="i-lucide-plus"
          label="新建"
          class="shrink-0"
          @click="addDepartment"
        />
      </div>

      <div v-if="loading" class="py-10 text-sm text-center text-n-slate-10">
        加载中…
      </div>

      <template v-else>
        <div class="flex flex-col gap-3">
          <div
            v-for="dept in departments"
            :key="dept.id"
            class="p-4 border rounded-xl border-white/60 bg-n-solid-1/75 backdrop-blur-xl"
          >
            <!-- 部门头 -->
            <div
              class="flex items-center gap-2 pb-3 mb-3 border-b border-n-weak"
            >
              <span class="text-sm font-semibold text-n-slate-12">
                {{ dept.name }}
              </span>
              <Button
                variant="ghost"
                color="slate"
                size="xs"
                icon="i-lucide-pencil"
                @click="rename(dept)"
              />
              <span class="flex-1" />
              <Button
                variant="ghost"
                color="ruby"
                size="xs"
                icon="i-lucide-trash-2"
                @click="remove(dept)"
              />
            </div>

            <!-- 负责人 -->
            <div class="grid grid-cols-[3rem_1fr] items-center gap-x-3 gap-y-3">
              <span class="text-xs text-n-slate-11">负责人</span>
              <select
                :value="dept.leaderId || ''"
                class="w-56 h-8 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
                @change="setLeader(dept, $event.target.value)"
              >
                <option value="">未指定</option>
                <option v-for="m in members" :key="m.userId" :value="m.userId">
                  {{ m.name }}
                </option>
              </select>

              <!-- 成员 -->
              <span class="pt-1.5 text-xs text-n-slate-11">成员</span>
              <div class="flex flex-wrap items-center gap-1.5">
                <span
                  v-for="id in dept.memberIds"
                  :key="id"
                  class="inline-flex items-center gap-1 pl-2 pr-1 py-1 text-xs rounded-md text-n-slate-12 bg-n-alpha-2"
                >
                  {{ memberName(id) }}
                  <button
                    class="flex text-n-slate-10 hover:text-n-ruby-11"
                    @click="removeMember(dept, id)"
                  >
                    <span class="i-lucide-x size-3" />
                  </button>
                </span>
                <select
                  value=""
                  class="w-32 h-7 pl-2 !pr-7 text-xs rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-11"
                  @change="
                    addMember(dept, $event.target.value);
                    $event.target.value = '';
                  "
                >
                  <option value="">+ 添加成员</option>
                  <option
                    v-for="m in members"
                    :key="m.userId"
                    :value="m.userId"
                  >
                    {{ m.name }}
                  </option>
                </select>
              </div>

              <!-- 店铺（只读） -->
              <span class="pt-1 text-xs text-n-slate-11">店铺</span>
              <div class="flex flex-wrap gap-1.5">
                <span
                  v-for="name in dept.shopNames"
                  :key="name"
                  class="px-2 py-0.5 text-xs rounded-md text-n-iris-11 bg-n-iris-3"
                >
                  {{ name }}
                </span>
                <span
                  v-if="!dept.shopNames || !dept.shopNames.length"
                  class="text-xs text-n-slate-9"
                >
                  未分配店铺（到「店铺设置」分配）
                </span>
              </div>
            </div>
          </div>

          <p
            v-if="!departments.length"
            class="py-8 text-sm text-center text-n-slate-10"
          >
            还没有部门，先在上方新建。
          </p>
        </div>
      </template>
    </div>
  </div>
</template>
