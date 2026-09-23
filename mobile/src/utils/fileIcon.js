// 文件类型图标与配色。知识库列表里一整列同样的灰色文件图标什么也没说，
// 靠扩展名给出类型色之后，扫一眼就知道哪条是表格、哪条是视频。
// 颜色对应的是各家软件的约定色（Excel 绿、PDF 红、PPT 橙…），不是随便配的。
const MAP = [
  { re: /\.(xlsx?|csv|numbers)$/i, icon: 'i-ri-file-excel-2-fill', cls: 'text-[#1F7A47]' },
  { re: /\.(docx?|pages)$/i, icon: 'i-ri-file-word-2-fill', cls: 'text-[#2B579A]' },
  { re: /\.(pptx?|key)$/i, icon: 'i-ri-file-ppt-2-fill', cls: 'text-[#C43E1C]' },
  { re: /\.pdf$/i, icon: 'i-ri-file-pdf-2-fill', cls: 'text-[#D93025]' },
  { re: /\.(png|jpe?g|gif|webp|heic|bmp|svg)$/i, icon: 'i-ri-image-fill', cls: 'text-[#1A73E8]' },
  { re: /\.(mp4|mov|avi|mkv|webm)$/i, icon: 'i-ri-video-fill', cls: 'text-[#7C4DFF]' },
  { re: /\.(mp3|wav|m4a|aac)$/i, icon: 'i-ri-music-2-fill', cls: 'text-[#E8710A]' },
  { re: /\.(zip|rar|7z|tar|gz)$/i, icon: 'i-ri-folder-zip-fill', cls: 'text-[#6B6B78]' },
];

// 没有扩展名的当「资料夹」——知识库里那种一条挂多个附件的条目就是这种
export const fileIcon = (name, attachmentCount = 0) => {
  const hit = MAP.find(m => m.re.test(String(name || '')));
  if (hit) return hit;
  return attachmentCount > 1
    ? { icon: 'i-ri-folder-fill', cls: 'text-[color:var(--pb-brand-ink)]' }
    : { icon: 'i-ri-file-text-fill', cls: 'text-[color:var(--pb-ink-3)]' };
};
