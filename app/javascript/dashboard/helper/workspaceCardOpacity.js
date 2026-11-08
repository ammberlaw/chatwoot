export const WORKSPACE_CARDS = [
  { id: 'crm', label: 'CRM' },
  { id: 'oa', label: 'OA' },
  { id: 'hr', label: 'HR' },
  { id: 'orders', label: 'ORDERS' },
  { id: 'erp', label: 'ERP' },
  { id: 'team', label: 'TEAM' },
  { id: 'tiktok', label: 'TIKTOK' },
  { id: 'docs', label: 'DOCS' },
  { id: 'calendar', label: 'CALENDAR' },
];

export const defaultWorkspaceCardOpacity = () => ({ all: 100, overrides: {} });

export const copyWorkspaceCardOpacity = settings => ({
  all: settings.all,
  overrides: { ...settings.overrides },
});

export const workspaceCardOpacity = (settings, id) =>
  settings.overrides[id] ?? settings.all;

// Literal classes keep every slider step available to Tailwind's scanner.
const whiteBackgrounds = [
  '!bg-white/0',
  '!bg-white/5',
  '!bg-white/10',
  '!bg-white/15',
  '!bg-white/20',
  '!bg-white/25',
  '!bg-white/30',
  '!bg-white/35',
  '!bg-white/40',
  '!bg-white/45',
  '!bg-white/50',
  '!bg-white/55',
  '!bg-white/60',
  '!bg-white/65',
  '!bg-white/70',
  '!bg-white/75',
  '!bg-white/80',
  '!bg-white/85',
  '!bg-white/90',
  '!bg-white/95',
  '!bg-white/100',
];
const crmBackgrounds = [
  '!bg-[#f6fafd]/0',
  '!bg-[#f6fafd]/5',
  '!bg-[#f6fafd]/10',
  '!bg-[#f6fafd]/15',
  '!bg-[#f6fafd]/20',
  '!bg-[#f6fafd]/25',
  '!bg-[#f6fafd]/30',
  '!bg-[#f6fafd]/35',
  '!bg-[#f6fafd]/40',
  '!bg-[#f6fafd]/45',
  '!bg-[#f6fafd]/50',
  '!bg-[#f6fafd]/55',
  '!bg-[#f6fafd]/60',
  '!bg-[#f6fafd]/65',
  '!bg-[#f6fafd]/70',
  '!bg-[#f6fafd]/75',
  '!bg-[#f6fafd]/80',
  '!bg-[#f6fafd]/85',
  '!bg-[#f6fafd]/90',
  '!bg-[#f6fafd]/95',
  '!bg-[#f6fafd]/100',
];

export const workspaceCardBackground = (settings, id) => {
  const step = Math.round(workspaceCardOpacity(settings, id) / 5);
  return (id === 'crm' ? crmBackgrounds : whiteBackgrounds)[step];
};
