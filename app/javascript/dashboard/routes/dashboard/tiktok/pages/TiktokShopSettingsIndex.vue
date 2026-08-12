<script setup>
import { ref, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useTiktokShopsStore } from 'dashboard/stores/tiktok/shops';
import { useTiktokDepartmentsStore } from 'dashboard/stores/tiktok/departments';
import Button from 'dashboard/components-next/button/Button.vue';

// TikTok 店铺设置：录入下拉的店铺主数据（新增 / 改名 / 停用 / 删除 / 归属部门）。
// 页面与侧栏入口按管理员/副管理员限定；写操作后端再校验。
const shopsStore = useTiktokShopsStore();
const departmentsStore = useTiktokDepartmentsStore();
const shops = ref([]);
const departments = ref([]);
const loading = ref(false);
const editing = ref({ id: null, name: '', region: '' });
const draft = ref({ name: '', region: '' });

const load = async () => {
  loading.value = true;
  try {
    shops.value = await shopsStore.get();
  } catch (e) {
    useAlert(e?.message || '加载失败');
  } finally {
    loading.value = false;
  }
};

const loadDepartments = async () => {
  try {
    departments.value = await departmentsStore.get();
  } catch (e) {
    departments.value = [];
  }
};

const run = async (fn, okMsg) => {
  try {
    await fn();
    if (okMsg) useAlert(okMsg);
  } catch (e) {
    useAlert(e?.message || '操作失败');
  }
};

const setDepartment = (shop, departmentId) =>
  run(() =>
    shopsStore.update({ id: shop.id, departmentId: departmentId || null })
  );

const addShop = () => {
  const name = draft.value.name.trim();
  if (!name) return;
  run(async () => {
    await shopsStore.create({ name, region: draft.value.region.trim() });
    draft.value = { name: '', region: '' };
  }, '已新增店铺');
};

const startEdit = shop => {
  editing.value = { id: shop.id, name: shop.name, region: shop.region || '' };
};

const cancelEdit = () => {
  editing.value = { id: null, name: '', region: '' };
};

const saveEdit = () => {
  const { id, name, region } = editing.value;
  const trimmed = name.trim();
  editing.value = { id: null, name: '', region: '' };
  if (!trimmed) return;
  run(() => shopsStore.update({ id, name: trimmed, region: region.trim() }));
};

const toggleActive = shop =>
  run(() => shopsStore.update({ id: shop.id, active: !shop.active }));

const remove = shop => {
  // eslint-disable-next-line no-alert
  if (
    !window.confirm(
      `确定删除店铺「${shop.name}」？（已有销售记录的店铺请改为停用）`
    )
  ) {
    return;
  }
  run(() => shopsStore.delete(shop.id), '已删除');
};

onMounted(() => {
  load();
  loadDepartments();
});
</script>

<template>
  <div class="flex flex-col w-full h-full overflow-auto">
    <div class="w-full max-w-3xl px-8 py-6 mx-auto">
      <h1 class="mb-1 text-xl font-semibold text-n-slate-12">店铺设置</h1>
      <p class="mb-5 text-sm text-n-slate-11">
        维护 TikTok
        店铺（录入日报时的店铺下拉来源）。停用后不再出现在下拉，但保留历史数据。
      </p>

      <div v-if="loading" class="py-10 text-sm text-center text-n-slate-10">
        加载中…
      </div>

      <template v-else>
        <div
          class="overflow-hidden border rounded-xl border-white/60 bg-n-solid-1/75 backdrop-blur-xl"
        >
          <div
            v-for="shop in shops"
            :key="shop.id"
            class="flex items-center gap-3 px-4 border-b h-14 last:border-b-0 border-n-weak"
          >
            <template v-if="editing.id === shop.id">
              <input
                v-model="editing.name"
                class="flex-1 h-8 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
                placeholder="店铺名称"
                @keyup.enter="saveEdit"
              />
              <input
                v-model="editing.region"
                class="w-24 h-8 pl-2 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
                placeholder="地区"
                @keyup.enter="saveEdit"
              />
              <Button
                color="iris"
                size="sm"
                label="保存"
                class="shrink-0"
                @click="saveEdit"
              />
              <Button
                variant="ghost"
                color="slate"
                size="sm"
                label="取消"
                class="shrink-0"
                @click="cancelEdit"
              />
            </template>
            <template v-else>
              <span
                class="text-sm font-medium truncate w-44 shrink-0"
                :class="
                  shop.active
                    ? 'text-n-slate-12'
                    : 'text-n-slate-9 line-through'
                "
              >
                {{ shop.name }}
              </span>
              <span
                v-if="shop.region"
                class="w-12 text-center shrink-0 px-1.5 py-0.5 text-xs rounded text-n-slate-11 bg-n-alpha-2"
              >
                {{ shop.region }}
              </span>
              <span class="flex-1" />
              <select
                :value="shop.departmentId || ''"
                class="w-40 h-8 pl-2 !pr-7 text-xs rounded-lg shrink-0 reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-11"
                title="归属部门"
                @change="setDepartment(shop, $event.target.value)"
              >
                <option value="">未分配部门</option>
                <option v-for="d in departments" :key="d.id" :value="d.id">
                  {{ d.name }}
                </option>
              </select>
              <Button
                variant="ghost"
                color="slate"
                size="xs"
                icon="i-lucide-pencil"
                @click="startEdit(shop)"
              />
              <Button
                variant="ghost"
                color="slate"
                size="xs"
                :icon="shop.active ? 'i-lucide-eye' : 'i-lucide-eye-off'"
                @click="toggleActive(shop)"
              />
              <Button
                variant="ghost"
                color="ruby"
                size="xs"
                icon="i-lucide-trash-2"
                @click="remove(shop)"
              />
            </template>
          </div>

          <p
            v-if="!shops.length"
            class="py-8 text-sm text-center text-n-slate-10"
          >
            还没有店铺，先在下方新增。
          </p>
        </div>

        <!-- 新增店铺 -->
        <div class="flex items-center gap-2 mt-4">
          <input
            v-model="draft.name"
            class="flex-1 h-10 pl-3 !pr-8 text-sm rounded-lg reset-base mb-0 outline outline-1 outline-n-weak focus:outline-n-brand bg-n-solid-1 text-n-slate-12"
            placeholder="新增店铺名称（如 KidzTab PH）"
            @keyup.enter="addShop"
          />
          <input
            v-model="draft.region"
            class="w-28 h-10 pl-3 !pr-8 text-sm rounded-lg shrink-0 reset-base mb-0 outline outline-1 outline-n-weak bg-n-solid-1 text-n-slate-12"
            placeholder="地区（选填）"
            @keyup.enter="addShop"
          />
          <Button
            color="iris"
            icon="i-lucide-plus"
            label="添加"
            class="shrink-0"
            @click="addShop"
          />
        </div>
      </template>
    </div>
  </div>
</template>
