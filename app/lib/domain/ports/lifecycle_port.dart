/// 平台生命周期端口（领域层 → 平台层抽象，Version 设计文档 2.1）。
///
/// 承载"屏幕常亮、横屏锁定"的平台能力。Android 实现见
/// `lib/platform/android/android_lifecycle_adapter.dart`。
abstract class LifecyclePort {
  /// 屏幕常亮开关（进入播放器时开、离开时关；Version 决策表）。
  Future<void> setKeepScreenOn(bool enabled);
}
