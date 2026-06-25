import 'package:flutter_test/flutter_test.dart';
import 'package:keydrop_piano/domain/exceptions/dk_exception.dart';

String _describe(DkException e) => switch (e) {
      UnsupportedMidiFormatException() => 'unsupported',
      CorruptedMidiException() => 'corrupted',
      DkVersionTooHighException() => 'version',
      MidiDeviceConnectionException() => 'device',
      FileSystemAccessException() => 'fs',
    };

void main() {
  group('DkException (E1)', () {
    test('每个子类 message 可取且 toString 含类型名与 message', () {
      final List<DkException> all = <DkException>[
        UnsupportedMidiFormatException('格式 2 不支持'),
        CorruptedMidiException('chunk 读取失败'),
        DkVersionTooHighException('版本过高'),
        MidiDeviceConnectionException('连接失败'),
        FileSystemAccessException('写入失败'),
      ];
      for (final DkException e in all) {
        expect(e.message, isNotEmpty);
        expect(e.toString(), contains(e.runtimeType.toString()));
        expect(e.toString(), contains(e.message));
      }
    });
  });

  group('DkException sealed (E2)', () {
    test('对所有子类穷尽 switch 匹配', () {
      expect(_describe(UnsupportedMidiFormatException('x')), 'unsupported');
      expect(_describe(CorruptedMidiException('x')), 'corrupted');
      expect(_describe(DkVersionTooHighException('x')), 'version');
      expect(_describe(MidiDeviceConnectionException('x')), 'device');
      expect(_describe(FileSystemAccessException('x')), 'fs');
    });
  });
}
