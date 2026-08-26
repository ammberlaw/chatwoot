// ERP 的文件下载统一走这里。
//
// ⚠️ 不能用 window.open(接口地址)：Chatwoot 的接口认证靠 access-token 请求头（不是 Cookie），
// 新标签页直接开会 401。必须用带认证的 axios 取 blob，再本地造链接触发下载。
export const downloadBlob = (data, filename) => {
  const url = window.URL.createObjectURL(new Blob([data]));
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  link.click();
  window.URL.revokeObjectURL(url);
};
