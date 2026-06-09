<div align="center">
  <img src="assets/icons/app_icon_opaque.png" alt="KikoFlu Edge" width="120" height="120">

  # KikoFlu Edge

  [English](README_EN.md) | 日本語 | [简体中文](README.md)
  
  クロスプラットフォーム同人音声クライアント。Kikoeru 自前サーバーおよびオンラインサービスに対応。

  [![Flutter](https://img.shields.io/badge/Flutter-3.0+-02569B?logo=flutter)](https://flutter.dev)
  [![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS%20%7C%20Windows%20%7C%20macOS%20%7C%20Linux-lightgrey)](#)
  [![License](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)


</div>

<div align="center">
  <img src="screenshots/8.png" width="900" alt="KikoFlu スクリーンショット">
</div>

## 機能

### 🎵 メディア再生
- バックグラウンド再生と自動キャッシュ
- 再生速度調整
- リピート（単曲 / リスト）・シャッフル再生
- マルチフォーマット対応：音声、動画、テキスト、画像、PDF など
- 作品全体または選択的ダウンロード、並行ダウンロード管理
- オフラインダウンロードの検索・並べ替え

### 📝 字幕システム
- 字幕自動読み込み
- 字幕のインポート、編集、タイミング調整
- 再生中のリアルタイム字幕・歌詞翻訳
- 字幕ライブラリ（SQLite インデックス、高速検索）
- 保存先ディレクトリのカスタマイズ、ドライブ間コピー対応

### 🎨 インターフェース
- 全プラットフォーム対応（Android / iOS / Windows / macOS / Linux）
- Material Design 3
- 横画面モード対応
- ライト・ダークテーマ
- タイトル、ファイルディレクトリ、テキストファイルの翻訳
- タグ自動翻訳（中国語 / 英語 / 日本語）
- プライバシーモード
- 評価システム
- おすすめ作品

### 🔍 検索
- 高度な検索（複数タグ / 除外タグ対応）
- 多次元フィルタ（タグ、評価、発売日など）
- 作品情報の詳細表示

### 🌐 多言語対応
- 简体中文 / 繁體中文 / English / 日本語 / Русский

### ⚙️ 設定
- マルチアカウント対応
- カスタムサーバーアドレス（[ガイド](https://github.com/pa-jesusf/KikoFlu/wiki/%E4%BD%BF%E7%94%A8%E8%87%AA%E5%BB%BA%E5%90%8E%E7%AB%AF%E6%9C%8D%E5%8A%A1%E5%99%A8)）、接続遅延テスト可能
- キャッシュサイズ制限とクリーンアップ戦略
- テーマ・カラースキームのカスタマイズ
- 豊富な UI カスタマイズオプション
- アプリ内ログシステム（エクスポート対応）
- アップデートチェック

### 📱 Android 固有機能
- フローティング歌詞（ロック / アンロック / タッチパススルー）

---

## ダウンロード

最新バージョンは [Releases](https://github.com/pa-jesusf/KikoFlu/releases/latest) からダウンロードできます。

対応プラットフォーム：Android（universal / arm64 / armeabi-v7a / x86_64）、iOS（未署名 IPA）、Windows（インストーラー / ポータブル）、macOS（DMG）、Linux（x64 / arm64）

### AltStore / SideStore

iOS ユーザーは AltStore または SideStore にソースを追加して、KikoFlu を簡単にインストール・更新できます：

**ソース URL：** `https://raw.githubusercontent.com/pa-jesusf/KikoFlu/main/altstore-source.json`

---

## ソースからビルド

### 必要環境
- Flutter SDK 3.0+
- Dart SDK 3.0+

```bash
git clone https://github.com/pa-jesusf/KikoFlu.git
cd KikoFlu
flutter pub get
```

### ビルドコマンド

| プラットフォーム | コマンド |
|------------------|---------|
| Android | `flutter build apk --release --split-per-abi` |
| Windows | `flutter build windows --release` |
| macOS | `flutter build macos --release` |
| Linux | `flutter build linux --release` |
| iOS | `./build_ios_xcode.sh` |

---

## 関連プロジェクト

- [Kikoeru](https://github.com/Number178/kikoeru-express) — セルフホスト型バックエンドサーバー
- [asmr.one](https://www.asmr.one) — オンラインサービス

## ライセンス

[GPL-3.0 License](LICENSE)

## お問い合わせ

- **バグ報告**：[Issues](https://github.com/pa-jesusf/KikoFlu/issues)
- **コミュニティ**：[Telegram](https://t.me/+PrkiN-pZrXs4ZTU1)
