import 'package:flutter_test/flutter_test.dart';

/// 测试文件夹名称模式匹配
/// 匹配规则：RJ/BJ/VJ + 6-8位数字，或纯6-8位数字（不区分大小写）
bool matchFolderPattern(String folderName) {
  final patterns = [
    RegExp(r'^[RrBbVv][Jj]\d{6,8}$'),
    RegExp(r'^\d{6,8}$'),
  ];

  return patterns.any((pattern) => pattern.hasMatch(folderName));
}

void main() {
  group('文件夹名称模式匹配测试', () {
    test('RJ格式匹配测试', () {
      expect(matchFolderPattern('RJ123456'), true);
      expect(matchFolderPattern('RJ1234567'), true);
      expect(matchFolderPattern('RJ12345678'), true);
      expect(matchFolderPattern('rj123456'), true);
      expect(matchFolderPattern('Rj123456'), true);
      expect(matchFolderPattern('RJ12345'), false);
      expect(matchFolderPattern('RJ123456789'), false);
    });

    test('BJ格式匹配测试', () {
      expect(matchFolderPattern('BJ123456'), true);
      expect(matchFolderPattern('bj1234567'), true);
      expect(matchFolderPattern('BJ12345678'), true);
      expect(matchFolderPattern('Bj12345'), false);
    });

    test('VJ格式匹配测试', () {
      expect(matchFolderPattern('VJ123456'), true);
      expect(matchFolderPattern('vj1234567'), true);
      expect(matchFolderPattern('VJ12345678'), true);
      expect(matchFolderPattern('vJ12345'), false);
    });

    test('纯数字格式匹配测试', () {
      expect(matchFolderPattern('123456'), true);
      expect(matchFolderPattern('1234567'), true);
      expect(matchFolderPattern('12345678'), true);
      expect(matchFolderPattern('12345'), false);
      expect(matchFolderPattern('123456789'), false);
    });

    test('不匹配的格式测试', () {
      expect(matchFolderPattern('RJ12345a'), false);
      expect(matchFolderPattern('123456a'), false);
      expect(matchFolderPattern('ABC123456'), false);
      expect(matchFolderPattern('R123456'), false);
      expect(matchFolderPattern('RJ 123456'), false);
      expect(matchFolderPattern('RJ-123456'), false);
      expect(matchFolderPattern('Season 1'), false);
      expect(matchFolderPattern('未知作品'), false);
    });

    test('边界情况测试', () {
      expect(matchFolderPattern(''), false);
      expect(matchFolderPattern('RJ'), false);
      expect(matchFolderPattern('123'), false);
    });

    test('实际场景测试 - 多层嵌套', () {
      final testCases = {
        'RJ123456': true,
        'RJ234567': true,
        'BJ345678': true,
        'VJ456789': true,
        '12345678': true,
        'MyMusic': false,
        'Collection': false,
        'Audio': false,
      };

      testCases.forEach((folderName, shouldMatch) {
        expect(matchFolderPattern(folderName), shouldMatch,
            reason:
                '$folderName should ${shouldMatch ? "match" : "not match"}');
      });
    });
  });
}