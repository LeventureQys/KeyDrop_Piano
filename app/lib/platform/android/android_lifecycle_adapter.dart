import 'package:flutter/services.dart';

import '../../domain/ports/lifecycle_port.dart';

/// Android 生命周期适配器：MethodChannel `keydrop_piano/lifecycle`
/// （Version 设计文档 2.1 平台层 PlatformLifecycle 的 Android 实现）。
class AndroidLifecycleAdapter implements LifecyclePort {
  static const MethodChannel _channel =
      MethodChannel('keydrop_piano/lifecycle');

  @override
  Future<void> setKeepScreenOn(bool enabled) async {
    await _channel.invokeMethod('setKeepScreenOn', <String, dynamic>{
      'enabled': enabled,
    });
  }
}
