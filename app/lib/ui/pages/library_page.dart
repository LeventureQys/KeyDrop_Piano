import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../di/providers.dart';
import '../../domain/models/dk_score.dart';
import '../../domain/ports/file_system_port.dart';
import 'convert_page.dart';
import 'player_page.dart';
import 'settings_page.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _fabOpen = false;
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<DkScoreFile>> scoresAsync = ref.watch(scoreListProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F2937),
        title: const Row(
          children: <Widget>[
            Text('🎹', style: TextStyle(fontSize: 18)),
            SizedBox(width: 8),
            Text('键落钢琴',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.settings, color: Color(0xFF9CA3AF)),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SettingsPage(),
                ),
              );
              ref.invalidate(scoreListProvider);
            },
          ),
        ],
      ),
      body: scoresAsync.when(
        data: (List<DkScoreFile> scores) =>
            scores.isEmpty ? _buildEmpty() : _buildFilled(scores),
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (Object e, _) =>
            Center(child: Text('加载失败: $e', style: const TextStyle(color: Colors.red))),
      ),
      floatingActionButton: _buildFab(),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text('🎹', style: TextStyle(fontSize: 80)),
          const SizedBox(height: 16),
          const Text('还没有任何谱面',
              style: TextStyle(fontSize: 18, color: Colors.white)),
          const SizedBox(height: 8),
          const Text('导入 MIDI 文件以创建第一个谱面',
              style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF))),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => _navToConvert(),
            icon: const Icon(Icons.add),
            label: const Text('开始导入'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilled(List<DkScoreFile> scores) {
    final List<DkScoreFile> filtered = _query.isEmpty
        ? scores
        : scores
            .where((DkScoreFile s) =>
                s.displayName.toLowerCase().startsWith(_query.toLowerCase()))
            .toList();

    return Column(
      children: <Widget>[
        // 搜索栏
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (String v) => setState(() => _query = v),
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: '搜索曲名或作曲家…',
              hintStyle: const TextStyle(color: Color(0xFF6B7280), fontSize: 13),
              prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF6B7280)),
              suffixText: '${filtered.length} 首',
              suffixStyle: const TextStyle(color: Color(0xFF6B7280), fontSize: 11),
              filled: true,
              fillColor: const Color(0xFF374151),
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        // 列表
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Text('没有匹配的谱面',
                      style: TextStyle(color: Color(0xFF9CA3AF))))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) =>
                      const Divider(color: Color(0xFF374151), height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    final DkScoreFile s = filtered[index];
                    return GestureDetector(
                      onTap: () => _playScore(s),
                      onLongPressStart: (LongPressStartDetails d) {
                        _showContextMenu(d.globalPosition, s, context);
                      },
                      child: Container(
                        height: 52,
                        alignment: Alignment.center,
                        child: Row(
                          children: <Widget>[
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2563EB).withAlpha(70),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(Icons.music_note,
                                  color: Color(0xFF60A5FA), size: 18),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(s.displayName,
                                      style: const TextStyle(
                                          color: Colors.white, fontSize: 13)),
                                  Text(
                                    '${s.sizeBytes ~/ 1024} KB · ${_fmtDate(s.modifiedAt)}',
                                    style: const TextStyle(
                                        color: Color(0xFF6B7280), fontSize: 11),
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
      ],
    );
  }

  Widget _buildFab() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (_fabOpen) ...<Widget>[
          _FabOption(
            icon: Icons.folder_open,
            label: '导入 DK 谱',
            color: const Color(0xFF7C3AED),
            onTap: () {
              setState(() => _fabOpen = false);
            },
          ),
          const SizedBox(height: 8),
          _FabOption(
            icon: Icons.music_note,
            label: '从 MIDI 文件创建',
            color: const Color(0xFF2563EB),
            onTap: () {
              setState(() => _fabOpen = false);
              _navToConvert();
            },
          ),
          const SizedBox(height: 8),
        ],
        FloatingActionButton(
          backgroundColor: const Color(0xFF2563EB),
          onPressed: () => setState(() => _fabOpen = !_fabOpen),
          child: AnimatedRotation(
            turns: _fabOpen ? 0.125 : 0,
            duration: const Duration(milliseconds: 180),
            child: const Icon(Icons.add, color: Colors.white),
          ),
        ),
      ],
    );
  }

  void _navToConvert() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ConvertPage()),
    ).then((_) => ref.invalidate(scoreListProvider));
  }

  void _showContextMenu(
      Offset position, DkScoreFile score, BuildContext context) {
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy,
          position.dx + 1, position.dy + 1),
      color: const Color(0xFF1F2937),
      items: <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'play',
          child: Text('演奏', style: TextStyle(color: Colors.white)),
        ),
        const PopupMenuItem<String>(
          value: 'rename',
          child: Text('重命名', style: TextStyle(color: Colors.white)),
        ),
        const PopupMenuItem<String>(
          value: 'export',
          child: Text('导出', style: TextStyle(color: Colors.white)),
        ),
        const PopupMenuItem<String>(
          value: 'delete',
          child: Text('删除',
              style: TextStyle(color: Color(0xFFF87171))),
        ),
      ],
    ).then((String? action) async {
      if (action == 'delete') {
        ref.read(fileSystemProvider).deleteDkScore(score.fileId);
        ref.invalidate(scoreListProvider);
      } else if (action == 'rename') {
        _showRenameDialog(score);
      } else if (action == 'play') {
        await _playScore(score);
      }
    });
  }

  void _showRenameDialog(DkScoreFile score) {
    final TextEditingController ctrl =
        TextEditingController(text: score.displayName);
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: const Text('重命名', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: '新名称',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              ref.read(fileSystemProvider).renameDkScore(score.fileId, ctrl.text);
              ref.invalidate(scoreListProvider);
              Navigator.of(ctx).pop();
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  Future<void> _playScore(DkScoreFile s) async {
    final String json =
        await ref.read(fileSystemProvider).readDkScore(s.fileId);
    final DkScore score = DkScore.fromJsonString(json);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerPage(
          score: score,
          config: ref.read(appConfigProvider),
          midiInput: ref.read(midiInputProvider),
        ),
      ),
    );
  }
}

class _FabOption extends StatelessWidget {
  const _FabOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withAlpha(200),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

