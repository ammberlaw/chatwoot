import { defineStore } from 'pinia';
import { ref } from 'vue';
import { loadCreds, signIn, signOut } from '@/api/client';

export const useAuthStore = defineStore('auth', () => {
  const user = ref(null);
  const accountId = ref(null);
  const ready = ref(false);

  const restore = async () => {
    const c = await loadCreds();
    if (c) {
      user.value = c.user || null;
      accountId.value = c.user?.account_id || c.user?.accounts?.[0]?.id || null;
    }
    ready.value = true;
    return !!c;
  };

  const login = async (email, password, revoke = {}) => {
    const c = await signIn(email, password, revoke);
    user.value = c.user;
    accountId.value = c.user?.account_id || c.user?.accounts?.[0]?.id || null;
  };

  const logout = async () => {
    await signOut();
    user.value = null;
    accountId.value = null;
  };

  return { user, accountId, ready, restore, login, logout };
});
