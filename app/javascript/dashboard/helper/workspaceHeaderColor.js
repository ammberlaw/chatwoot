export const WORKSPACE_HEADER_COLORS = [
  {
    id: 'dark',
    label: 'DARK',
    text: '!text-[#202427]',
    secondary: '!text-[#646c73]',
    swatch: 'bg-[#202427]',
  },
  {
    id: 'white',
    label: 'WHITE',
    text: '!text-white',
    secondary: '!text-white/80',
    swatch: 'bg-white',
  },
  {
    id: 'yellow',
    label: 'YELLOW',
    text: '!text-[#ffe7a3]',
    secondary: '!text-[#ffe7a3]/80',
    swatch: 'bg-[#ffe7a3]',
  },
  {
    id: 'blue',
    label: 'BLUE',
    text: '!text-[#b9ddff]',
    secondary: '!text-[#b9ddff]/80',
    swatch: 'bg-[#b9ddff]',
  },
  {
    id: 'pink',
    label: 'PINK',
    text: '!text-[#ffd0e4]',
    secondary: '!text-[#ffd0e4]/80',
    swatch: 'bg-[#ffd0e4]',
  },
];

export const workspaceHeaderColor = id =>
  WORKSPACE_HEADER_COLORS.find(color => color.id === id) ||
  WORKSPACE_HEADER_COLORS[0];
