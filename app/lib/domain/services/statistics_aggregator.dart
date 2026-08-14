import '../models/app_config.dart';
import 'judgment_engine.dart';

/// 演奏统计汇总（Version 设计文档 2.1 领域服务 StatisticsAggregator）。
///
/// 计分规则（问题清单 F2 / 设计文档）：
/// - 完美 = 100%，抢拍 = 70%，拖拍 = 70%，掉 key = 0%，错音 = 0%（相当于扣分）。
/// - `scorePercent = Σ(权重) / 总判定数`，总判定数含错音与掉 key。
class JudgmentStats {
  int perfect = 0;
  int early = 0;
  int late = 0;
  int miss = 0;
  int error = 0;

  /// 综合得分（0-100）。
  double get scorePercent {
    final int total = perfect + early + late + miss + error;
    if (total == 0) {
      return 100.0;
    }
    return (perfect * 100 + early * 70 + late * 70) / total.toDouble();
  }
}

/// 统计聚合器：把判定引擎的原始记录与错音计数汇总为 [JudgmentStats]。
class StatisticsAggregator {
  const StatisticsAggregator();

  JudgmentStats aggregate(List<JudgmentRecord> records, int errorCount) {
    final JudgmentStats s = JudgmentStats();
    s.error = errorCount;
    for (final JudgmentRecord r in records) {
      switch (r.result) {
        case JudgmentResult.perfect:
          s.perfect++;
        case JudgmentResult.early:
          s.early++;
        case JudgmentResult.late:
          s.late++;
        case JudgmentResult.miss:
          s.miss++;
      }
    }
    return s;
  }
}

/// 便捷函数（保持与旧调用点兼容）。
JudgmentStats computeStats(List<JudgmentRecord> records, int errorCount) =>
    const StatisticsAggregator().aggregate(records, errorCount);
