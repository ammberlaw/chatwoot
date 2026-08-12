/* global axios */

/**
 * Constants and Configuration
 */

// Version for the API endpoint.
const API_VERSION = 'v1';

// Default headers to be used in the axios request.
const HEADERS = {
  'Content-Type': 'multipart/form-data',
};

/**
 * Uploads a file to the server.
 *
 * This function sends a POST request to a given API endpoint and uploads the specified file.
 * The function uses FormData to wrap the file and axios to send the request.
 *
 * @param {File} file - The file to be uploaded. It should be a File object (typically coming from a file input element).
 * @param {string} accountId - The account ID.
 * @returns {Promise} A promise that resolves with the server's response when the upload is successful, or rejects if there's an error.
 */
export async function uploadFile(file, accountId) {
  if (!accountId) {
    accountId = window.location.pathname.split('/')[3];
  }

  // Append the file to the FormData instance under the key 'attachment'.
  let formData = new FormData();
  formData.append('attachment', file);

  const { data } = await axios.post(
    `/api/${API_VERSION}/accounts/${accountId}/upload`,
    formData,
    { headers: HEADERS }
  );

  return {
    fileUrl: data.file_url,
    blobKey: data.blob_key,
    blobId: data.blob_id,
  };
}

// data:URI 内联图 → File。很多客户端（含小满/Outlook）把图片误标成
// application/octet-stream，这里按 base64 头的魔数还原真实图片类型，
// 否则存进去的 blob content-type 不是 image/*，<img> 不渲染。
function dataUriToImageFile(dataUri) {
  const comma = dataUri.indexOf(',');
  if (comma < 0) return null;
  const b64 = dataUri.slice(comma + 1);
  let binary;
  try {
    binary = atob(b64);
  } catch {
    return null;
  }
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);

  const head = b64.slice(0, 12);
  let type = 'image/png';
  let ext = 'png';
  if (head.startsWith('/9j/')) {
    type = 'image/jpeg';
    ext = 'jpg';
  } else if (head.startsWith('R0lGOD')) {
    type = 'image/gif';
    ext = 'gif';
  } else if (head.startsWith('UklGR')) {
    type = 'image/webp';
    ext = 'webp';
  }
  return new File([bytes], `inline-image.${ext}`, { type });
}

/**
 * 把 markdown 正文里的 data:URI 内联图（base64）上传到存储、替换成短链接。
 * 用于写邮件/邮件模板：粘贴带图内容会内嵌几百 KB base64 撑爆正文（模板还有长度上限），
 * 转成 URL 后正文只剩一条链接，图片照常显示。
 *
 * @param {string} markdown
 * @param {string} accountId
 * @returns {Promise<string>} 替换后的 markdown（无内联图则原样返回）
 */
export async function uploadInlineDataUriImages(markdown, accountId) {
  if (!markdown || !markdown.includes('base64,')) return markdown;

  const regex = /!\[[^\]]*]\(\s*(data:[^;]+;base64,[^)\s]+)\s*\)/gi;
  // 去重：同一张图贴多次只上传一次。
  const dataUris = [...new Set([...markdown.matchAll(regex)].map(m => m[1]))];
  if (!dataUris.length) return markdown;

  const uploaded = await Promise.all(
    dataUris.map(async dataUri => {
      const file = dataUriToImageFile(dataUri);
      if (!file) return null;
      const { fileUrl } = await uploadFile(file, accountId);
      return fileUrl ? { dataUri, fileUrl } : null;
    })
  );

  let result = markdown;
  uploaded.filter(Boolean).forEach(({ dataUri, fileUrl }) => {
    result = result.split(dataUri).join(fileUrl);
  });
  return result;
}

/**
 * Uploads an image from an external URL.
 *
 * @param {string} url - The external URL of the image.
 * @param {string} accountId - The account ID.
 * @returns {Promise} A promise that resolves with the server's response.
 */
export async function uploadExternalImage(url, accountId) {
  if (!accountId) {
    accountId = window.location.pathname.split('/')[3];
  }

  const { data } = await axios.post(
    `/api/${API_VERSION}/accounts/${accountId}/upload`,
    { external_url: url },
    { headers: { 'Content-Type': 'application/json' } }
  );

  return {
    fileUrl: data.file_url,
    blobKey: data.blob_key,
    blobId: data.blob_id,
  };
}
