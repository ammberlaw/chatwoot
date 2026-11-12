// OA 审批流：编辑器内部结构 ⇄ 后端 flow JSON 的互转，以及条件运算符定义。
// 后端结构：固定步骤 { type:'user'|'dept_leader', user_id }；
//           条件节点 { type:'condition', branches:[{ conditions:[{var,op,value}], flow:[…] }] }。
// 分支的 flow 里还能再放条件节点（先按发起人分组、组内再按天数分），两端都按递归处理。

let seq = 0;
export const nextSeq = () => {
  seq += 1;
  return seq;
};

// 条件运算符：数值型全量，选择/文本仅等于/不等于，发起人用属于/不属于。
export const OPERATORS = [
  { value: 'lte', label: '≤' },
  { value: 'lt', label: '<' },
  { value: 'gte', label: '≥' },
  { value: 'gt', label: '>' },
  { value: 'eq', label: '=' },
  { value: 'neq', label: '≠' },
];
export const APPLICANT_OPERATORS = [
  { value: 'in', label: '属于' },
  { value: 'not_in', label: '不属于' },
];
const ENUM_OPS = ['eq', 'neq'];

export const varMeta = (vars, name) =>
  vars.find(v => v.value === name) || { kind: 'number' };

export const opsForVar = (vars, name) => {
  const { kind } = varMeta(vars, name);
  if (kind === 'applicant') return APPLICANT_OPERATORS;
  if (kind === 'number') return OPERATORS;
  return OPERATORS.filter(o => ENUM_OPS.includes(o.value));
};

// 发起人是多选（部门与成员混选），其余条件是单值。
const isMultiKind = kind => kind === 'applicant';

export const blankApprover = () => ({
  seq: nextSeq(),
  type: 'dept_leader',
  userId: '',
});

export const blankCondRow = vars => {
  const name = vars[0]?.value || 'leave_days';
  const { kind } = varMeta(vars, name);
  const multi = isMultiKind(kind);
  return {
    seq: nextSeq(),
    var: name,
    op: multi ? 'in' : 'lte',
    value: multi ? [] : '',
  };
};

export const blankBranch = vars => ({
  seq: nextSeq(),
  conditions: [blankCondRow(vars)],
  flow: [blankApprover()],
});

// 新建条件节点：一个「有条件」分支 + 一个「其他情况」兜底分支。
export const blankCondition = vars => ({
  seq: nextSeq(),
  type: 'condition',
  branches: [
    blankBranch(vars),
    { seq: nextSeq(), conditions: [], flow: [blankApprover()] },
  ],
});

export const isDefaultBranch = b => (b.conditions || []).length === 0;

// 变量类型变了（如从天数换成发起人），运算符与值若不适用则重置。
export const onVarChange = (vars, cond) => {
  const ops = opsForVar(vars, cond.var);
  if (!ops.some(o => o.value === cond.op)) cond.op = ops[0].value;
  cond.value = isMultiKind(varMeta(vars, cond.var).kind) ? [] : '';
};

const parseApprover = s => ({
  seq: nextSeq(),
  type: s.type || 'dept_leader',
  userId: s.user_id ? String(s.user_id) : '',
});

const parseCondValue = value => {
  if (Array.isArray(value)) return value.map(String);
  return value != null ? String(value) : '';
};

export const parseStep = s => {
  if (s.type !== 'condition') return parseApprover(s);
  return {
    seq: nextSeq(),
    type: 'condition',
    branches: (s.branches || []).map(b => ({
      seq: nextSeq(),
      autoApprove: !!b.auto_approve,
      conditions: (b.conditions || []).map(c => ({
        seq: nextSeq(),
        var: c.var,
        op: c.op,
        value: parseCondValue(c.value),
      })),
      flow: (b.flow || []).map(parseStep),
    })),
  };
};

const serializeApprover = s => ({
  type: s.type,
  user_id: s.type === 'user' && s.userId ? Number(s.userId) : null,
});

const serializeCondValue = (vars, c) => {
  const { kind } = varMeta(vars, c.var);
  if (isMultiKind(kind)) return Array.isArray(c.value) ? c.value : [];
  return kind === 'number' || kind === 'dept' ? Number(c.value) : c.value;
};

export const serializeStep = (vars, s) => {
  if (s.type !== 'condition') return serializeApprover(s);
  return {
    type: 'condition',
    branches: (s.branches || []).map(b => ({
      conditions: (b.conditions || []).map(c => ({
        var: c.var,
        op: c.op,
        value: serializeCondValue(vars, c),
      })),
      auto_approve: !!b.autoApprove,
      flow: b.autoApprove
        ? []
        : (b.flow || []).map(x => serializeStep(vars, x)),
    })),
  };
};

// 整棵流程树里是否出现「申请人部门主管」——发起时要不要让他选部门。
export const flowNeedsDept = flow =>
  (flow || []).some(s =>
    s.type === 'condition'
      ? (s.branches || []).some(b => flowNeedsDept(b.flow))
      : s.type === 'dept_leader'
  );
