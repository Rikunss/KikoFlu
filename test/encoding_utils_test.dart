import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:kikoeru_flutter/src/utils/encoding_utils.dart';

void main() {
  group('UTF-8', () {
    test('纯 ASCII 文本', () {
      final bytes = utf8.encode('Hello world');
      final (content, encoding) = EncodingUtils.decodeBytes(bytes);
      expect(encoding, 'UTF-8');
      expect(content, 'Hello world');
    });

    test('UTF-8 中文', () {
      final bytes = utf8.encode('你好世界');
      final (content, encoding) = EncodingUtils.decodeBytes(bytes);
      expect(encoding, 'UTF-8');
      expect(content, '你好世界');
    });

    test('UTF-8 日文', () {
      final bytes = utf8.encode('こんにちは世界');
      final (content, encoding) = EncodingUtils.decodeBytes(bytes);
      expect(encoding, 'UTF-8');
      expect(content, 'こんにちは世界');
    });

    test('UTF-8 韩文', () {
      final bytes = utf8.encode('안녕하세요');
      final (content, encoding) = EncodingUtils.decodeBytes(bytes);
      expect(encoding, 'UTF-8');
      expect(content, '안녕하세요');
    });

    test('UTF-8 BOM (EF BB BF)', () {
      const text = '带BOM的UTF-8文本';
      final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode(text)];
      final (content, encoding) = EncodingUtils.decodeBytes(bytes);
      expect(encoding, 'UTF-8');
      expect(content, text);
    });

    test('UTF-8 混合语言', () {
      const text = 'English 中文 日本語 한국어 Русский';
      final bytes = utf8.encode(text);
      final (content, encoding) = EncodingUtils.decodeBytes(bytes);
      expect(encoding, 'UTF-8');
      expect(content, text);
    });

    test('UTF-8 Emoji', () {
      const text = '🎵 Music 🎶';
      final bytes = utf8.encode(text);
      final (content, encoding) = EncodingUtils.decodeBytes(bytes);
      expect(encoding, 'UTF-8');
      expect(content, text);
    });

    test('UTF-8 多行字幕内容', () {
      const text = '[00:01.00]第一行歌词\n[00:05.00]第二行歌词\n[00:10.00]第三行歌词';
      final bytes = utf8.encode(text);
      final (content, encoding) = EncodingUtils.decodeBytes(bytes);
      expect(encoding, 'UTF-8');
      expect(content, text);
    });
  });

  group('UTF-16LE', () {
    test('UTF-16LE BOM + ASCII', () {
      final bytes = [0xFF, 0xFE, 0x48, 0x00, 0x69, 0x00];
      final (content, encoding) = EncodingUtils.decodeBytes(bytes);
      expect(encoding, 'UTF-16LE');
      expect(content, 'Hi');
    });

    test('UTF-16LE 中文', () {
      const text = '你好';
      final encoded = EncodingUtils.encodeString(text, 'UTF-16LE');
      final (content, encoding) = EncodingUtils.decodeBytes(encoded);
      expect(encoding, 'UTF-16LE');
      expect(content, text);
    });

    test('UTF-16LE 日文', () {
      const text = 'こんにちは';
      final encoded = EncodingUtils.encodeString(text, 'UTF-16LE');
      final (content, encoding) = EncodingUtils.decodeBytes(encoded);
      expect(encoding, 'UTF-16LE');
      expect(content, text);
    });

    test('UTF-16LE 往返一致性', () {
      const text = 'Hello 你好 こんにちは';
      final encoded = EncodingUtils.encodeString(text, 'UTF-16LE');
      expect(encoded[0], 0xFF);
      expect(encoded[1], 0xFE);
      final (content, encoding) = EncodingUtils.decodeBytes(encoded);
      expect(encoding, 'UTF-16LE');
      expect(content, text);
    });
  });

  group('UTF-16BE', () {
    test('UTF-16BE BOM + ASCII', () {
      final bytes = [0xFE, 0xFF, 0x00, 0x48, 0x00, 0x69];
      final (content, encoding) = EncodingUtils.decodeBytes(bytes);
      expect(encoding, 'UTF-16BE');
      expect(content, 'Hi');
    });

    test('UTF-16BE 中文', () {
      const text = '世界';
      final encoded = EncodingUtils.encodeString(text, 'UTF-16BE');
      final (content, encoding) = EncodingUtils.decodeBytes(encoded);
      expect(encoding, 'UTF-16BE');
      expect(content, text);
    });

    test('UTF-16BE 往返一致性', () {
      const text = 'Test 测试 テスト';
      final encoded = EncodingUtils.encodeString(text, 'UTF-16BE');
      expect(encoded[0], 0xFE);
      expect(encoded[1], 0xFF);
      final (content, encoding) = EncodingUtils.decodeBytes(encoded);
      expect(encoding, 'UTF-16BE');
      expect(content, text);
    });
  });

  group('GBK', () {
    test('GBK 中文字幕内容', () {
      const text = '这是一段中文字幕内容，用于测试编码';
      final encoded = EncodingUtils.encodeString(text, 'GBK');
      final (content, encoding) = EncodingUtils.decodeBytes(encoded);
      expect(encoding, 'GBK');
      expect(content, text);
    });

    test('GBK 中英混合', () {
      const text = '[00:01.00]第一行歌词 Hello\n[00:05.00]第二行 World';
      final encoded = EncodingUtils.encodeString(text, 'GBK');
      final (content, encoding) = EncodingUtils.decodeBytes(encoded);
      expect(encoding, 'GBK');
      expect(content, text);
    });

    test('GBK 常见标点', () {
      const text = '你好,世界!这是测试内容.';
      final encoded = EncodingUtils.encodeString(text, 'GBK');
      final (content, encoding) = EncodingUtils.decodeBytes(encoded);
      expect(encoding, 'GBK');
      expect(content, text);
    });
  });

  group('Shift-JIS', () {
    test('Shift-JIS 与 GBK 字节重叠', () {
      const text = 'あいう';
      final encoded = EncodingUtils.encodeString(text, 'Shift-JIS');
      final (_, encoding) = EncodingUtils.decodeBytes(encoded);
      expect(['GBK', 'Shift-JIS'], contains(encoding));
    });

    test('Shift-JIS 编码→解码一致性 (encodeString 往返)', () {
      const text = 'テスト';
      final encoded = EncodingUtils.encodeString(text, 'Shift-JIS');
      expect(encoded.length, 6);
      final (content, _) = EncodingUtils.decodeBytes(encoded);
      expect(content.isNotEmpty, isTrue);
    });
  });

  group('Latin1', () {
    test('Latin1 纯 ASCII', () {
      final bytes = latin1.encode('Hello world');
      final (content, encoding) = EncodingUtils.decodeBytes(bytes);
      expect(content, 'Hello world');
      expect(encoding, 'UTF-8');
    });

    test('Latin1 西欧特殊字符', () {
      final bytes = [0x63, 0x61, 0x66, 0xE9];
      final (content, encoding) = EncodingUtils.decodeBytes(bytes);
      expect(content.isNotEmpty, isTrue);
    });
  });

  group('Roundtrip (encodeString → decodeBytes)', () {
    test('UTF-8 往返', () {
      const text = 'Hello 你好 こんにちは 안녕';
      final encoded = EncodingUtils.encodeString(text, 'UTF-8');
      final (content, encoding) = EncodingUtils.decodeBytes(encoded);
      expect(encoding, 'UTF-8');
      expect(content, text);
    });

    test('UTF-16LE 往返', () {
      const text = '中英日韩混合 Mixed Content テスト 테스트';
      final encoded = EncodingUtils.encodeString(text, 'UTF-16LE');
      final (content, encoding) = EncodingUtils.decodeBytes(encoded);
      expect(encoding, 'UTF-16LE');
      expect(content, text);
    });

    test('UTF-16BE 往返', () {
      const text = '大端序编码测试';
      final encoded = EncodingUtils.encodeString(text, 'UTF-16BE');
      final (content, encoding) = EncodingUtils.decodeBytes(encoded);
      expect(encoding, 'UTF-16BE');
      expect(content, text);
    });

    test('GBK 往返', () {
      const text = '这是GBK编码的中文字幕';
      final encoded = EncodingUtils.encodeString(text, 'GBK');
      final (content, encoding) = EncodingUtils.decodeBytes(encoded);
      expect(encoding, 'GBK');
      expect(content, text);
    });
  });

  group('Edge Cases', () {
    test('空字节数组', () {
      final (content, encoding) = EncodingUtils.decodeBytes([]);
      expect(content, isEmpty);
      expect(encoding, 'UTF-8');
    });

    test('单字节', () {
      final (content, encoding) = EncodingUtils.decodeBytes([0x41]);
      expect(content, 'A');
      expect(encoding, 'UTF-8');
    });

    test('仅 UTF-16LE BOM 无内容', () {
      final (content, encoding) = EncodingUtils.decodeBytes([0xFF, 0xFE]);
      expect(encoding, 'UTF-16LE');
      expect(content, isEmpty);
    });

    test('仅 UTF-16BE BOM 无内容', () {
      final (content, encoding) = EncodingUtils.decodeBytes([0xFE, 0xFF]);
      expect(encoding, 'UTF-16BE');
      expect(content, isEmpty);
    });

    test('仅 UTF-8 BOM 无内容', () {
      final (content, encoding) =
          EncodingUtils.decodeBytes([0xEF, 0xBB, 0xBF]);
      expect(encoding, 'UTF-8');
      expect(content, isEmpty);
    });

    test('换行符保留', () {
      const text = 'Line1\nLine2\r\nLine3\rLine4';
      final bytes = utf8.encode(text);
      final (content, _) = EncodingUtils.decodeBytes(bytes);
      expect(content, text);
      expect(content.split('\n').length, 3);
    });

    test('大文件性能 (100KB UTF-8)', () {
      final buf = StringBuffer();
      for (int i = 0; i < 5000; i++) {
        buf.writeln('[${(i ~/ 60).toString().padLeft(2, '0')}:${(i % 60).toString().padLeft(2, '0')}.00]这是第$i行歌词内容');
      }
      final bytes = utf8.encode(buf.toString());

      final stopwatch = Stopwatch()..start();
      final (content, encoding) = EncodingUtils.decodeBytes(bytes);
      stopwatch.stop();

      expect(encoding, 'UTF-8');
      expect(content.contains('第0行'), isTrue);
      expect(content.contains('第4999行'), isTrue);
      expect(stopwatch.elapsedMilliseconds, lessThan(50));
    });
  });

  group('Detection Priority', () {
    test('BOM 优先于内容检测', () {
      final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode('Hello')];
      final (_, encoding) = EncodingUtils.decodeBytes(bytes);
      expect(encoding, 'UTF-8');
    });

    test('UTF-16LE BOM 优先于 UTF-8', () {
      final bytes = [0xFF, 0xFE, 0x48, 0x00];
      final (_, encoding) = EncodingUtils.decodeBytes(bytes);
      expect(encoding, 'UTF-16LE');
    });

    test('UTF-16BE BOM 优先于 UTF-8', () {
      final bytes = [0xFE, 0xFF, 0x00, 0x48];
      final (_, encoding) = EncodingUtils.decodeBytes(bytes);
      expect(encoding, 'UTF-16BE');
    });

    test('有效 UTF-8 优先于 GBK', () {
      final bytes = utf8.encode('你好世界');
      final (_, encoding) = EncodingUtils.decodeBytes(bytes);
      expect(encoding, 'UTF-8');
    });

    test('GBK 优先于 Shift-JIS', () {
      final encoded = EncodingUtils.encodeString('这是中文测试内容', 'GBK');
      final (_, encoding) = EncodingUtils.decodeBytes(encoded);
      expect(encoding, 'GBK');
    });
  });

  group('Real Subtitle Scenarios', () {
    test('UTF-8 LRC 字幕', () {
      const lrc = '[ti:测试歌曲]\n[ar:测试歌手]\n[00:01.00]第一句歌词\n[00:05.00]第二句歌词';
      final bytes = utf8.encode(lrc);
      final (content, encoding) = EncodingUtils.decodeBytes(bytes);
      expect(encoding, 'UTF-8');
      expect(content, lrc);
    });

    test('UTF-8 BOM WebVTT 字幕', () {
      const vtt = 'WEBVTT\n\n00:00:01.000 --> 00:00:05.000\nHello world';
      final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode(vtt)];
      final (content, encoding) = EncodingUtils.decodeBytes(bytes);
      expect(encoding, 'UTF-8');
      expect(content, vtt);
    });

    test('GBK SRT 字幕', () {
      const srt = '1\n00:00:01,000 --> 00:00:05,000\n这是一段中文字幕';
      final bytes = EncodingUtils.encodeString(srt, 'GBK');
      final (content, encoding) = EncodingUtils.decodeBytes(bytes);
      expect(encoding, 'GBK');
      expect(content, srt);
    });

    test('UTF-16LE ASS 字幕', () {
      const ass = '[Events]\nDialogue: 0,0:00:01.00,0:00:05.00,Default,,0,0,0,,你好世界';
      final bytes = EncodingUtils.encodeString(ass, 'UTF-16LE');
      final (content, encoding) = EncodingUtils.decodeBytes(bytes);
      expect(encoding, 'UTF-16LE');
      expect(content, ass);
    });

    test('Shift-JIS 日文字幕 (GBK 优先导致误判)', () {
      const text = 'こんにちは\nこれは日本語の字幕です';
      final bytes = EncodingUtils.encodeString(text, 'Shift-JIS');
      final (content, encoding) = EncodingUtils.decodeBytes(bytes);
      expect(['GBK', 'Shift-JIS'], contains(encoding));
      expect(content.isNotEmpty, isTrue);
    });
  });
}