import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../../domain/models/midi_data.dart';

class ConvertPage extends ConsumerWidget {
  const ConvertPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ConvertState state = ref.watch(convertStateProvider);
    final ConvertStateNotifier notifier =
        ref.read(convertStateProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F2937),
        title: const Text('谱面转换', style: TextStyle(fontSize: 16)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _buildBody(state, notifier, context),
    );
  }

  Widget _buildBody(
      ConvertState state, ConvertStateNotifier notifier, BuildContext context) {
    switch (state.page) {
      case ConvertPageState.aNoFile:
        return _stateA(notifier);
      case ConvertPageState.bSelectTrack:
        return _stateB(state, notifier);
      case ConvertPageState.cPreview:
        return _stateC(state, notifier);
      case ConvertPageState.dSave:
        return _stateD(state, notifier, context);
      case ConvertPageState.eError:
        return _stateE(state, notifier);
    }
  }

  Widget _stateA(ConvertStateNotifier notifier) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ElevatedButton.icon(
            onPressed: () => notifier.pickFile(),
            icon: const Icon(Icons.folder_open, size: 28),
            label: const Text('📁 选择 MIDI 文件'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          const Text('支持 SMF 格式 0 与 1，单字节编码',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
        ],
      ),
    );
  }

  Widget _stateB(ConvertState state, ConvertStateNotifier notifier) {
    final List<MidiTrackInfo> tracks = state.midiData?.tracks ?? <MidiTrackInfo>[];
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF1F2937),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: <Widget>[
                const Text('🎵', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '已识别：${state.midiData?.format == MidiFormat.single ? '格式 0' : '格式 1'}，${tracks.length} 轨道',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14),
                      ),
                      const Text('请选择一条作为「旋律轨」',
                          style: TextStyle(
                              color: Color(0xFF6B7280), fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: tracks.length,
              separatorBuilder: (_, _) =>
                  const Divider(color: Color(0xFF374151)),
              itemBuilder: (BuildContext context, int index) {
                final MidiTrackInfo t = tracks[index];
                final bool sel = state.selectedTrackIndex == index;
                return GestureDetector(
                  onTap: () => notifier.selectTrack(index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    color: sel ? const Color(0xFF2563EB).withAlpha(50) : null,
                    child: Row(
                      children: <Widget>[
                        Icon(
                          sel ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                          color: sel ? const Color(0xFF2563EB) : const Color(0xFF6B7280),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                '轨道 ${t.trackIndex + 1} · ${t.trackName ?? "通道 ${t.channel}"}',
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                              ),
                              Text(
                                '${t.noteCount} notes${t.minPitch >= 0 ? " · 音域 ${_pitchName(t.minPitch)}-${_pitchName(t.maxPitch)}" : ""}',
                                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed:
                    state.selectedTrackIndex != null ? notifier.toSave : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  disabledBackgroundColor: const Color(0xFF374151),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('下一步：保存',
                    style: TextStyle(fontSize: 14)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stateC(ConvertState state, ConvertStateNotifier notifier) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: <Widget>[
          _field('曲名', state.title, notifier.setTitle),
          const SizedBox(height: 8),
          _field('作曲家', state.composer, notifier.setComposer),
          const SizedBox(height: 12),
          if (state.midiData != null)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _metaCard('BPM', state.midiData!.tempoMap.isNotEmpty
                    ? state.midiData!.tempoMap.first.bpm.toStringAsFixed(0)
                    : '—'),
                _metaCard('拍号', state.midiData!.timeSignature),
                _metaCard('调号', state.midiData!.keySignature),
                _metaCard('总时长', _fmtMs(state.midiData!.totalDurationMs)),
              ],
            ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              OutlinedButton(
                onPressed: () => notifier.selectTrack(
                    state.selectedTrackIndex ?? 0),
                child: const Text('上一步'),
              ),
              ElevatedButton(
                onPressed: notifier.toSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                ),
                child: const Text('下一步：保存'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stateD(
      ConvertState state, ConvertStateNotifier notifier, BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('💾 保存为 DK 谱',
                style: TextStyle(color: Colors.white, fontSize: 18)),
            const SizedBox(height: 16),
            TextField(
              controller: TextEditingController(
                  text: state.title.isNotEmpty ? state.title : 'untitled'),
              onChanged: notifier.setTitle,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: '文件名',
                hintStyle: const TextStyle(color: Color(0xFF6B7280)),
                filled: true,
                fillColor: const Color(0xFF374151),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text('📂 保存到 App 私有目录',
                style: TextStyle(color: Color(0xFF6B7280), fontSize: 12)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                OutlinedButton(
                  onPressed: () =>
                      notifier.selectTrack(state.selectedTrackIndex ?? 0),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await notifier.confirmSave();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('✓ 已保存'),
                        backgroundColor: Color(0xFF16A34A),
                        duration: Duration(seconds: 1),
                      ),
                    );
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                  ),
                  child: const Text('确认保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stateE(ConvertState state, ConvertStateNotifier notifier) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(40),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFEF4444)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.warning_amber, color: Color(0xFFF87171), size: 40),
            const SizedBox(height: 12),
            const Text('无法导入',
                style: TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(state.message,
                  style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13)),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: notifier.dismissError,
              child: const Text('知道了'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, String value, ValueChanged<String> onChanged) {
    return TextField(
      controller: TextEditingController(text: value),
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF9CA3AF)),
        filled: true,
        fillColor: const Color(0xFF374151),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _metaCard(String label, String value) {
    return Container(
      width: 120,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF374151)),
      ),
      child: Column(
        children: <Widget>[
          Text(label,
              style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(color: Colors.white, fontSize: 16)),
        ],
      ),
    );
  }

  String _pitchName(int pitch) {
    const List<String> names = <String>[
      'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'
    ];
    final int octave = pitch ~/ 12 - 1;
    return '${names[pitch % 12]}$octave';
  }

  String _fmtMs(int ms) {
    final int totalSec = ms ~/ 1000;
    final int min = totalSec ~/ 60;
    final int sec = totalSec % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }
}
