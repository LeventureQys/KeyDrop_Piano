import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../../domain/models/app_config.dart';
import '../widgets/seg_group.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppConfig config = ref.watch(appConfigProvider);
    final AppConfigNotifier notifier = ref.read(appConfigProvider.notifier);
    final String jsonStr =
        const JsonEncoder.withIndent('  ').convert(config.toJson());

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F2937),
        title: const Text('设置', style: TextStyle(fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: <Widget>[
                _Section(
                  icon: Icons.piano,
                  title: '键盘',
                  children: <Widget>[
                    _label('硬件键数'),
                    SegGroup<int>(
                      options: const <SegOption<int>>[
                        SegOption<int>(value: 49, label: '49'),
                        SegOption<int>(value: 61, label: '61'),
                        SegOption<int>(value: 76, label: '76'),
                        SegOption<int>(value: 88, label: '88'),
                      ],
                      value: config.hardwareKeyboardKeys,
                      onChanged: notifier.setHardwareKeyboardKeys,
                    ),
                    const SizedBox(height: 8),
                    _label('视口键数'),
                    SegGroup<int>(
                      options: const <SegOption<int>>[
                        SegOption<int>(value: 24, label: '24'),
                        SegOption<int>(value: 32, label: '32'),
                        SegOption<int>(value: 40, label: '40'),
                      ],
                      value: config.viewportKeys,
                      onChanged: notifier.setViewportKeys,
                    ),
                    const SizedBox(height: 8),
                    _label('滚动模式'),
                    SegGroup<ScrollMode>(
                      options: const <SegOption<ScrollMode>>[
                        SegOption<ScrollMode>(value: ScrollMode.auto, label: '自动'),
                        SegOption<ScrollMode>(value: ScrollMode.manual, label: '手动'),
                        SegOption<ScrollMode>(value: ScrollMode.fixed, label: '固定'),
                      ],
                      value: config.scrollMode,
                      onChanged: notifier.setScrollMode,
                    ),
                  ],
                ),
                _Section(
                  icon: Icons.movie,
                  title: '显示',
                  children: <Widget>[
                    _slider(
                      '下落时长',
                      config.fallDurationSeconds,
                      1.0,
                      3.0,
                      0.1,
                      (double v) => notifier.setFallDurationSeconds(v),
                      suffix: '${config.fallDurationSeconds.toStringAsFixed(1)}s',
                    ),
                  ],
                ),
                _Section(
                  icon: Icons.gps_fixed,
                  title: '判定',
                  children: <Widget>[
                    _label('判定档位'),
                    SegGroup<JudgmentWidth>(
                      options: const <SegOption<JudgmentWidth>>[
                        SegOption<JudgmentWidth>(value: JudgmentWidth.strict, label: '严 60ms'),
                        SegOption<JudgmentWidth>(value: JudgmentWidth.medium, label: '中 100ms'),
                        SegOption<JudgmentWidth>(value: JudgmentWidth.wide, label: '宽 160ms'),
                      ],
                      value: config.judgmentWidth,
                      onChanged: notifier.setJudgmentWidth,
                    ),
                    const SizedBox(height: 8),
                    _slider(
                      '输入延迟校准',
                      config.inputLatencyOffsetMs.toDouble(),
                      -100,
                      100,
                      5,
                      (double v) =>
                          notifier.setInputLatencyOffsetMs(v.round()),
                      suffix: '${config.inputLatencyOffsetMs}ms',
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 32,
                      child: OutlinedButton.icon(
                        onPressed: () => _showCalibrationDialog(context),
                        icon: const Icon(Icons.tune, size: 14),
                        label: const Text('校准', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ),
                _Section(
                  icon: Icons.music_note,
                  title: '演奏',
                  children: <Widget>[
                    _slider(
                      'BPM 倍率',
                      config.bpmMultiplier,
                      0.5,
                      2.0,
                      0.05,
                      (double v) => notifier.setBpmMultiplier(v),
                      suffix: '${config.bpmMultiplier.toStringAsFixed(2)}×',
                    ),
                    const SizedBox(height: 8),
                    _label('默认模式'),
                    SegGroup<PlayMode>(
                      options: const <SegOption<PlayMode>>[
                        SegOption<PlayMode>(value: PlayMode.learning, label: '学习'),
                        SegOption<PlayMode>(value: PlayMode.performance, label: '演奏'),
                      ],
                      value: config.defaultMode,
                      onChanged: notifier.setDefaultMode,
                    ),
                  ],
                ),
                _Section(
                  icon: Icons.bug_report,
                  title: '调试',
                  children: <Widget>[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        const Text('DebugMidiInjector',
                            style: TextStyle(fontSize: 13)),
                        Switch(
                          value: config.enableDebugMidiInjector,
                          onChanged: notifier.setEnableDebugMidiInjector,
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          // JSON 预览
          Container(
            width: double.infinity,
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: const Color(0xFF0B1220),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Text(
                jsonStr.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' '),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Color(0xFF86EFAC),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCalibrationDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        Future<void>.delayed(const Duration(seconds: 3), () {
          if (context.mounted) {
            Navigator.of(context).pop();
          }
        });
        return const AlertDialog(
          backgroundColor: Color(0xFF1F2937),
          title: Text('校准中…', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text(
                '请在电钢琴上按下任意键…',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ),
        );
      },
    );
  }
}

Widget _label(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF9CA3AF),
          )),
    );

Widget _slider(
  String label,
  double value,
  double min,
  double max,
  double step,
  ValueChanged<double> onChanged, {
  String? suffix,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          _label(label),
          Text(suffix ?? value.toStringAsFixed(1),
              style: const TextStyle(fontSize: 12, color: Color(0xFF60A5FA))),
        ],
      ),
      Slider(
        value: value,
        min: min,
        max: max,
        divisions: ((max - min) / step).round(),
        activeColor: const Color(0xFF2563EB),
        onChanged: onChanged,
      ),
    ],
  );
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF374151)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 16, color: Colors.blue.shade300),
              const SizedBox(width: 6),
              Text(title,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}
