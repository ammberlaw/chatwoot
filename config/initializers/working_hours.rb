# MES 接单计时用工作时间口径：工作日 08:00–17:30，周末不计（进入阶段后 4 个「工作小时」内须接单）。
# 用于生产订单接单时限（ack_deadline）、超时未接单点名、看板各环节接单响应时长。
# 法定节假日暂不排除，将来可在此填 WorkingHours::Config.holidays。
WorkingHours::Config.working_hours = {
  mon: { '08:00' => '17:30' },
  tue: { '08:00' => '17:30' },
  wed: { '08:00' => '17:30' },
  thu: { '08:00' => '17:30' },
  fri: { '08:00' => '17:30' }
}
WorkingHours::Config.time_zone = 'Asia/Shanghai'
