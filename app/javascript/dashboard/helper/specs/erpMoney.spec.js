import { fmtMoney, rmbCapital } from '../erpMoney';

// 人民币大写是要印在凭证票面上的，写错了整张凭证作废重打。
// 补「零」的规则最容易错：看的是**下一节够不够四位**，不是看当前节大小。
describe('erpMoney', () => {
  describe('fmtMoney', () => {
    it('按元显示，固定两位小数、带千分位', () => {
      expect(fmtMoney(1_234_567_890_000)).toBe('1,234,567.89');
      expect(fmtMoney(0)).toBe('0.00');
      expect(fmtMoney(500_000)).toBe('0.50');
    });

    it('空值不显示 0，交给调用方决定占位符', () => {
      expect(fmtMoney(null)).toBe('');
      expect(fmtMoney(undefined)).toBe('');
    });
  });

  describe('rmbCapital', () => {
    it('整元带「整」', () => {
      expect(rmbCapital(1_000_000)).toBe('壹元整');
      // 票据大写规范要求「壹拾」不能省成「拾」
      expect(rmbCapital(10_000_000)).toBe('壹拾元整');
      expect(rmbCapital(100_000_000)).toBe('壹佰元整');
    });

    it('角分', () => {
      expect(rmbCapital(1_050_000)).toBe('壹元零伍分');
      expect(rmbCapital(1_500_000)).toBe('壹元伍角');
      expect(rmbCapital(1_560_000)).toBe('壹元伍角陆分');
      expect(rmbCapital(50_000)).toBe('伍分');
    });

    it('节与节之间补零看的是下一节够不够四位', () => {
      // 1,234,567.89：万节(123)之后跟着 4567 是满四位，不补零
      expect(rmbCapital(1_234_567_890_000)).toBe(
        '壹佰贰拾叁万肆仟伍佰陆拾柒元捌角玖分'
      );
      // 1,000,567.00：万节(100)之后跟着 567 不满四位，要补零
      expect(rmbCapital(1_000_567_000_000)).toBe('壹佰万零伍佰陆拾柒元整');
    });

    it('节内补零', () => {
      expect(rmbCapital(1_002_000_000)).toBe('壹仟零贰元整');
      expect(rmbCapital(1_000_000_000)).toBe('壹仟元整');
    });

    it('亿级', () => {
      expect(rmbCapital(123_456_789_000_000)).toBe(
        '壹亿贰仟叁佰肆拾伍万陆仟柒佰捌拾玖元整'
      );
    });

    it('零与负数', () => {
      expect(rmbCapital(0)).toBe('零元整');
      expect(rmbCapital(-1_234_000_000)).toBe('负壹仟贰佰叁拾肆元整');
    });
  });
});
