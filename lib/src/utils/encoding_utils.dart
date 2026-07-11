import 'dart:convert';
import 'dart:io';
import 'package:gbk_codec/gbk_codec.dart';
import 'package:charset/charset.dart';

/// 文件编码检测和解码工具类
/// 支持 UTF-8、UTF-16LE、UTF-16BE、GBK、Shift-JIS、Latin1 等编码
class EncodingUtils {
  /// 检测编码并解码字节数组
  /// 返回 (解码后的字符串, 检测到的编码名称)
  static (String content, String encoding) decodeBytes(List<int> bytes) {
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      try {
        final utf16Bytes = bytes.sublist(2);
        final utf16Codes = <int>[];
        for (int i = 0; i < utf16Bytes.length; i += 2) {
          if (i + 1 < utf16Bytes.length) {
            final code = utf16Bytes[i] | (utf16Bytes[i + 1] << 8);
            utf16Codes.add(code);
          }
        }
        return (String.fromCharCodes(utf16Codes), 'UTF-16LE');
      } catch (e) {
      }
    }

    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      try {
        final utf16Bytes = bytes.sublist(2);
        final utf16Codes = <int>[];
        for (int i = 0; i < utf16Bytes.length; i += 2) {
          if (i + 1 < utf16Bytes.length) {
            final code = (utf16Bytes[i] << 8) | utf16Bytes[i + 1];
            utf16Codes.add(code);
          }
        }
        return (String.fromCharCodes(utf16Codes), 'UTF-16BE');
      } catch (e) {
      }
    }

    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      try {
        return (utf8.decode(bytes.sublist(3)), 'UTF-8');
      } catch (e) {
      }
    }

    try {
      final decoded = utf8.decode(bytes, allowMalformed: false);
      return (decoded, 'UTF-8');
    } catch (e) {
    }

    try {
      final decoded = gbk_bytes.decode(bytes);
      if (decoded.isNotEmpty &&
          !decoded.contains('\uFFFD') &&
          !decoded.contains('�')) {
        if (_hasReasonableContent(decoded)) {
          return (decoded, 'GBK');
        }
      }
    } catch (e) {
    }

    try {
      final decoded = shiftJis.decode(bytes);
      if (decoded.isNotEmpty &&
          !decoded.contains('\uFFFD') &&
          !decoded.contains('�')) {
        if (_hasReasonableContent(decoded)) {
          return (decoded, 'Shift-JIS');
        }
      }
    } catch (e) {
    }

    try {
      return (latin1.decode(bytes), 'Latin1');
    } catch (e) {
      return ('文件编码无法识别，无法正确显示内容', 'Unknown');
    }
  }

  /// 检查解码后的内容是否合理
  /// 避免错误解码导致的乱码通过验证
  static bool _hasReasonableContent(String content) {
    if (content.isEmpty) return false;

    int validChars = 0;
    int totalChars = content.length;

    for (final codeUnit in content.codeUnits) {
      if (
          (codeUnit >= 0x20 && codeUnit <= 0x7E) ||
              (codeUnit >= 0x4E00 && codeUnit <= 0x9FFF) ||
              (codeUnit >= 0x3040 && codeUnit <= 0x309F) ||
              (codeUnit >= 0x30A0 && codeUnit <= 0x30FF) ||
              codeUnit == 0x0A ||
              codeUnit == 0x0D ||
              codeUnit == 0x09) {
        validChars++;
      }
    }

    return totalChars > 0 && (validChars / totalChars) > 0.8;
  }

  /// 从文件读取内容，自动检测编码
  /// 返回 (解码后的字符串, 检测到的编码名称)
  static Future<(String content, String encoding)> readFileWithEncoding(
      File file) async {
    final bytes = await file.readAsBytes();
    return decodeBytes(bytes);
  }

  /// 从文件读取内容，自动检测编码（只返回内容）
  static Future<String> readFileAsString(File file) async {
    final (content, _) = await readFileWithEncoding(file);
    return content;
  }

  /// 将字符串编码为字节数组
  /// 使用指定的编码格式
  static List<int> encodeString(String content, String encoding) {
    try {
      switch (encoding) {
        case 'UTF-16LE':
          final codeUnits = content.codeUnits;
          final bytes = <int>[0xFF, 0xFE];
          for (final code in codeUnits) {
            bytes.add(code & 0xFF);
            bytes.add((code >> 8) & 0xFF);
          }
          return bytes;
        case 'UTF-16BE':
          final codeUnits = content.codeUnits;
          final bytes = <int>[0xFE, 0xFF];
          for (final code in codeUnits) {
            bytes.add((code >> 8) & 0xFF);
            bytes.add(code & 0xFF);
          }
          return bytes;
        case 'GBK':
          return gbk_bytes.encode(content);
        case 'Shift-JIS':
          return shiftJis.encode(content);
        case 'Latin1':
          return latin1.encode(content);
        case 'UTF-8':
        default:
          return utf8.encode(content);
      }
    } catch (e) {
      return utf8.encode(content);
    }
  }
}