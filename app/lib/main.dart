import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // TODO(stage6): 进入播放器时启用强制横屏锁定
  //   (SystemChrome.setPreferredOrientations) 与屏幕常亮 (wakelock)，
  //   离开时恢复。骨架阶段不引入平台依赖，仅占位。
  runApp(const ProviderScope(child: KeyDropApp()));
}
