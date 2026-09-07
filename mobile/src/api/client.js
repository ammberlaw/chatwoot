import axios from 'axios';
import { Preferences } from '@capacitor/preferences';

// 三种情形：
//  1) 浏览器 dev  → 留空，走 vite 同源代理（见 vite.config.js）
//  2) 真机调试    → 构建时传 VITE_API_BASE=http://<Mac 局域网IP>:3001，连本机 dev 后端
//  3) 正式打包    → 生产域名
export const API_BASE =
  import.meta.env.VITE_API_BASE ||
  (import.meta.env.DEV ? '' : 'https://wintouchspace.com');

const TOKEN_KEY = 'wt_auth';

// 用 devise_token_auth 的 access-token/client/uid（连字符）。
// 不用 Chatwoot 的 api_access_token —— 生产 nginx 会丢带下划线的请求头。
let creds = null;

export const loadCreds = async () => {
  if (creds) return creds;
  const { value } = await Preferences.get({ key: TOKEN_KEY });
  creds = value ? JSON.parse(value) : null;
  return creds;
};

export const saveCreds = async next => {
  creds = next;
  if (next) {
    await Preferences.set({ key: TOKEN_KEY, value: JSON.stringify(next) });
  } else {
    await Preferences.remove({ key: TOKEN_KEY });
  }
};

export const http = axios.create({ baseURL: API_BASE, timeout: 20000 });

// 由 network store 注入，避免 api 层直接依赖 store
let onNetworkError = null;
let onNetworkOk = null;
export const setNetworkErrorHandler = (fail, ok) => {
  onNetworkError = fail;
  onNetworkOk = ok;
};

http.interceptors.request.use(async config => {
  const c = await loadCreds();
  if (c) {
    config.headers['access-token'] = c.accessToken;
    config.headers.client = c.client;
    config.headers.uid = c.uid;
  }
  return config;
});

// devise 每次响应可能轮换 token，需回写；401 视为登录失效
http.interceptors.response.use(
  res => {
    const t = res.headers['access-token'];
    if (t && creds) saveCreds({ ...creds, accessToken: t });
    if (typeof onNetworkOk === 'function') onNetworkOk();
    return res;
  },
  async err => {
    if (err.response?.status === 401) {
      await saveCreds(null);
    }
    // 没有 response = 请求根本没到服务器，按断网处理（供离线横幅使用）
    if (!err.response && typeof onNetworkError === 'function') {
      onNetworkError();
    }
    return Promise.reject(err);
  }
);

// revoke: {revoke_session_id} 或 {revoke_all_sessions:true}
// 后端 MAX_USER_SESSIONS 默认 25，达上限且 UA 含 'Mozilla'(WKWebView 也含)时返回 409 +
// 会话列表，要求先踢掉一个再登录。
export const signIn = async (email, password, revoke = {}) => {
  const res = await axios.post(`${API_BASE}/auth/sign_in`, {
    email,
    password,
    ...revoke,
  });
  const next = {
    accessToken: res.headers['access-token'],
    client: res.headers.client,
    uid: res.headers.uid,
    user: res.data?.data,
  };
  await saveCreds(next);
  return next;
};

export const signOut = () => saveCreds(null);

// 带本地缓存的 GET：成功则写缓存；失败(断网/超时)回落到上次缓存。
// 让 App 在飞行模式下仍能显示有意义的内容，而不是一片"加载失败"。
export const cachedGet = async (url, config = {}) => {
  const key = `cache:${url}:${JSON.stringify(config.params || {})}`;
  try {
    const res = await http.get(url, config);
    await Preferences.set({
      key,
      value: JSON.stringify({ data: res.data, at: Date.now() }),
    });
    return { data: res.data, fromCache: false, at: null };
  } catch (err) {
    const { value } = await Preferences.get({ key });
    if (!value) throw err;
    const cached = JSON.parse(value);
    return { data: cached.data, fromCache: true, at: cached.at };
  }
};
