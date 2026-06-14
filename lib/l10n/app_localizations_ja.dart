// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class SJa extends S {
  SJa([String locale = 'ja']) : super(locale);

  @override
  String get appTitle => 'KikoFlu Edge';

  @override
  String get navHome => 'ホーム';

  @override
  String get navSearch => '検索';

  @override
  String get navMy => 'マイ';

  @override
  String get navSettings => '設定';

  @override
  String get offlineModeMessage =>
      'オフラインモード：ネットワーク接続に失敗しました。ダウンロード済みコンテンツのみアクセスできます';

  @override
  String get retry => '再試行';

  @override
  String get searchTypeKeyword => 'キーワード';

  @override
  String get searchTypeTag => 'タグ';

  @override
  String get searchTypeVa => '声優';

  @override
  String get searchTypeCircle => 'サークル';

  @override
  String get searchTypeRjNumber => 'RJ番号';

  @override
  String get searchHintKeyword => '作品名やキーワードを入力...';

  @override
  String get searchHintTag => 'タグ名を入力...';

  @override
  String get searchHintVa => '声優名を入力...';

  @override
  String get searchHintCircle => 'サークル名を入力...';

  @override
  String get searchHintRjNumber => '番号を入力...';

  @override
  String get ageRatingAll => 'すべて';

  @override
  String get ageRatingGeneral => '全年齢';

  @override
  String get ageRatingR15 => 'R-15';

  @override
  String get ageRatingAdult => '成人向け';

  @override
  String get salesRangeAll => 'すべて';

  @override
  String get sortRelease => '発売日';

  @override
  String get sortCreateAt => '追加日';

  @override
  String get sortCreateDate => '登録日';

  @override
  String get sortRating => '評価';

  @override
  String get sortReviewCount => 'レビュー数';

  @override
  String get sortRandom => 'ランダム';

  @override
  String get sortDlCount => '販売数';

  @override
  String get sortPrice => '価格';

  @override
  String get sortNsfw => '全年齢';

  @override
  String get sortUpdatedAt => 'マーク日時';

  @override
  String get sortAsc => '昇順';

  @override
  String get sortDesc => '降順';

  @override
  String get sortOptions => '並べ替えオプション';

  @override
  String get sortField => '並べ替え項目';

  @override
  String get sortDirection => '並べ替え方向';

  @override
  String get displayModeAll => 'すべて';

  @override
  String get displayModePopular => '人気';

  @override
  String get displayModeRecommended => 'おすすめ';

  @override
  String get subtitlePriorityHighest => '優先';

  @override
  String get subtitlePriorityLowest => '後回し';

  @override
  String get translationSourceGoogle => 'Google 翻訳';

  @override
  String get translationSourceLlm => 'LLM 翻訳';

  @override
  String get progressMarked => '気になる';

  @override
  String get progressListening => '聴取中';

  @override
  String get progressListened => '聴取済み';

  @override
  String get progressReplay => '再聴';

  @override
  String get progressPostponed => '保留';

  @override
  String get loginTitle => 'ログイン';

  @override
  String get register => '登録';

  @override
  String get addAccount => 'アカウント追加';

  @override
  String get registerAccount => 'アカウント登録';

  @override
  String get username => 'ユーザー名';

  @override
  String get password => 'パスワード';

  @override
  String get serverAddress => 'サーバーアドレス';

  @override
  String get serverCookie => 'サーバークッキー';

  @override
  String get login => 'ログイン';

  @override
  String get loginSuccess => 'ログイン成功';

  @override
  String get loginFailed => 'ログイン失敗';

  @override
  String get registerFailed => '登録失敗';

  @override
  String get usernameMinLength => 'ユーザー名は5文字以上必要です';

  @override
  String get passwordMinLength => 'パスワードは5文字以上必要です';

  @override
  String accountAdded(Object username) {
    return 'アカウント「$username」が追加されました';
  }

  @override
  String get testConnection => '接続テスト';

  @override
  String get testing => 'テスト中...';

  @override
  String get enterServerAddressToTest => 'サーバーアドレスを入力して接続テストしてください';

  @override
  String latencyMs(Object ms) {
    return '${ms}ms';
  }

  @override
  String get connectionFailed => '接続失敗';

  @override
  String get guestModeTitle => 'ゲストモードの確認';

  @override
  String get guestModeMessage =>
      'ゲストモードは機能が制限されています：\n\n• 作品のマークや評価ができません\n• プレイリストの作成ができません\n• 進捗の同期ができません\n\nゲストモードはデモアカウントでサーバーに接続するため、不安定になる場合があります。';

  @override
  String get continueGuestMode => 'ゲストモードで続行';

  @override
  String get guestAccountAdded => 'ゲストアカウントが追加されました';

  @override
  String get guestLoginFailed => 'ゲストログイン失敗';

  @override
  String get guestMode => 'ゲストモード';

  @override
  String get cancel => 'キャンセル';

  @override
  String get confirm => '確定';

  @override
  String get close => '閉じる';

  @override
  String get delete => '削除';

  @override
  String get save => '保存';

  @override
  String get edit => '編集';

  @override
  String get add => '追加';

  @override
  String get create => '作成';

  @override
  String get ok => 'OK';

  @override
  String get search => '検索';

  @override
  String get filter => 'フィルター';

  @override
  String get advancedFilter => '詳細フィルター';

  @override
  String get enterSearchContent => '検索内容を入力してください';

  @override
  String get searchTag => 'タグを検索...';

  @override
  String get minRating => '最低評価';

  @override
  String minRatingStars(Object stars) {
    return '$starsつ星';
  }

  @override
  String get searchHistory => '検索履歴';

  @override
  String get clearSearchHistory => '検索履歴をクリア';

  @override
  String get clearSearchHistoryConfirm => 'すべての検索履歴をクリアしますか？';

  @override
  String get clear => 'クリア';

  @override
  String get searchHistoryCleared => '検索履歴をクリアしました';

  @override
  String get noSearchHistory => '検索履歴はありません';

  @override
  String get excludeMode => '除外';

  @override
  String get includeMode => '含む';

  @override
  String get noResults => '結果なし';

  @override
  String get loadFailed => '読み込み失敗';

  @override
  String loadFailedWithError(Object error) {
    return '読み込み失敗: $error';
  }

  @override
  String get loading => '読み込み中...';

  @override
  String get calculating => '計算中...';

  @override
  String get getFailed => '取得失敗';

  @override
  String get settingsTitle => '設定';

  @override
  String get accountManagement => 'アカウント管理';

  @override
  String get accountManagementSubtitle => 'マルチアカウント管理、アカウント切り替え';

  @override
  String get privacyMode => 'プライバシーモード';

  @override
  String get privacyModeEnabled => '有効 - 再生情報が非表示';

  @override
  String get privacyModeDisabled => '無効';

  @override
  String get permissionManagement => '権限管理';

  @override
  String get permissionManagementSubtitle => '通知権限、バックグラウンド実行権限';

  @override
  String get desktopFloatingLyric => 'デスクトップフローティング字幕';

  @override
  String get floatingLyricEnabled => '有効 - 字幕がデスクトップに表示されます';

  @override
  String get floatingLyricDisabled => '無効';

  @override
  String get floatingLyricTouch => 'フローティング字幕ロック';

  @override
  String get floatingLyricTouchEnabled => 'ロック解除 - ドラッグ可能、長押しでロック';

  @override
  String get floatingLyricTouchDisabled => 'ロック中 - 長押しでロック解除';

  @override
  String get floatingFPS => 'FPS表示';

  @override
  String get floatingFPSEnabled => 'オン - フローティングウィンドウの左下にFPSを表示';

  @override
  String get floatingFPSDisabled => 'オフ';

  @override
  String get floatingNetworkSpeed => '通信速度表示';

  @override
  String get floatingNetworkSpeedEnabled => 'オン - フローティングウィンドウの右下に通信速度を表示';

  @override
  String get floatingNetworkSpeedDisabled => 'オフ';

  @override
  String get styleSettings => 'スタイル設定';

  @override
  String get styleSettingsSubtitle => 'フォント、色、透明度などをカスタマイズ';

  @override
  String get downloadPath => 'ダウンロードパス';

  @override
  String get downloadPathSubtitle => 'ダウンロードファイルの保存先をカスタマイズ';

  @override
  String get maxConcurrentDownloads => '最大同時ダウンロード数';

  @override
  String get maxConcurrentDownloadsSubtitle => '同時に実行するダウンロードタスクの上限';

  @override
  String get cacheManagement => 'キャッシュ管理';

  @override
  String currentCache(Object size) {
    return '現在のキャッシュ: $size';
  }

  @override
  String get themeSettings => 'テーマ設定';

  @override
  String get themeSettingsSubtitle => 'ダークモード、テーマカラーなど';

  @override
  String get uiSettings => 'UI設定';

  @override
  String get uiSettingsSubtitle => 'プレーヤー、詳細ページ、カードなど';

  @override
  String get preferenceSettings => '環境設定';

  @override
  String get preferenceSettingsSubtitle => '翻訳ソース、ブロック、オーディオ設定など';

  @override
  String get aboutTitle => 'について';

  @override
  String get unknownVersion => '不明';

  @override
  String get licenseLoadFailed => 'LICENSEファイルの読み込みに失敗しました';

  @override
  String get licenseEmpty => 'LICENSEの内容が空です';

  @override
  String get failedToLoadAbout => '概要情報の読み込みに失敗しました';

  @override
  String get newVersionFound => '新バージョンが見つかりました';

  @override
  String newVersionAvailable(Object current, Object version) {
    return '$version が利用可能です（現在: $current）';
  }

  @override
  String get versionInfo => 'バージョン情報';

  @override
  String currentVersion(Object version) {
    return '現在のバージョン: $version';
  }

  @override
  String get checkUpdate => 'アップデートを確認';

  @override
  String get author => '作者';

  @override
  String get projectRepo => 'プロジェクトリポジトリ';

  @override
  String get openSourceLicense => 'オープンソースライセンス';

  @override
  String get cannotOpenLink => 'リンクを開けません';

  @override
  String openLinkFailed(Object error) {
    return 'リンクを開けませんでした: $error';
  }

  @override
  String foundNewVersion(Object version) {
    return '新バージョン $version が見つかりました';
  }

  @override
  String get view => '表示';

  @override
  String get alreadyLatestVersion => '最新バージョンです';

  @override
  String get checkUpdateFailed => 'アップデートの確認に失敗しました。ネットワーク接続を確認してください';

  @override
  String get onlineMarks => 'オンラインマーク';

  @override
  String get historyRecord => '再生履歴';

  @override
  String get playlists => 'プレイリスト';

  @override
  String get downloaded => 'ダウンロード済み';

  @override
  String get downloadTasks => 'ダウンロードタスク';

  @override
  String get subtitleLibrary => '字幕ライブラリ';

  @override
  String get all => 'すべて';

  @override
  String get marked => '気になる';

  @override
  String get listening => '聴取中';

  @override
  String get listened => '聴取済み';

  @override
  String get replayMark => '再聴';

  @override
  String get postponed => '保留';

  @override
  String get switchToSmallGrid => '小グリッド表示に切り替え';

  @override
  String get switchToList => 'リスト表示に切り替え';

  @override
  String get switchToLargeGrid => '大グリッド表示に切り替え';

  @override
  String get sort => '並べ替え';

  @override
  String get noPlayHistory => '再生履歴はありません';

  @override
  String get clearHistory => '履歴をクリア';

  @override
  String get clearHistoryTitle => '履歴をクリア';

  @override
  String get clearHistoryConfirm => 'すべての再生履歴をクリアしますか？この操作は取り消せません。';

  @override
  String get popularNoSort => '人気モードでは並べ替えできません';

  @override
  String get recommendedNoSort => 'おすすめモードでは並べ替えできません';

  @override
  String get showAllWorks => 'すべての作品を表示';

  @override
  String get showOnlySubtitled => '字幕付き作品のみ表示';

  @override
  String selectedCount(Object count) {
    return '$count件選択中';
  }

  @override
  String get selectAll => 'すべて選択';

  @override
  String get deselectAll => '選択解除';

  @override
  String get select => '選択';

  @override
  String get noDownloadTasks => 'ダウンロードタスクはありません';

  @override
  String nFiles(Object count) {
    return '$countファイル';
  }

  @override
  String errorWithMessage(Object error) {
    return 'エラー: $error';
  }

  @override
  String get pause => '一時停止';

  @override
  String get resume => '再開';

  @override
  String get deletionConfirmTitle => '削除の確認';

  @override
  String deletionConfirmMessage(Object count) {
    return '選択した$count件のダウンロードタスクを削除しますか？ダウンロード済みファイルも削除されます。';
  }

  @override
  String deletedNFiles(Object count) {
    return '$countファイルを削除しました';
  }

  @override
  String get downloadStatusPending => '待機中';

  @override
  String get downloadStatusDownloading => 'ダウンロード中';

  @override
  String get downloadStatusCompleted => '完了';

  @override
  String get downloadStatusFailed => '失敗';

  @override
  String get downloadStatusPaused => '一時停止中';

  @override
  String translationFailed(Object error) {
    return '翻訳失敗: $error';
  }

  @override
  String copiedToClipboard(Object label, Object text) {
    return '$labelをコピーしました：$text';
  }

  @override
  String get loadingFileList => 'ファイルリストを読み込み中...';

  @override
  String loadFileListFailed(Object error) {
    return 'ファイルリストの読み込みに失敗: $error';
  }

  @override
  String get playlistTitle => 'プレイリスト';

  @override
  String get noAudioPlaying => '再生中のオーディオはありません';

  @override
  String get playbackSpeed => '再生速度';

  @override
  String get backward10s => '10秒戻る';

  @override
  String get forward10s => '10秒進む';

  @override
  String get sleepTimer => 'スリープタイマー';

  @override
  String get repeatMode => 'リピートモード';

  @override
  String get repeatOff => 'オフ';

  @override
  String get repeatOne => '1曲リピート';

  @override
  String get repeatAll => '全曲リピート';

  @override
  String get addMark => 'マーク追加';

  @override
  String get viewDetail => '詳細を見る';

  @override
  String get volume => '音量';

  @override
  String get sleepTimerTitle => 'タイマー';

  @override
  String get aboutToStop => 'まもなく停止';

  @override
  String get remainingTime => '残り時間';

  @override
  String get finishCurrentTrack => '現在のトラック終了後に停止';

  @override
  String addMinutes(Object min) {
    return '+$min分';
  }

  @override
  String get cancelTimer => 'タイマーをキャンセル';

  @override
  String get duration => '長さ';

  @override
  String get specifyTime => '時刻指定';

  @override
  String get selectTimerDuration => 'タイマーの長さを選択';

  @override
  String get selectStopTime => '再生を停止する時刻を選択';

  @override
  String get markWork => '作品をマーク';

  @override
  String get addToPlaylist => 'プレイリストに追加';

  @override
  String get remove => '削除';

  @override
  String get createPlaylist => 'プレイリストを作成';

  @override
  String get addPlaylist => 'プレイリストを追加';

  @override
  String get playlistName => 'プレイリスト名';

  @override
  String get enterPlaylistName => '名前を入力';

  @override
  String get privacySetting => 'プライバシー設定';

  @override
  String get playlistDescription => '説明（任意）';

  @override
  String get addDescription => '説明を追加';

  @override
  String get enterPlaylistNameWarning => 'プレイリスト名を入力してください';

  @override
  String get enterPlaylistLink => 'プレイリストのリンクを入力してください';

  @override
  String get switchAccountTitle => 'アカウント切り替え';

  @override
  String switchAccountConfirm(Object username) {
    return 'アカウント「$username」に切り替えますか？';
  }

  @override
  String switchedToAccount(Object username) {
    return 'アカウントを切り替えました: $username';
  }

  @override
  String get switchFailed => '切り替え失敗。アカウント情報を確認してください';

  @override
  String switchFailedWithError(Object error) {
    return '切り替え失敗: $error';
  }

  @override
  String get noAccounts => 'アカウントがありません';

  @override
  String get tapToAddAccount => '右下のボタンをタップしてアカウントを追加';

  @override
  String get currentAccount => '現在のアカウント';

  @override
  String get switchAction => '切替';

  @override
  String get deleteAccount => 'アカウント削除';

  @override
  String deleteAccountConfirm(Object username) {
    return 'アカウント「$username」を削除しますか？この操作は取り消せません。';
  }

  @override
  String get accountDeleted => 'アカウントを削除しました';

  @override
  String deletionFailedWithError(Object error) {
    return '削除失敗: $error';
  }

  @override
  String get subtitleLibraryPriority => '字幕ライブラリの優先度';

  @override
  String get selectSubtitlePriority => '自動読み込みでの字幕ライブラリの優先度を選択：';

  @override
  String get subtitlePriorityHighestDesc => '字幕ライブラリを優先して検索';

  @override
  String get subtitlePriorityLowestDesc => 'オンライン/ダウンロードを優先して検索';

  @override
  String get defaultSortSettings => 'デフォルトの並べ替え設定';

  @override
  String get defaultSortUpdated => 'デフォルトの並べ替えを更新しました';

  @override
  String get translationSourceSettings => '翻訳ソース設定';

  @override
  String get selectTranslationProvider => '翻訳サービスプロバイダーを選択：';

  @override
  String get needsConfiguration => '設定が必要';

  @override
  String get llmTranslation => 'LLM翻訳';

  @override
  String get goToConfigure => '設定へ';

  @override
  String get subtitlePrioritySettingSubtitle => '字幕ライブラリの優先度';

  @override
  String get defaultSortSettingTitle => 'ホームのデフォルト並べ替え';

  @override
  String get translationSource => '翻訳ソース';

  @override
  String get llmSettings => 'LLM設定';

  @override
  String get llmSettingsSubtitle => 'API URL、キー、モデルを設定';

  @override
  String get audioFormatPreference => 'オーディオフォーマット設定';

  @override
  String get audioFormatSubtitle => 'オーディオフォーマットの優先順位を設定';

  @override
  String get blockingSettings => 'ブロック設定';

  @override
  String get blockingSettingsSubtitle => 'ブロック中のタグ、声優、サークルを管理';

  @override
  String get audioPassthrough => 'オーディオパススルー(Beta)';

  @override
  String get audioPassthroughDescWindows => 'WASAPI排他モードを有効にしてロスレス出力（再起動が必要）';

  @override
  String get audioPassthroughDescMac => 'CoreAudio排他モードを有効にしてロスレス出力';

  @override
  String get audioPassthroughDisableDesc => 'オーディオパススルーモードを無効にする';

  @override
  String get warning => '警告';

  @override
  String get audioPassthroughWarning =>
      'この機能は十分にテストされておらず、予期しない音声出力などのリスクがあります。有効にしますか？';

  @override
  String get exclusiveModeEnabled => '排他モードを有効にしました（再起動後に反映）';

  @override
  String get audioPassthroughEnabled => 'オーディオパススルーモードを有効にしました';

  @override
  String get audioPassthroughDisabled => 'オーディオパススルーモードを無効にしました';

  @override
  String get tagVoteSupport => '賛成';

  @override
  String get tagVoteOppose => '反対';

  @override
  String get tagVoted => '投票済み';

  @override
  String get votedSupport => '賛成に投票しました';

  @override
  String get votedOppose => '反対に投票しました';

  @override
  String get voteCancelled => '投票を取り消しました';

  @override
  String voteFailed(Object error) {
    return '投票失敗: $error';
  }

  @override
  String get blockThisTag => 'このタグをブロック';

  @override
  String get copyTag => 'タグをコピー';

  @override
  String get addTag => 'タグを追加';

  @override
  String loadTagsFailed(Object error) {
    return 'タグの読み込みに失敗: $error';
  }

  @override
  String get selectAtLeastOneTag => 'タグを少なくとも1つ選択してください';

  @override
  String get tagSubmitSuccess => 'タグを送信しました、サーバー処理待ち';

  @override
  String get bindEmailFirst => 'www.asmr.one でメールアドレスを登録してください';

  @override
  String selectedNTags(Object count) {
    return '$count個のタグを選択中:';
  }

  @override
  String get noMatchingTags => '一致するタグが見つかりません';

  @override
  String get loadFailedRetry => '読み込み失敗。タップして再試行';

  @override
  String get refresh => '更新';

  @override
  String get playlistPrivacyPrivate => '非公開';

  @override
  String get playlistPrivacyUnlisted => '限定公開';

  @override
  String get playlistPrivacyPublic => '公開';

  @override
  String get systemPlaylistMarked => 'マーク済み';

  @override
  String get systemPlaylistLiked => 'お気に入り';

  @override
  String totalNWorks(Object count) {
    return '$count作品';
  }

  @override
  String pageNOfTotal(Object current, Object total) {
    return '$current / $total ページ';
  }

  @override
  String get translateTitle => '翻訳';

  @override
  String get translateDescription => '説明を翻訳';

  @override
  String get translating => '翻訳中...';

  @override
  String translationFallbackNotice(Object source) {
    return '翻訳に失敗しました。$sourceに自動切り替えしました';
  }

  @override
  String get tagLabel => 'タグ';

  @override
  String get vaLabel => '声優';

  @override
  String get circleLabel => 'サークル';

  @override
  String get releaseDate => '発売日';

  @override
  String get ratingLabel => '評価';

  @override
  String get salesLabel => '販売数';

  @override
  String get priceLabel => '価格';

  @override
  String get durationLabel => '長さ';

  @override
  String get ageRatingLabel => '年齢区分';

  @override
  String get hasSubtitle => '字幕あり';

  @override
  String get noSubtitle => '字幕なし';

  @override
  String get description => '概要';

  @override
  String get fileList => 'ファイル一覧';

  @override
  String get series => 'シリーズ';

  @override
  String get settingsLanguage => '言語';

  @override
  String get settingsLanguageSubtitle => '表示言語を切り替え';

  @override
  String get languageSystem => 'システムに従う';

  @override
  String get languageZh => '简体中文';

  @override
  String get languageZhTw => '繁體中文';

  @override
  String get languageEn => 'English';

  @override
  String get languageJa => '日本語';

  @override
  String get languageRu => 'Русский';

  @override
  String get themeModeDark => 'ダークモード';

  @override
  String get themeModeLight => 'ライトモード';

  @override
  String get themeModeSystem => 'システムに従う';

  @override
  String get themeModeTrueBlack => 'トゥルーブラック';

  @override
  String get colorSchemeOceanBlue => 'オーシャンブルー';

  @override
  String get colorSchemeForestGreen => 'フォレストグリーン';

  @override
  String get colorSchemeSunsetOrange => 'サンセットオレンジ';

  @override
  String get colorSchemeLavenderPurple => 'ラベンダーパープル';

  @override
  String get colorSchemeSakuraPink => 'サクラピンク';

  @override
  String get colorSchemeCrimsonRed => 'クリムゾンレッド';

  @override
  String get colorSchemeAmberGold => 'アンバーゴールド';

  @override
  String get colorSchemeSlateGray => 'スレートグレー';

  @override
  String get colorSchemeDynamic => 'ダイナミックカラー';

  @override
  String get noData => 'データなし';

  @override
  String get unknownError => '不明なエラー';

  @override
  String get networkError => 'ネットワークエラー';

  @override
  String get timeout => 'リクエストタイムアウト';

  @override
  String get playAll => 'すべて再生';

  @override
  String get download => 'ダウンロード';

  @override
  String get downloadAll => 'すべてダウンロード';

  @override
  String get downloading => 'ダウンロード中';

  @override
  String get downloadComplete => 'ダウンロード完了';

  @override
  String get downloadFailed => 'ダウンロード失敗';

  @override
  String get startDownload => 'ダウンロード開始';

  @override
  String get confirmDeleteDownload => 'このダウンロードタスクを削除しますか？ダウンロード済みファイルも削除されます。';

  @override
  String get deletedSuccessfully => '削除しました';

  @override
  String get scanSubtitleLibrary => '字幕ライブラリをスキャン';

  @override
  String get scanning => 'スキャン中...';

  @override
  String get scanComplete => 'スキャン完了';

  @override
  String get noSubtitleFiles => '字幕ファイルが見つかりません';

  @override
  String subtitleFilesFound(Object count) {
    return '$count個の字幕ファイルが見つかりました';
  }

  @override
  String get selectDirectory => 'ディレクトリを選択';

  @override
  String get privacyModeSettings => 'プライバシーモード設定';

  @override
  String get blurCover => 'カバーをぼかす';

  @override
  String get maskTitle => 'タイトルを隠す';

  @override
  String get customTitle => 'カスタムタイトル';

  @override
  String get privacyModeDesc => 'システム通知とメディアコントロールで再生情報を非表示にする';

  @override
  String get audioFormatSettingsTitle => 'オーディオフォーマット設定';

  @override
  String get preferredFormat => '優先フォーマット';

  @override
  String get cacheSizeLimit => 'キャッシュサイズ上限';

  @override
  String get llmApiUrl => 'API URL';

  @override
  String get llmApiKey => 'APIキー';

  @override
  String get llmModel => 'モデル';

  @override
  String get llmPrompt => 'システムプロンプト';

  @override
  String get llmConcurrency => '同時実行数';

  @override
  String get llmTestTranslation => '翻訳テスト';

  @override
  String get llmTestSuccess => 'テスト成功';

  @override
  String get llmTestFailed => 'テスト失敗';

  @override
  String get subtitleTimingAdjustment => '字幕タイミング調整';

  @override
  String get playerLyricStyle => 'プレーヤー歌詞スタイル';

  @override
  String get floatingLyricStyle => 'フローティング歌詞スタイル';

  @override
  String get fontSize => 'フォントサイズ';

  @override
  String get fontColor => 'フォントカラー';

  @override
  String get backgroundColor => '背景色';

  @override
  String get transparency => '透明度';

  @override
  String get windowSize => 'ウィンドウサイズ';

  @override
  String get playerButtonSettings => 'プレーヤーボタン設定';

  @override
  String get showButton => 'ボタンを表示';

  @override
  String get buttonOrder => 'ボタンの順序';

  @override
  String get workCardDisplaySettings => '作品カード表示設定';

  @override
  String get showTags => 'タグを表示';

  @override
  String get showVa => '声優を表示';

  @override
  String get showRating => '評価を表示';

  @override
  String get showPrice => '価格を表示';

  @override
  String get cardSize => 'カードサイズ';

  @override
  String get compact => 'コンパクト';

  @override
  String get medium => 'ミディアム';

  @override
  String get full => 'フル';

  @override
  String get workDetailDisplaySettings => '作品詳細表示設定';

  @override
  String get infoSectionVisibility => '情報セクションの表示';

  @override
  String get imageSize => '画像サイズ';

  @override
  String get showMetadata => 'メタデータを表示';

  @override
  String get relatedRecommendations => '関連作品';

  @override
  String moreFromCircle(Object circle) {
    return '$circle の他の作品';
  }

  @override
  String get myTabsDisplaySettings => '「マイ」ページ設定';

  @override
  String get showTab => 'タブを表示';

  @override
  String get tabOrder => 'タブの順序';

  @override
  String get blockedItems => 'ブロック項目';

  @override
  String get blockedTags => 'ブロック中のタグ';

  @override
  String get blockedVas => 'ブロック中の声優';

  @override
  String get blockedCircles => 'ブロック中のサークル';

  @override
  String get unblock => 'ブロック解除';

  @override
  String get noBlockedItems => 'ブロック項目はありません';

  @override
  String get clearCache => 'キャッシュをクリア';

  @override
  String get clearCacheConfirm => 'すべてのキャッシュをクリアしますか？';

  @override
  String get cacheCleared => 'キャッシュをクリアしました';

  @override
  String get imagePreview => '画像プレビュー';

  @override
  String get saveImage => '画像を保存';

  @override
  String get imageSaved => '画像を保存しました';

  @override
  String get saveImageFailed => '保存失敗';

  @override
  String get logout => 'ログアウト';

  @override
  String get logoutConfirm => 'ログアウトしますか？';

  @override
  String get openInBrowser => 'ブラウザで開く';

  @override
  String get copyLink => 'リンクをコピー';

  @override
  String get linkCopied => 'リンクをコピーしました';

  @override
  String get ratingDistribution => '評価分布';

  @override
  String reviewsCount(Object count) {
    return '$count件のレビュー';
  }

  @override
  String ratingsCount(Object count) {
    return '全 $count 件の評価';
  }

  @override
  String get myReviews => 'マイレビュー';

  @override
  String get noReviews => 'レビューはありません';

  @override
  String get writeReview => 'レビューを書く';

  @override
  String get editReview => 'レビューを編集';

  @override
  String get deleteReview => 'レビューを削除';

  @override
  String get deleteReviewConfirm => 'このレビューを削除しますか？';

  @override
  String get reviewDeleted => 'レビューを削除しました';

  @override
  String get reviewContent => 'レビュー内容';

  @override
  String get enterReviewContent => 'レビュー内容を入力...';

  @override
  String get submitReview => '送信';

  @override
  String get reviewSubmitted => 'レビューを送信しました';

  @override
  String reviewFailed(Object error) {
    return 'レビュー失敗: $error';
  }

  @override
  String get notificationPermission => '通知権限';

  @override
  String get mediaPermission => 'メディアライブラリ権限';

  @override
  String get storagePermission => 'ストレージ権限';

  @override
  String get granted => '許可済み';

  @override
  String get denied => '拒否';

  @override
  String get requestPermission => 'リクエスト';

  @override
  String get localDownloads => 'ローカルダウンロード';

  @override
  String get offlinePlayback => 'オフライン再生';

  @override
  String get noDownloadedWorks => 'ダウンロード済み作品はありません';

  @override
  String get updateAvailable => 'アップデートが利用可能です';

  @override
  String get ignoreThisVersion => 'このバージョンを無視';

  @override
  String get remindLater => '後で通知';

  @override
  String get updateNow => '今すぐアップデート';

  @override
  String get fetchFailed => '取得に失敗';

  @override
  String operationFailedWithError(Object error) {
    return '操作失敗: $error';
  }

  @override
  String get aboutSubtitle => '更新確認、ライセンスなど';

  @override
  String get currentCacheSize => '現在のキャッシュサイズ';

  @override
  String cacheLimitLabelMB(Object size) {
    return '上限: ${size}MB';
  }

  @override
  String get cacheUsagePercent => '使用率';

  @override
  String get autoCleanTitle => '自動クリーニングについて';

  @override
  String get autoCleanDescription =>
      '• キャッシュが上限を超えると自動的にクリーニングされます\n• 上限の80%まで削除します\n• LRU（最も使われていないもの）方式で削除';

  @override
  String get autoCleanDescriptionShort =>
      '• キャッシュが上限を超えると自動的にクリーニングされます\n• 上限の80%まで削除します';

  @override
  String get confirmClear => 'クリアを確認';

  @override
  String get confirmClearCacheMessage => 'すべてのキャッシュをクリアしますか？この操作は取り消せません。';

  @override
  String clearCacheFailedWithError(Object error) {
    return 'キャッシュのクリアに失敗: $error';
  }

  @override
  String get hasNewVersion => '新しいバージョン';

  @override
  String get themeMode => 'テーマモード';

  @override
  String get colorTheme => 'カラーテーマ';

  @override
  String get themePreview => 'テーマプレビュー';

  @override
  String get themeModeSystemDesc => 'システムのダーク/ライトモードに自動対応';

  @override
  String get themeModeLightDesc => '常にライトテーマを使用';

  @override
  String get themeModeDarkDesc => '常にダークテーマを使用';

  @override
  String get colorSchemeOceanBlueDesc => 'ブルー、ブルー、ブルー！';

  @override
  String get colorSchemeSakuraPinkDesc => '( ゜- ゜)つロ 乾杯~';

  @override
  String get colorSchemeSunsetOrangeDesc => 'テーマ変更は必須✍🏻✍🏻✍🏻';

  @override
  String get colorSchemeLavenderPurpleDesc => 'ブラザー、ブラザー...';

  @override
  String get colorSchemeForestGreenDesc => 'グリーン、グリーン、グリーン';

  @override
  String get colorSchemeCrimsonRedDesc => 'レッド、レッド、レッド！🔴';

  @override
  String get colorSchemeAmberGoldDesc => 'ゴールドで輝く！';

  @override
  String get colorSchemeSlateGrayDesc => 'ニュートラルでエレガント';

  @override
  String get colorSchemeDynamicDesc => 'システム壁紙の色を使用 (Android 12+)';

  @override
  String get primaryContainer => 'プライマリコンテナ';

  @override
  String get secondaryContainer => 'セカンダリコンテナ';

  @override
  String get tertiaryContainer => 'ターシャリコンテナ';

  @override
  String get surfaceColor => 'サーフェス';

  @override
  String get playerButtonSettingsSubtitle => 'プレーヤーコントロールボタンの順序をカスタマイズ';

  @override
  String get playerLyricStyleSubtitle => 'ミニプレーヤーとフルスクリーンプレーヤーの字幕スタイルをカスタマイズ';

  @override
  String get workDetailDisplaySubtitle => '作品詳細ページの表示項目を制御';

  @override
  String get workCardDisplaySubtitle => '作品カードの表示項目を制御';

  @override
  String get myTabsDisplaySubtitle => 'マイページのタブ表示を制御';

  @override
  String get pageSizeSettings => 'ページあたりの表示数';

  @override
  String pageSizeCurrent(Object size) {
    return '現在の設定: $size 件/ページ';
  }

  @override
  String currentSettingLabel(Object value) {
    return '現在: $value';
  }

  @override
  String setToValue(Object value) {
    return '設定: $value';
  }

  @override
  String get llmConfigRequiredMessage =>
      'LLM翻訳にはAPI Keyの設定が必要です。先に設定画面で設定してください。';

  @override
  String get autoSwitchedToLlm => '自動切替: LLM翻訳';

  @override
  String get translationDescGoogle => 'Googleサービスへのネットワークアクセスが必要';

  @override
  String get translationDescLlm => 'OpenAI互換API、手動でAPI Keyの設定が必要';

  @override
  String get audioPassthroughDescAndroid =>
      '外部デコーダーへの生ビットストリーム出力 (AC3/DTS) を許可。オーディオデバイスを占有する場合があります。';

  @override
  String get permissionExplanation => '権限の説明';

  @override
  String get backgroundRunningPermission => 'バックグラウンド実行権限';

  @override
  String get notificationPermissionDesc =>
      'メディア再生通知バーの表示に使用し、ロック画面や通知バーから再生を制御できます。';

  @override
  String get backgroundRunningPermissionDesc =>
      'バッテリー最適化の制限を解除し、バックグラウンドでのオーディオ再生を維持します。';

  @override
  String get notificationGrantedStatus => '許可済み - 再生通知とコントローラーを表示可能';

  @override
  String get notificationDeniedStatus => '未許可 - タップして権限を申請';

  @override
  String get backgroundGrantedStatus => '許可済み - バックグラウンドで継続実行可能';

  @override
  String get backgroundDeniedStatus => '未許可 - タップして権限を申請';

  @override
  String get notificationPermissionGranted => '通知権限が許可されました';

  @override
  String get notificationPermissionDenied => '通知権限が拒否されました';

  @override
  String requestNotificationFailed(Object error) {
    return '通知権限の申請に失敗: $error';
  }

  @override
  String get backgroundPermissionGranted => 'バックグラウンド実行権限が許可されました';

  @override
  String get backgroundPermissionDenied => 'バックグラウンド実行権限が拒否されました';

  @override
  String requestBackgroundFailed(Object error) {
    return 'バックグラウンド権限の申請に失敗: $error';
  }

  @override
  String permissionRequired(Object permission) {
    return '$permissionが必要です';
  }

  @override
  String permissionPermanentlyDenied(Object permission) {
    return '$permissionが永久に拒否されています。システム設定で手動で有効にしてください。';
  }

  @override
  String get openSettings => '設定を開く';

  @override
  String get permissionsAndroidOnly => '権限管理はAndroidでのみ利用可能です';

  @override
  String get permissionsNotNeeded => '他のプラットフォームでは手動での権限管理は不要です';

  @override
  String get refreshPermissionStatus => '権限状態を更新';

  @override
  String deleteFileConfirm(Object fileName) {
    return '「$fileName」を削除しますか？';
  }

  @override
  String deleteSelectedFilesConfirm(Object count) {
    return '選択した $count 個のファイルを削除しますか？';
  }

  @override
  String get deleted => '削除済み';

  @override
  String cannotOpenFolder(Object path) {
    return 'フォルダを開けません: $path';
  }

  @override
  String openFolderFailed(Object error) {
    return 'フォルダを開けませんでした: $error';
  }

  @override
  String get reloadingFromDisk => 'ディスクから再読み込み中...';

  @override
  String get refreshComplete => '更新完了';

  @override
  String refreshFailed(Object error) {
    return '更新失敗: $error';
  }

  @override
  String deleteSelectedWorksConfirm(Object count) {
    return '選択した $count 個の作品を削除しますか？';
  }

  @override
  String partialDeleteFailed(Object error) {
    return '一部の削除に失敗: $error';
  }

  @override
  String deletedNOfTotal(Object success, Object total) {
    return '$success/$total 個のタスクを削除';
  }

  @override
  String deleteFailedWithError(Object error) {
    return '削除失敗: $error';
  }

  @override
  String get noWorkMetadataForOffline =>
      'このダウンロードには作品詳細が保存されていないため、オフラインで表示できません';

  @override
  String openWorkDetailFailed(Object error) {
    return '作品詳細を開けませんでした: $error';
  }

  @override
  String get noLocalDownloads => 'ローカルダウンロードなし';

  @override
  String get exitSelection => '選択を終了';

  @override
  String get reload => '再読み込み';

  @override
  String get openFolder => 'フォルダを開く';

  @override
  String get playlistLink => 'プレイリストリンク';

  @override
  String get playlistLinkHint =>
      'プレイリストリンクを貼り付け、例:\nhttps://www.asmr.one/playlist?id=...';

  @override
  String get unrecognizedPlaylistLink => '認識できないプレイリストリンクまたはID';

  @override
  String get addingPlaylist => 'プレイリストを追加中...';

  @override
  String get playlistAddedSuccess => 'プレイリストの追加に成功';

  @override
  String get addFailed => '追加失敗';

  @override
  String get playlistNotFound => 'プレイリストが存在しないか、削除されています';

  @override
  String get noPermissionToAccessPlaylist => 'このプレイリストへのアクセス権限がありません';

  @override
  String get networkConnectionFailed => 'ネットワーク接続に失敗しました。接続を確認してください';

  @override
  String addFailedWithError(Object error) {
    return '追加失敗: $error';
  }

  @override
  String get creatingPlaylist => 'プレイリストを作成中...';

  @override
  String playlistCreatedSuccess(Object name) {
    return 'プレイリスト「$name」を作成しました';
  }

  @override
  String createFailedWithError(Object error) {
    return '作成失敗: $error';
  }

  @override
  String get noPlaylists => 'プレイリストなし';

  @override
  String get noPlaylistsDescription => 'プレイリストはまだ作成・お気に入り登録されていません';

  @override
  String get myPlaylists => 'マイプレイリスト';

  @override
  String totalNItems(Object count) {
    return '全 $count 件';
  }

  @override
  String get systemPlaylistCannotDelete => 'システムプレイリストは削除できません';

  @override
  String get deletePlaylist => 'プレイリストを削除';

  @override
  String get unfavoritePlaylist => 'お気に入りを解除';

  @override
  String get deletePlaylistConfirm =>
      '削除すると元に戻せません。このプレイリストをお気に入りに登録しているユーザーもアクセスできなくなります。削除しますか？';

  @override
  String unfavoritePlaylistConfirm(Object name) {
    return '「$name」のお気に入りを解除しますか？';
  }

  @override
  String get unfavorite => 'お気に入り解除';

  @override
  String get deleting => '削除中...';

  @override
  String get deleteSuccess => '削除成功';

  @override
  String get onlyOwnerCanEdit => 'プレイリストの作成者のみ編集できます';

  @override
  String get editPlaylist => 'プレイリストを編集';

  @override
  String get playlistNameRequired => 'プレイリスト名は必須です';

  @override
  String get privacyDescPrivate => '自分のみ閲覧可能';

  @override
  String get privacyDescUnlisted => 'リンクを知っている人のみ閲覧可能';

  @override
  String get privacyDescPublic => '誰でも閲覧可能';

  @override
  String get addWorks => '作品を追加';

  @override
  String get addWorksInputHint => '作品番号を含むテキストを入力、RJ番号を自動検出';

  @override
  String get workId => '作品番号';

  @override
  String get workIdHint => '例: RJ123456\nrj233333';

  @override
  String detectedNWorkIds(Object count) {
    return '$count 個の作品番号を検出';
  }

  @override
  String addNWorks(Object count) {
    return '$count 個追加';
  }

  @override
  String get noValidWorkIds => '有効な作品番号が見つかりません（RJで始まるもの）';

  @override
  String addingNWorks(Object count) {
    return '$count 個の作品を追加中...';
  }

  @override
  String addedNWorksSuccess(Object count) {
    return '$count 個の作品を追加しました';
  }

  @override
  String get removeWork => '作品を削除';

  @override
  String removeWorkConfirm(Object title) {
    return 'プレイリストから「$title」を削除しますか？';
  }

  @override
  String get removeSuccess => '削除成功';

  @override
  String removeFailedWithError(Object error) {
    return '削除失敗: $error';
  }

  @override
  String get saving => '保存中...';

  @override
  String get saveSuccess => '保存成功';

  @override
  String saveFailedWithError(Object error) {
    return '保存失敗: $error';
  }

  @override
  String get noWorks => '作品なし';

  @override
  String get playlistNoWorksDescription => 'このプレイリストにはまだ作品が追加されていません';

  @override
  String get lastUpdated => '最終更新';

  @override
  String get createdTime => '作成日';

  @override
  String nWorksCount(Object count) {
    return '$count 作品';
  }

  @override
  String nPlaysCount(Object count) {
    return '$count 再生';
  }

  @override
  String get removeFromPlaylist => 'プレイリストから削除';

  @override
  String get checkNetworkOrRetry => 'ネットワーク接続を確認するか、後で再試行してください';

  @override
  String get reachedEnd => '最後まで読みました~';

  @override
  String excludedNWorks(Object count) {
    return '$count 作品を除外';
  }

  @override
  String pageExcludedNWorks(Object count) {
    return 'このページで $count 作品を除外しました';
  }

  @override
  String get noSubtitlesAvailable => '字幕がありません';

  @override
  String get translateLyrics => '歌詞を翻訳';

  @override
  String get showOriginalLyrics => '原文を表示';

  @override
  String get showTranslatedLyrics => '翻訳を表示';

  @override
  String get translatingLyrics => '翻訳中...';

  @override
  String get lyricTranslationFailed => '歌詞の翻訳に失敗しました';

  @override
  String get unlock => 'ロック解除';

  @override
  String get backToCover => 'カバーに戻る';

  @override
  String get lyricHintTapCover => 'カバーまたはタイトルをタップして字幕画面に入る';

  @override
  String get floatingSubtitle => 'フローティング字幕';

  @override
  String get appendMode => '追加モード';

  @override
  String get appendModeStatusOn => '追加モード：オン';

  @override
  String get appendModeStatusOff => '追加モード：オフ';

  @override
  String get playlistEmpty => 'プレイリストが空です';

  @override
  String get clearQueue => 'キューをクリア';

  @override
  String get clearQueueConfirm => '再生キューをクリアしてもよろしいですか？';

  @override
  String get saveAsPlaylist => 'プレイリストとして保存';

  @override
  String get newPlaylistNameHint => 'プレイリスト名を入力';

  @override
  String get appendModeEnabled => '追加モードが有効です';

  @override
  String get appendModeHint =>
      '次にタップした音声は現在のプレイリストの末尾に追加されます。リスト全体を置き換えません。\n同じトラックは重複追加されません。';

  @override
  String get gotIt => '了解';

  @override
  String nMinutes(Object count) {
    return '$count分';
  }

  @override
  String nHours(Object count) {
    return '$count時間';
  }

  @override
  String get titleLabel => 'タイトル';

  @override
  String get rjNumberLabel => 'RJ番号';

  @override
  String get tapToViewRatingDetail => 'タップして評価詳細を表示';

  @override
  String priceInYen(Object price) {
    return '$price 円';
  }

  @override
  String soldCount(Object count) {
    return '販売数：$count';
  }

  @override
  String get circleAndVaSection => 'サークル | 声優';

  @override
  String get subtitleBadge => '字幕';

  @override
  String get otherEditions => '他のバージョン';

  @override
  String tenThousandSuffix(Object count) {
    return '$count万';
  }

  @override
  String get packingWork => '作品をパッキング中...';

  @override
  String get workDirectoryNotExist => '作品ディレクトリが存在しません';

  @override
  String get packingFailed => 'パッキング失敗';

  @override
  String exportSuccess(Object path) {
    return 'エクスポート成功：$path';
  }

  @override
  String exportFailed(Object error) {
    return 'エクスポート失敗: $error';
  }

  @override
  String get exportAsZip => 'ZIPでエクスポート';

  @override
  String get offlineBadge => 'オフライン';

  @override
  String loadFilesFailed(Object error) {
    return 'ファイルの読み込みに失敗: $error';
  }

  @override
  String get unknown => '不明';

  @override
  String get noPlayableAudioFiles => '再生可能な音声ファイルが見つかりません';

  @override
  String cannotFindAudioFile(Object title) {
    return '音声ファイルが見つかりません: $title';
  }

  @override
  String nowPlayingNOfTotal(Object current, Object title, Object total) {
    return '再生中: $title ($current/$total)';
  }

  @override
  String get noAudioCannotLoadSubtitle => '再生中の音声がないため、字幕を読み込めません';

  @override
  String get loadSubtitle => '字幕を読み込む';

  @override
  String get loadSubtitleConfirm => 'このファイルを現在の音声の字幕として読み込みますか？';

  @override
  String get subtitleFile => '字幕ファイル';

  @override
  String get currentAudio => '現在の音声';

  @override
  String get subtitleAutoRestoreNote => '他の音声に切り替えると、字幕はデフォルトのマッチングに自動復元されます';

  @override
  String get confirmLoad => '読み込み確定';

  @override
  String get loadingSubtitle => '字幕を読み込み中...';

  @override
  String subtitleLoadSuccess(Object title) {
    return '字幕読み込み成功：$title';
  }

  @override
  String subtitleLoadFailed(Object error) {
    return '字幕読み込み失敗：$error';
  }

  @override
  String get cannotPreviewImageMissingInfo => '画像をプレビューできません：必要な情報が不足';

  @override
  String get cannotFindImageFile => '画像ファイルが見つかりません';

  @override
  String get cannotPreviewTextMissingInfo => 'テキストをプレビューできません：必要な情報が不足';

  @override
  String get cannotPreviewPdfMissingInfo => 'PDFをプレビューできません：必要な情報が不足';

  @override
  String get cannotPlayVideoMissingId => '動画を再生できません：ファイルIDが不足';

  @override
  String get cannotPlayVideoMissingParams => '動画を再生できません：必要なパラメータが不足';

  @override
  String get cannotPlayDirectly => '直接再生できません';

  @override
  String get noVideoPlayerFound => '対応する動画プレーヤーが見つかりません。';

  @override
  String get youCan => '次の方法があります：';

  @override
  String get copyLinkToExternalPlayer => '1. 外部プレーヤーにリンクをコピー（MX Player、VLCなど）';

  @override
  String get openInBrowserOption => '2. ブラウザで開く';

  @override
  String playVideoError(Object error) {
    return '動画再生エラー: $error';
  }

  @override
  String get noFiles => 'ファイルがありません';

  @override
  String get resourceFiles => 'リソースファイル';

  @override
  String resourceFilesTranslated(Object count) {
    return 'リソースファイル (翻訳済み $count 項目)';
  }

  @override
  String get translationOriginal => '原';

  @override
  String get translationTranslated => '訳';

  @override
  String copiedName(Object title) {
    return '名前をコピー: $title';
  }

  @override
  String translationComplete(Object count) {
    return '翻訳完了：$count 項目';
  }

  @override
  String get noContentToTranslate => '翻訳するコンテンツがありません';

  @override
  String get preparingTranslation => '翻訳を準備中...';

  @override
  String translatingProgress(Object current, Object total) {
    return '翻訳中 $current/$total';
  }

  @override
  String nItems(Object count) {
    return '$count 項目';
  }

  @override
  String get loadAsSubtitle => '字幕として読み込む';

  @override
  String get preview => 'プレビュー';

  @override
  String openVideoFileError(Object error) {
    return '動画ファイルを開くエラー: $error';
  }

  @override
  String cannotOpenVideoFile(Object message) {
    return '動画ファイルを開けません: $message';
  }

  @override
  String get noFileTreeInfo => 'ファイルツリー情報がありません';

  @override
  String get workFolderNotExist => '作品フォルダが存在しません';

  @override
  String get cannotPlayAudioMissingId => '音声を再生できません：ファイルIDが不足';

  @override
  String get audioFileNotExist => '音声ファイルが存在しません';

  @override
  String get noPreviewableImages => 'プレビュー可能な画像が見つかりません';

  @override
  String get cannotPreviewTextMissingId => 'テキストをプレビューできません：ファイルIDが不足';

  @override
  String get cannotFindFilePath => 'ファイルパスが見つかりません';

  @override
  String fileNotExist(Object title) {
    return 'ファイルが存在しません：$title';
  }

  @override
  String get cannotPreviewPdfMissingId => 'PDFをプレビューできません：ファイルIDが不足';

  @override
  String get videoFileNotExist => '動画ファイルが存在しません';

  @override
  String get cannotOpenVideo => '動画を開けません';

  @override
  String errorInfo(Object message) {
    return 'エラー情報: $message';
  }

  @override
  String get installVideoPlayerApp =>
      '動画プレーヤーアプリをインストールしてください（VLC、MX Playerなど）';

  @override
  String get filePathLabel => 'ファイルパス：';

  @override
  String get noDownloadedFiles => 'ダウンロード済みファイルがありません';

  @override
  String get offlineFiles => 'オフラインファイル';

  @override
  String unsupportedFileType(Object title) {
    return 'このファイル形式は未対応です: $title';
  }

  @override
  String get deleteFilePrompt => 'このファイルを削除しますか？';

  @override
  String deletedItem(Object title) {
    return '削除済み: $title';
  }

  @override
  String get selectAtLeastOneFile => 'ファイルを少なくとも1つ選択してください';

  @override
  String addedNFilesToDownloadQueue(Object count) {
    return '$count ファイルをダウンロードキューに追加';
  }

  @override
  String downloadedAndSelected(Object downloaded, Object selected) {
    return 'ダウンロード済み $downloaded · 選択中 $selected';
  }

  @override
  String downloadN(Object count) {
    return 'ダウンロード ($count)';
  }

  @override
  String get checkingDownloadedFiles => 'ダウンロード済みファイルを確認中...';

  @override
  String get noDownloadableFiles => 'ダウンロード可能なファイルがありません';

  @override
  String get selectFilesToDownload => 'ダウンロードファイルを選択';

  @override
  String downloadedNCount(Object count) {
    return 'ダウンロード済み $count 個';
  }

  @override
  String selectedNCount(Object count) {
    return '選択中 $count 個';
  }

  @override
  String get pleaseEnterServerAddress => 'サーバーアドレスを入力してください';

  @override
  String get pleaseEnterUsername => 'ユーザー名を入力してください';

  @override
  String get pleaseEnterPassword => 'パスワードを入力してください';

  @override
  String get notTestedYet => '未テスト';

  @override
  String latencyResultDetail(Object latency, Object status) {
    return '遅延 $latency ($status)';
  }

  @override
  String connectionFailedWithDetail(Object error) {
    return '接続失敗: $error';
  }

  @override
  String get noAccountTapToRegister => 'アカウントがない？タップして登録';

  @override
  String get haveAccountTapToLogin => 'アカウントをお持ちですか？タップしてログイン';

  @override
  String get cannotDeleteActiveAccount => '現在使用中のアカウントは削除できません';

  @override
  String get selectAccount => 'アカウントを選択';

  @override
  String get noSavedAccounts => '保存されたアカウントがありません';

  @override
  String get addAccountToGetStarted => 'アカウントを追加して始めましょう';

  @override
  String get unknownHost => '不明なホスト';

  @override
  String lastUsedTime(Object time) {
    return '最終使用: $time';
  }

  @override
  String daysAgo(Object count) {
    return '$count日前';
  }

  @override
  String hoursAgo(Object count) {
    return '$count時間前';
  }

  @override
  String minutesAgo(Object count) {
    return '$count分前';
  }

  @override
  String get justNow => 'たった今';

  @override
  String get confirmDelete => '削除の確認';

  @override
  String deleteSelectedConfirm(Object count) {
    return '選択した $count 項目を削除しますか？';
  }

  @override
  String deletedNOfTotalItems(Object success, Object total) {
    return '$success/$total 項目を削除';
  }

  @override
  String get importingSubtitleFile => '字幕ファイルをインポート中...';

  @override
  String get preparingImport => 'インポートを準備中...';

  @override
  String get preparingExtract => '解凍を準備中...';

  @override
  String get importSubtitleFile => '字幕ファイルをインポート';

  @override
  String get supportedSubtitleFormats => '.srt, .vtt, .lrc などの字幕形式に対応';

  @override
  String get importFolder => 'フォルダをインポート';

  @override
  String get importFolderDesc => 'フォルダ構造を保持し、字幕ファイルのみインポート';

  @override
  String get importArchive => 'アーカイブをインポート';

  @override
  String get importArchiveDesc =>
      'パスワードなしZIPアーカイブに対応\n一括インポートする場合は1つのアーカイブにまとめてください';

  @override
  String get subtitleLibraryGuide => '字幕ライブラリ使用ガイド';

  @override
  String get subtitleLibraryFunction => '字幕ライブラリ機能';

  @override
  String get subtitleLibraryFunctionDesc =>
      'インポート/保存した字幕ファイルを管理し、再生時の自動/手動読み込みに対応';

  @override
  String get subtitleAutoLoad => '字幕自動読み込み';

  @override
  String get subtitleAutoLoadDesc => '音声再生時、システムが自動的に字幕ライブラリからマッチする字幕を検索：';

  @override
  String get smartCategoryAndMark => 'スマート分類とマーキング';

  @override
  String get open => '開く';

  @override
  String get moveTo => '移動先';

  @override
  String get rename => '名前変更';

  @override
  String get newName => '新しい名前';

  @override
  String get renameSuccess => '名前変更成功';

  @override
  String get renameFailed => '名前変更失敗';

  @override
  String deleteItemConfirm(Object title) {
    return '「$title」を削除しますか？';
  }

  @override
  String get deleteFolderContentsWarning => 'フォルダ内のすべてのコンテンツが削除されます。';

  @override
  String get deleteFailed => '削除失敗';

  @override
  String subtitleLoaded(Object title) {
    return '字幕を読み込みました：$title';
  }

  @override
  String get moveSuccess => '移動成功';

  @override
  String get moveFailed => '移動失敗';

  @override
  String previewFailed(Object error) {
    return 'プレビュー失敗: $error';
  }

  @override
  String openFailed(Object error) {
    return '開く失敗: $error';
  }

  @override
  String get back => '戻る';

  @override
  String get subtitleLibraryEmpty => '字幕ライブラリが空です';

  @override
  String get tapToImportSubtitle => '右下の + ボタンをタップして字幕をインポート';

  @override
  String get importSubtitle => '字幕をインポート';

  @override
  String get sampleSubtitleContent => '♪ サンプル字幕コンテンツ ♪';

  @override
  String get presetStyles => 'プリセットスタイル';

  @override
  String get backgroundOpacity => '背景の不透明度';

  @override
  String get colorSettings => '色設定';

  @override
  String get shapeSettings => '形状設定';

  @override
  String get cornerRadius => '角の半径';

  @override
  String get horizontalPadding => '水平パディング';

  @override
  String get verticalPadding => '垂直パディング';

  @override
  String get resetStyle => 'スタイルをリセット';

  @override
  String get resetStyleConfirm => 'デフォルトスタイルに戻しますか？';

  @override
  String get restoreDefaultStyle => 'デフォルトスタイルに戻す';

  @override
  String get reset => 'リセット';

  @override
  String noBlockedItemsOfType(Object type) {
    return 'ブロック中の$typeはありません';
  }

  @override
  String unblockedItem(Object item) {
    return 'ブロック解除: $item';
  }

  @override
  String addBlockedItem(Object type) {
    return '$typeをブロックに追加';
  }

  @override
  String blockedItemName(Object type) {
    return '$type名';
  }

  @override
  String enterBlockedItemHint(Object type) {
    return 'ブロックする$typeを入力';
  }

  @override
  String blockedItemAdded(Object item) {
    return 'ブロックに追加: $item';
  }

  @override
  String workCountLabel(Object count) {
    return '作品数: $count';
  }

  @override
  String get miniPlayer => 'ミニプレーヤー';

  @override
  String get lineHeight => '行の高さ';

  @override
  String get portraitPlayerBelowCover => '縦画面プレーヤー（カバー下）';

  @override
  String get fullscreenSubtitleMode => '全画面字幕（縦画面/横画面）';

  @override
  String get activeSubtitleFontSize => 'アクティブ字幕サイズ';

  @override
  String get inactiveSubtitleFontSize => 'その他の字幕サイズ';

  @override
  String get restoreDefaultSettings => 'デフォルト設定に戻す';

  @override
  String get guideInPrefix => '';

  @override
  String get guideParsedFolder => '<解析済み>';

  @override
  String get guideFindWorkDesc => 'フォルダで対応する作品を検索\nサポートされるフォルダ形式：RJ123456';

  @override
  String get guideSavedFolder => '<保存済み>';

  @override
  String get guideFindSubtitleDesc => 'フォルダで個別の字幕ファイルを検索';

  @override
  String get guideMatchRule => 'マッチルール：字幕ファイル名がオーディオファイル名と一致（拡張子の有無は問わない）';

  @override
  String get guideRecognizedWorkPrefix => '認識された作品には緑色の';

  @override
  String get guideTagSuffix => 'タグが追加され、オーディオファイルのアイコンにも';

  @override
  String get guideSubtitleMatchSuffix => 'マークが付き、字幕ライブラリとの一致を示します';

  @override
  String get guideAutoRecognizeRJ => 'インポート時にRJ形式を自動認識し、<解析済み>に分類';

  @override
  String get guideAutoAddRJPrefix =>
      '数字のみのフォルダにRJプレフィックスを自動追加（例：123456 → RJ123456）';

  @override
  String get unknownFile => '不明なファイル';

  @override
  String deleteWithCount(Object count) {
    return '削除 ($count)';
  }

  @override
  String get searchSubtitles => '字幕を検索...';

  @override
  String nFilesWithSize(Object count, Object size) {
    return '$count ファイル • $size';
  }

  @override
  String get rootDirectory => 'ルート';

  @override
  String get goToParent => '上の階層へ';

  @override
  String moveToTarget(Object name) {
    return '移動先: $name';
  }

  @override
  String get noSubfoldersHere => 'このディレクトリにサブフォルダはありません';

  @override
  String addedToPlaylist(Object name) {
    return '「$name」に追加しました';
  }

  @override
  String removedFromPlaylist(Object name) {
    return '「$name」から削除しました';
  }

  @override
  String get alreadyFavorited => 'お気に入り済み';

  @override
  String loadImageFailedWithError(Object error) {
    return '画像の読み込みに失敗\n$error';
  }

  @override
  String get noImageAvailable => '利用可能な画像はありません';

  @override
  String get storagePermissionRequiredForImage => '画像を保存するにはストレージ権限が必要です';

  @override
  String get savedToGallery => 'アルバムに保存しました';

  @override
  String get saveCoverImage => 'カバー画像を保存';

  @override
  String savedToPath(Object path) {
    return '$path に保存しました';
  }

  @override
  String get doubleTapToZoom => 'ダブルタップで拡大 · ピンチでズーム';

  @override
  String getStatusFailed(Object error) {
    return 'ステータスの取得に失敗: $error';
  }

  @override
  String get deleteRecord => '記録を削除';

  @override
  String deletePlayRecordConfirm(Object title) {
    return '\"$title\" の再生記録を削除しますか？';
  }

  @override
  String get notPlayedYet => '未再生';

  @override
  String playbackFailed(Object error) {
    return '再生失敗: $error';
  }

  @override
  String get storagePermissionRequired => 'ストレージ権限が必要';

  @override
  String get storagePermissionForGalleryDesc =>
      '画像を保存するにはフォトアルバムへのアクセス権限が必要です。設定で権限を付与してください。';

  @override
  String get goToSettings => '設定へ';

  @override
  String get imageSavedToGallery => '画像をアルバムに保存しました';

  @override
  String imageSavedToPath(Object path) {
    return '画像を保存しました: $path';
  }

  @override
  String get pullDownForNextPage => '下に引いて次のページへ';

  @override
  String get releaseForNextPage => '離して次のページへ';

  @override
  String get jumpTo => 'ジャンプ';

  @override
  String get goToPageTitle => 'ページへ移動';

  @override
  String pageNumberRange(Object max) {
    return 'ページ (1-$max)';
  }

  @override
  String get enterPageNumber => 'ページ番号を入力';

  @override
  String enterValidPageNumber(Object max) {
    return '有効なページ番号を入力してください (1-$max)';
  }

  @override
  String get previousPage => '前のページ';

  @override
  String get nextPage => '次のページ';

  @override
  String get localPdfNotExist => 'ローカルPDFファイルが存在しません';

  @override
  String get cannotOpenPdf => 'PDFファイルを開けません';

  @override
  String loadPdfFailed(Object error) {
    return 'PDFの読み込みに失敗: $error';
  }

  @override
  String pdfPageOfTotal(Object current, Object total) {
    return '$current / $total ページ';
  }

  @override
  String get loadingPdf => 'PDFを読み込み中...';

  @override
  String get pdfPathInvalid => 'PDFファイルパスが無効です';

  @override
  String get desktopPdfPreviewNotSupported => 'デスクトップでのPDFプレビューはまだサポートされていません';

  @override
  String get openWithSystemApp => 'システムデフォルトアプリで開く';

  @override
  String renderPdfFailed(Object error) {
    return 'PDFのレンダリングに失敗: $error';
  }

  @override
  String get ratingDetails => '評価詳細';

  @override
  String get selectSaveDirectory => '保存先を選択';

  @override
  String get noSubtitleContentToSave => '保存する字幕コンテンツがありません';

  @override
  String get savedToSubtitleLibrary => '字幕ライブラリに保存しました';

  @override
  String get saveToLocal => 'ローカルに保存';

  @override
  String get selectDirectoryToSaveFile => 'ファイルの保存先を選択';

  @override
  String get saveToSubtitleLibrary => '字幕ライブラリに保存';

  @override
  String get saveToSubtitleLibraryDesc => '字幕ライブラリの\"保存済み\"フォルダに保存';

  @override
  String get saveToFile => 'ファイルに保存';

  @override
  String get noContentToSave => '保存するコンテンツがありません';

  @override
  String fileSavedToPath(Object path) {
    return 'ファイルを保存しました：$path';
  }

  @override
  String get localFileNotExist => 'ローカルファイルが存在しません。再読み込みしてください';

  @override
  String loadTextFailed(Object error) {
    return 'テキストの読み込みに失敗: $error';
  }

  @override
  String get previewMode => 'プレビューモード';

  @override
  String get editMode => '編集モード';

  @override
  String get showOriginal => '原文を表示';

  @override
  String get translateContent => 'コンテンツを翻訳';

  @override
  String get editTextContentHint => 'テキストを編集...';

  @override
  String get markButton => 'マーク';

  @override
  String get bookmarkRemoved => 'ブックマークを削除しました';

  @override
  String setProgressAndRating(Object progress, Object rating) {
    return '$progressに設定、評価: $rating 星';
  }

  @override
  String setProgressTo(Object progress) {
    return '$progressに設定';
  }

  @override
  String ratingSetTo(Object rating) {
    return '評価を$rating星に設定';
  }

  @override
  String get updated => '更新しました';

  @override
  String addTagFailed(Object error) {
    return 'タグの追加に失敗: $error';
  }

  @override
  String addWithCount(Object count) {
    return '追加 ($count)';
  }

  @override
  String get undo => '元に戻す';

  @override
  String nStars(Object count) {
    return '$count 星';
  }

  @override
  String get voteRemoved => '投票を取り消しました';

  @override
  String get votedUp => '賛成票を投じました';

  @override
  String get votedDown => '反対票を投じました';

  @override
  String voteFailedWithError(Object error) {
    return '投票に失敗: $error';
  }

  @override
  String get voteFor => '賛成';

  @override
  String get voteAgainst => '反対';

  @override
  String get voted => '投票済み';

  @override
  String tagBlockedWithName(Object name) {
    return 'タグをブロックしました: $name';
  }

  @override
  String get subtitleParseFailedUnsupportedFormat => '解析失敗、サポートされていない形式';

  @override
  String get lyricPresetDynamic => 'ダイナミック';

  @override
  String get lyricPresetClassic => 'クラシック';

  @override
  String get lyricPresetModern => 'モダン';

  @override
  String get lyricPresetMinimal => 'ミニマル';

  @override
  String get lyricPresetVibrant => 'ビビッド';

  @override
  String get lyricPresetElegant => 'エレガント';

  @override
  String get lyricPresetDynamicDesc => 'システムテーマに合わせて自動配色';

  @override
  String get lyricPresetClassicDesc => '黒背景に白文字、クラシック';

  @override
  String get lyricPresetModernDesc => 'グラデーション背景、スタイリッシュ';

  @override
  String get lyricPresetMinimalDesc => '軽い透明感、シンプルで優雅';

  @override
  String get lyricPresetVibrantDesc => '鮮やかな色彩、活気あふれる';

  @override
  String get lyricPresetElegantDesc => '深いブルー、上品な雰囲気';

  @override
  String get floatingLyricLoading => '♪ 字幕を読み込み中 ♪';

  @override
  String get subtitleFileNotExist => 'ファイルが存在しません';

  @override
  String get subtitleMissingInfo => '必要な情報が不足しています';

  @override
  String get privacyDefaultTitle => 'オーディオ再生中';

  @override
  String get offlineModeStartup => 'ネットワーク接続に失敗、オフラインモードで開始';

  @override
  String get playlistInfoNotLoaded => 'プレイリスト情報が読み込まれていません';

  @override
  String get encodingUnrecognized => 'ファイルエンコーディングを認識できず、正しく表示できません';

  @override
  String editPlaylistFailed(Object error) {
    return 'プレイリストの編集に失敗: $error';
  }

  @override
  String unsupportedFileTypeWithTitle(Object title) {
    return 'このファイルタイプは開けません: $title';
  }

  @override
  String get settingsSaved => '設定を保存しました';

  @override
  String get restoredToDefault => 'デフォルト設定に復元しました';

  @override
  String get restoreDefault => 'デフォルトに戻す';

  @override
  String get saveSettings => '設定を保存';

  @override
  String get addAtLeastOneSearchCondition => '検索条件を少なくとも1つ追加してください';

  @override
  String get privacyModeSettingsTitle => 'プライバシーモード設定';

  @override
  String get whatIsPrivacyMode => 'プライバシーモードとは？';

  @override
  String get privacyModeDescription =>
      '有効にすると、システム通知やロック画面に表示される再生情報がぼかし処理され、プライバシーが保護されます。';

  @override
  String get enablePrivacyMode => 'プライバシーモードを有効にする';

  @override
  String get privacyModeEnabledSubtitle => '有効 - 再生情報が非表示になります';

  @override
  String get privacyModeDisabledSubtitle => '無効 - 再生情報が通常表示されます';

  @override
  String get blurOptions => 'ぼかしオプション';

  @override
  String get blurNotificationCover => '通知カバーをぼかす';

  @override
  String get blurNotificationCoverSubtitle =>
      'システム通知、ロック画面、コントロールセンターのカバーにぼかしを適用';

  @override
  String get blurInAppCover => 'アプリ内カバーをぼかす';

  @override
  String get blurInAppCoverSubtitle => 'プレーヤーやリストなどの画面でカバー画像をぼかす';

  @override
  String get replaceTitle => 'タイトルを置換';

  @override
  String get replaceTitleSubtitle => '実際のタイトルをカスタムタイトルに置換';

  @override
  String get replaceTitleContent => '置換タイトルの内容';

  @override
  String get setReplaceTitle => '置換タイトルを設定';

  @override
  String get enterDisplayTitle => '表示するタイトルを入力';

  @override
  String get replaceTitleSaved => '置換タイトルを保存しました';

  @override
  String get effectExample => '効果の例';

  @override
  String get downloadPathSettings => 'ダウンロードパス設定';

  @override
  String loadPathFailedWithError(Object error) {
    return 'パスの読み込みに失敗: $error';
  }

  @override
  String get platformNotSupportCustomPath =>
      'このプラットフォームではカスタムダウンロードパスはサポートされていません';

  @override
  String activeDownloadsWarning(Object count) {
    return '$count 件のダウンロードが進行中です。パスを切り替える前に完了またはキャンセルしてください';
  }

  @override
  String setPathFailedWithError(Object error) {
    return 'パスの設定に失敗: $error';
  }

  @override
  String get confirmMigrateFiles => 'ファイル移行の確認';

  @override
  String get migrateFilesToNewDir => '既存のダウンロードファイルを新しいディレクトリに移行します：';

  @override
  String get migrationMayTakeTime => 'この操作はファイルの数とサイズによって時間がかかる場合があります。';

  @override
  String get confirmMigrate => '移行を確認';

  @override
  String get restoreDefaultPath => 'デフォルトパスに戻す';

  @override
  String get restoreDefaultPathConfirm =>
      'ダウンロードパスをデフォルトの場所に戻し、すべてのファイルを移行します。\n\n続行しますか？';

  @override
  String get defaultPathRestored => 'デフォルトパスに復元しました';

  @override
  String resetPathFailedWithError(Object error) {
    return 'デフォルトパスの復元に失敗: $error';
  }

  @override
  String get migratingFiles => 'ファイルを移行中...';

  @override
  String get doNotCloseApp => 'アプリを閉じないでください';

  @override
  String get currentDownloadPath => '現在のダウンロードパス';

  @override
  String get customPath => 'カスタムパス';

  @override
  String get defaultPath => 'デフォルトパス';

  @override
  String get changeCustomPath => 'カスタムパスを変更';

  @override
  String get setCustomPath => 'カスタムパスを設定';

  @override
  String get usageInstructions => '使用方法';

  @override
  String get downloadPathUsageDesc =>
      '• パスをカスタマイズすると、既存のファイルは自動的に新しい場所に移行されます\n• 移行中はアプリを閉じないでください\n• 十分な空き容量のあるディレクトリを選択してください\n• デフォルトパスに戻すと、ファイルも自動的に戻されます';

  @override
  String get llmTranslationSettings => 'LLM翻訳設定';

  @override
  String get apiEndpointUrl => 'APIエンドポイントURL';

  @override
  String get openaiCompatibleEndpoint => 'OpenAI互換エンドポイントURL';

  @override
  String get pleaseEnterApiUrl => 'APIエンドポイントURLを入力してください';

  @override
  String get pleaseEnterValidUrl => '有効なURLを入力してください';

  @override
  String get pleaseEnterApiKey => 'APIキーを入力してください';

  @override
  String get modelName => 'モデル名';

  @override
  String get pleaseEnterModelName => 'モデル名を入力してください';

  @override
  String get concurrencyCount => '同時実行数';

  @override
  String get concurrencyDescription => '同時翻訳リクエスト数、推奨 3-5';

  @override
  String get promptSection => 'プロンプト (Prompt)';

  @override
  String get promptDescription =>
      'システムはチャンク翻訳を使用しているため、翻訳結果のみを出力し説明を含めないようプロンプトを明確にしてください。';

  @override
  String get enterSystemPrompt => 'システムプロンプトを入力...';

  @override
  String get pleaseEnterPrompt => 'プロンプトを入力してください';

  @override
  String get restoreDefaultPrompt => 'デフォルトプロンプトに戻す';

  @override
  String get confirmRestoreButtonOrder => 'デフォルトのボタン順序に戻しますか？';

  @override
  String get buttonDisplayRules => 'ボタン表示ルール';

  @override
  String buttonDisplayRulesDesc(Object maxVisible) {
    return '• 最初の $maxVisible 個のボタンがプレーヤーの下部に表示されます\n• 残りのボタンは「その他」メニューに格納されます';
  }

  @override
  String get shownInPlayer => 'プレーヤーに表示';

  @override
  String get shownInMoreMenu => 'その他メニューに表示';

  @override
  String get audioFormatPriority => 'オーディオ形式の優先順位';

  @override
  String get confirmRestoreAudioFormat => 'デフォルトのオーディオ形式優先順位に戻しますか？';

  @override
  String get priorityDescription => '優先順位の説明';

  @override
  String get audioFormatPriorityDesc =>
      '• 作品詳細ページを開くと、優先度の高い形式のオーディオフォルダが自動的に展開されます';

  @override
  String get ratingInfo => '評価情報';

  @override
  String get showRatingAndReviewCount => '作品の評価とレビュー数を表示';

  @override
  String get priceInfo => '価格情報';

  @override
  String get showWorkPrice => '作品の価格を表示';

  @override
  String get durationInfo => '再生時間情報';

  @override
  String get showWorkDuration => '作品の再生時間を表示';

  @override
  String get showWorkTotalDuration => '作品の合計再生時間を表示';

  @override
  String get salesInfo => '販売情報';

  @override
  String get showWorkSalesCount => '作品の販売数を表示';

  @override
  String get externalLinkInfo => '外部リンク情報';

  @override
  String get showExternalLinks => 'DLsiteや公式サイトなどの外部リンクを表示';

  @override
  String get releaseDateInfo => '発売日';

  @override
  String get showWorkReleaseDate => '作品の発売日を表示';

  @override
  String get translateButtonLabel => '翻訳ボタン';

  @override
  String get showTranslateButton => '作品タイトルの翻訳ボタンを表示';

  @override
  String get subtitleTagLabel => '字幕タグ';

  @override
  String get showSubtitleTagOnCover => 'カバー画像に字幕タグを表示';

  @override
  String get recommendationsLabel => '関連おすすめ';

  @override
  String get showRecommendations => '作品詳細ページに関連おすすめを表示';

  @override
  String get circleInfo => 'サークル情報';

  @override
  String get showWorkCircle => '作品のサークルを表示';

  @override
  String get showSubtitleTagOnCard => '作品カードに字幕タグを表示';

  @override
  String get showOnlineMarks => 'オンラインマークの作品を表示';

  @override
  String get showStats => '聴取統計を表示';

  @override
  String get cannotBeDisabled => '無効にできません';

  @override
  String get showPlaylists => '作成したプレイリストを表示';

  @override
  String get showSubtitleLibrary => '字幕ライブラリ管理を表示';

  @override
  String get playlistPrivacyPrivateDesc => '自分だけが閲覧可能';

  @override
  String get playlistPrivacyUnlistedDesc => 'リンクを知っている人だけが閲覧可能';

  @override
  String get playlistPrivacyPublicDesc => '誰でも閲覧可能';

  @override
  String get convertWavAfterDownload => 'WAVをFLAC/ALACに変換';

  @override
  String get convertWavAfterDownloadDesc =>
      'WAVファイルのダウンロード後、自動的にロスレスFLAC（iOSはALAC）に変換してストレージを約50%節約';

  @override
  String get convertWavAfterDownloadEnabled => '有効 — ダウンロード後にWAVを変換します';

  @override
  String get convertWavAfterDownloadDisabled => '無効 — WAVファイルをそのまま保存';

  @override
  String get convertWavFfmpegNotFound =>
      'FFmpegが見つかりません。FFmpegをインストールするか、PATHを確認してください。';

  @override
  String get convertingAudio => '音声を変換中…';

  @override
  String get clearTranslationCache => '翻訳キャッシュをクリア';

  @override
  String get translationCacheCleared => '翻訳キャッシュをクリアしました';

  @override
  String get platformHintAndroid =>
      'Android: システムのファイルピッカーを使用します。ストレージ権限が必要な場合があります';

  @override
  String get platformHintIOS =>
      'iOS: システム制限によりデフォルトパスを使用します。システムのファイルマネージャーで確認できます';

  @override
  String get platformHintWindows => 'Windows: 任意のアクセス可能なディレクトリを選択できます';

  @override
  String get platformHintMacOS => 'macOS: 任意のアクセス可能なディレクトリを選択できます';

  @override
  String get platformHintLinux => 'Linux: 任意のアクセス可能なディレクトリを選択できます';

  @override
  String get platformHintDefault => 'ダウンロードファイルを保存するディレクトリを選択してください';

  @override
  String get subtitleFolderParsed => '解析済み';

  @override
  String get subtitleFolderSaved => '保存済み';

  @override
  String get subtitleFolderUnknown => '不明な作品';

  @override
  String get sortDownloadDate => 'ダウンロード日';

  @override
  String get sortWorkId => 'ID';

  @override
  String get sortTitle => 'タイトル';

  @override
  String get searchDownloads => 'ダウンロード済み作品を検索...';

  @override
  String get logTitle => 'アプリログ';

  @override
  String get logSubtitle => 'アプリログの表示とエクスポート';

  @override
  String get logSearchHint => 'ログを検索...';

  @override
  String get logFilterAll => 'すべて';

  @override
  String get logCopy => 'ログをコピー';

  @override
  String get logExport => 'ログファイルをエクスポート';

  @override
  String get logClear => 'ログをクリア';

  @override
  String get logCopied => 'ログをクリップボードにコピーしました';

  @override
  String logExported(Object path) {
    return 'ログを $path にエクスポートしました';
  }

  @override
  String logCount(Object count) {
    return '$count 件のログ';
  }

  @override
  String get logAutoScroll => '自動スクロール';

  @override
  String get logEmpty => 'ログはありません';

  @override
  String get crossfadeTitle => 'クロスフェード';

  @override
  String crossfadeEnabledWithDuration(Object ms) {
    return 'クロスフェード: ${ms}ms';
  }

  @override
  String get gaplessPlaybackEnabled => 'ギャップレス再生（クロスフェードなし）';

  @override
  String get crossfadeDurationLabel => 'クロスフェード時間';

  @override
  String get crossfadeMinLabel => '0.5秒';

  @override
  String get crossfadeMaxLabel => '10秒';

  @override
  String get crossfadeDescription =>
      'トラック間を滑らかにフェードします。無効にするとギャップレス再生が隙間を最小限に抑えます。';

  @override
  String get equalizerTitle => 'イコライザー';

  @override
  String get equalizerEnabled => 'イコライザー有効';

  @override
  String get equalizerDisabled => 'イコライザー無効';

  @override
  String get equalizerActive => 'アクティブ';

  @override
  String get equalizerPresets => 'プリセット';

  @override
  String get equalizerCustomBands => 'カスタムバンド';

  @override
  String get equalizerCustom => 'カスタム';

  @override
  String get equalizerReset => 'フラットにリセット';

  @override
  String get equalizerNotSupported => 'このデバイスではイコライザーを利用できません';

  @override
  String get equalizerNotSupportedAndroid =>
      'オーディオセッションが初期化されていません。先にトラックを再生してください。';

  @override
  String get equalizerNotSupportedOther =>
      'このプラットフォームではハードウェアEQはサポートされていません。設定は保存されますが、サポートされた環境で適用されます。';

  @override
  String get equalizerInfo =>
      'AndroidではハードウェアオーディオエフェクトでEQが適用されます。その他のプラットフォームではEQ設定が保存されます。';

  @override
  String get searchSettings => '設定を検索...';

  @override
  String get searchSettingsTitle => '設定検索';

  @override
  String get searchSettingsComingSoon => '設定のフル検索は今後のアップデートで利用可能になります。';

  @override
  String get preferredSampleRate => '優先サンプルレート';

  @override
  String get preferredSampleRateSubtitle => 'ハイレゾ出力ターゲット (Android)';

  @override
  String get preferredSampleRateAuto => '自動（ファイルに合わせる）';

  @override
  String get preferredSampleRateDesc =>
      '出力サンプルレートを設定します。高いレートは互換性を低下させる可能性がありますが、対応DACでは品質が向上します。';

  @override
  String get settingsPlayback => '再生';

  @override
  String get settingsPlaybackSubtitle => 'イコライザー、クロスフェード、オーディオフォーマット';

  @override
  String get settingsAppearance => '外観';

  @override
  String get settingsAppearanceSubtitle => 'テーマ、言語、表示設定';

  @override
  String get settingsDownloadsStorage => 'ダウンロード＆ストレージ';

  @override
  String get settingsDownloadsStorageSubtitle => 'ダウンロードパス、キャッシュ管理';

  @override
  String get settingsPrivacyContent => 'プライバシー＆コンテンツ';

  @override
  String get settingsPrivacyContentSubtitle => 'プライバシーモード、ブロック設定';

  @override
  String get settingsTranslation => '翻訳';

  @override
  String get settingsTranslationSubtitle => '翻訳ソース、LLM設定';

  @override
  String get settingsAccount => 'アカウント';

  @override
  String get settingsAccountSubtitle => 'サーバーアカウント、フローティング字幕';

  @override
  String get settingsAdvanced => '詳細設定';

  @override
  String get settingsAdvancedSubtitle => '並べ替え順、ログ、すべての設定';

  @override
  String get settingsAboutSubtitle => 'バージョン、アップデート、ライセンス';

  @override
  String get advancedInfoBanner => 'これらの設定は初期設定後はほとんど変更されません。';

  @override
  String get advancedSectionDisplaySorting => '表示＆並べ替え';

  @override
  String get advancedDefaultSortOrderSubtitle => '発売日、タイトル、評価など';

  @override
  String get advancedMyTabsDisplaySubtitle => 'マイページのタブの表示/非表示';

  @override
  String get advancedSectionContentFiltering => 'コンテンツフィルタリング';

  @override
  String get advancedSubtitlePrioritySubtitle => '優先度の高い順と低い順';

  @override
  String get advancedSectionDebugLegacy => 'デバッグ＆レガシー';

  @override
  String get advancedAllSettingsLegacy => 'すべての設定（レガシー）';

  @override
  String get advancedAllSettingsLegacySubtitle => '従来の設定画面';

  @override
  String get hiResExclusiveMode => 'ハイレゾ専用モード';

  @override
  String get hiResExclusiveModeSubtitle => 'FLAC/WAVハイレゾトラックにネイティブExoPlayerを使用';

  @override
  String get hiResExclusiveModeDesc =>
      '有効にすると、ハイレゾトラック（FLAC/WAV >48kHz）はネイティブExoPlayerで再生されます。プレーヤー切り替え時に短い中断が発生する場合があります。';

  @override
  String get hiResExclusiveModeEnabled => 'ハイレゾ専用モードが有効になりました';

  @override
  String get hiResExclusiveModeDisabled => 'ハイレゾ専用モードが無効になりました';

  @override
  String get enable => '有効にする';

  @override
  String get listeningStatsTitle => 'リスニング統計';

  @override
  String get listeningStatsSubtitle => 'あなたの聴取習慣と履歴';

  @override
  String get statsWorksPlayed => '再生した作品';

  @override
  String get statsCompleted => '完了';

  @override
  String get statsListeningTime => '聴取時間';

  @override
  String get statsStreakDays => '連続日数';

  @override
  String get statsDays => '日';

  @override
  String get statsDailyActivity => '日別アクティビティ（14日間）';

  @override
  String get statsTopVAs => 'トップ声優';

  @override
  String get statsTopCircles => 'トップサークル';

  @override
  String get statsRecentPlays => '最近の再生';

  @override
  String get statsNoData => 'まだ統計データがありません';

  @override
  String get statsNoDataDesc => '作品を聴き始めると、統計データがここに表示されます。';

  @override
  String get statsTabDaily => '日別';

  @override
  String get statsTabWeekly => '週別';

  @override
  String get statsTabMonthly => '月別';

  @override
  String get statsWeeklyReport => '週別レポート（4週間）';

  @override
  String get statsMonthlyReport => '月別レポート（6ヶ月）';

  @override
  String get statsHeatmap => 'アクティビティヒートマップ';

  @override
  String get statsHeatmapDesc => '過去12週間の聴取アクティビティ';

  @override
  String get statsMilestones => '実績';

  @override
  String get statsMilestoneDesc => 'あなたのリスニング旅で獲得した実績';

  @override
  String get statsMilestoneFirstSteps => '最初の一歩';

  @override
  String get statsMilestoneFirstStepsDesc => '最初の作品を再生';

  @override
  String get statsMilestoneGettingStarted => '始めたばかり';

  @override
  String get statsMilestoneGettingStartedDesc => '10作品を再生';

  @override
  String get statsMilestoneListener => '熱心なリスナー';

  @override
  String get statsMilestoneListenerDesc => '50作品を再生';

  @override
  String get statsMilestoneCentury => '100作品達成';

  @override
  String get statsMilestoneCenturyDesc => '100作品を再生';

  @override
  String get statsMilestoneComplete => 'コンプリート！';

  @override
  String get statsMilestoneCompleteDesc => '最初の作品を完走';

  @override
  String get statsMilestoneDoubleDigits => '二桁突入';

  @override
  String get statsMilestoneDoubleDigitsDesc => '合計10時間聴取';

  @override
  String get statsMilestoneLongHaul => 'ロングホール';

  @override
  String get statsMilestoneLongHaulDesc => '合計50時間聴取';

  @override
  String get statsMilestoneHundredHours => '100時間クラブ';

  @override
  String get statsMilestoneHundredHoursDesc => '合計100時間聴取';

  @override
  String get statsMilestoneConsistent => '継続は力なり';

  @override
  String get statsMilestoneConsistentDesc => '7日間連続達成';

  @override
  String get statsMilestoneUnstoppable => '止められない';

  @override
  String get statsMilestoneUnstoppableDesc => '30日間連続達成';

  @override
  String get bitPerfectPlayback => 'ビットパーフェクト再生';

  @override
  String get bitPerfectPlaybackSubtitleOff => 'USB DAC検出が無効です';

  @override
  String get bitPerfectPlaybackSubtitleOn => 'libusb経由でUSB DACに直接出力';

  @override
  String get bitPerfectPlaybackSelectDevice => 'USB DACを選択';

  @override
  String get bitPerfectPlaybackSelectHint => 'USBオーディオデバイスを選択...';

  @override
  String get bitPerfectPlaybackNoDevice => 'USB DACが検出されませんでした';

  @override
  String get bitPerfectPlaybackRefreshTooltip => 'デバイス一覧を更新';

  @override
  String get bitPerfectPlaybackConfirmDesc =>
      '有効にすると、接続されたUSB DACが検出され、Androidミキサーをバイパスして直接オーディオをストリーミングできます。';

  @override
  String get bitPerfectPlaybackEnabled => 'ビットパーフェクト再生が有効になりました';

  @override
  String get bitPerfectPlaybackDisabled => 'ビットパーフェクト再生が無効になりました';

  @override
  String get bitPerfectPlaybackDeviceUpdated => 'USB DACデバイスを更新しました';

  @override
  String get bitPerfectPlaybackListRefreshed => 'USBデバイス一覧を更新しました';

  @override
  String get bitPerfectPlaybackInfoTooltip => 'ビットパーフェクト再生について';

  @override
  String get bitPerfectPlaybackInfo =>
      'ビットパーフェクト再生は、元のオーディオデータを変更せずに外部DACに送信し、最高の忠実度を実現します。\n\nAndroidのオーディオミキサーは通常すべてのオーディオを48kHzにリサンプリングし、ハイレゾコンテンツを劣化させます。このモードでは、libusbドライバーを介して接続されたUSB DACにオーディオを直接ルーティングし、Androidミキサーをバイパスします。';

  @override
  String get bitPerfectPlaybackPermissionDenied =>
      'USBパーミッションが拒否されました。設定でUSBアクセスを許可してください。';

  @override
  String get playNext => '次を再生';

  @override
  String get noAudioTracks => '音声トラックが見つかりません';

  @override
  String playingNextTracks(Object count) {
    return '次を再生中: $count トラック';
  }

  @override
  String get localFileBrowser => 'ローカルファイルブラウザ';

  @override
  String get browseFiles => 'ファイルを参照';

  @override
  String get progressSync => 'デバイス間進捗同期';

  @override
  String get progressSyncSubtitle => '再生進捗をサーバーに同期し、デバイス間でシームレスに再開';

  @override
  String get progressSyncEnabled => '有効 — 進捗がサーバーに同期されています';

  @override
  String get progressSyncDisabled => '無効';

  @override
  String get autoTranslateLyrics => '歌詞の自動翻訳';

  @override
  String get autoTranslateLyricsEnabled => '有効 — 歌詞が自動的に翻訳されます';

  @override
  String get autoTranslateLyricsDisabled => '無効';

  @override
  String autoTranslateBannerTranslating(Object language) {
    return '$language に自動翻訳中…';
  }

  @override
  String autoTranslateBannerDone(Object language) {
    return '$language に翻訳しました';
  }

  @override
  String get backupTitle => 'バックアップと復元';

  @override
  String get backupSubtitle => 'アプリデータのエクスポートまたは復元';

  @override
  String get backupInfoDescription =>
      'アカウント、設定、履歴、プレイリスト、字幕ライブラリを含むアプリデータのバックアップを作成します。いつでもバックアップファイルから復元できます。';

  @override
  String get backupExportTitle => 'エクスポート';

  @override
  String get backupExportSubtitle => 'フルバックアップを作成';

  @override
  String get backupCreateBackup => 'バックアップを作成';

  @override
  String get backupCreateBackupDesc => 'すべてのデータを.zipファイルに保存';

  @override
  String get backupExportSuccess => 'バックアップを作成しました';

  @override
  String backupSavedTo(Object path, Object size) {
    return 'バックアップ保存先：\n$path\n\nファイルサイズ：$size';
  }

  @override
  String backupExportFailed(Object error) {
    return 'バックアップ失敗：\n$error';
  }

  @override
  String get backupSelectExportDir => 'バックアップ保存先を選択';

  @override
  String get backupRestoreTitle => '復元';

  @override
  String get backupRestoreSubtitle => 'バックアップから復元';

  @override
  String get backupRestoreFromBackup => 'バックアップから復元';

  @override
  String get backupRestoreFromBackupDesc => '復元する .zip バックアップファイルを選択';

  @override
  String get backupSelectImportFile => 'バックアップファイルを選択';

  @override
  String get backupRestoreConfirmTitle => 'データを復元しますか？';

  @override
  String get backupRestoreConfirmMessage =>
      '現在のすべてのアプリデータがバックアップのデータで置き換えられます。復元後にアプリの再起動が必要です。\n\n続行しますか？';

  @override
  String get backupRestoreSuccessTitle => '復元完了';

  @override
  String get backupRestoreSuccess => 'すべてのデータが正常に復元されました。';

  @override
  String get backupRestoreWarnings => '警告：';

  @override
  String backupRestoreFailed(Object error) {
    return '復元失敗：\n$error';
  }

  @override
  String get backupRestartApp => 'アプリを再起動';

  @override
  String get backupRestartRequired => '再起動が必要です';

  @override
  String get backupRestartRequiredDesc => '復元したデータを完全に反映するにはアプリを再起動してください。';

  @override
  String get backupError => 'バックアップエラー';

  @override
  String get backupDataIncluded => '含まれるデータ';

  @override
  String get backupDatabases => 'データベース';

  @override
  String get backupHiveBoxes => 'アプリ状態';

  @override
  String get backupPreferences => '環境設定';

  @override
  String get backupAllSettings => 'すべての設定、スマートプレイリスト、環境設定';

  @override
  String get smartPlaylist => 'スマートプレイリスト';

  @override
  String get smartPlaylists => 'スマートプレイリスト';

  @override
  String get smartPlaylistSubtitle => 'ルールに基づいて自動生成';

  @override
  String get searchRules => '検索ルール';

  @override
  String activeRules(Object count) {
    return 'アクティブルール ($count)';
  }

  @override
  String get regularPlaylist => '通常プレイリスト';

  @override
  String get audioBookmarksTitle => 'ブックマーク';

  @override
  String get audioBookmarksEmpty => 'ブックマークはまだありません';

  @override
  String get audioBookmarksEmptyTrack =>
      'このトラックにはブックマークがありません。\nブックマークアイコンをタップして追加してください。';

  @override
  String get audioBookmarksHint => 'お気に入りの瞬間をブックマーク';

  @override
  String audioBookmarkAdded(Object position) {
    return '$position にブックマークを追加しました';
  }

  @override
  String get audioBookmarksView => '表示';

  @override
  String get audioBookmarksEditNote => 'メモを編集';

  @override
  String get audioBookmarksNoteHint => 'このブックマークにメモを追加...';

  @override
  String get audioBookmarksDeleteConfirm => 'このブックマークを削除しますか？';

  @override
  String get appLockTitle => 'アプリロック';

  @override
  String get appLockEnabledSubtitle => '有効 — アプリを開くには生体認証またはPINが必要です';

  @override
  String get appLockDisabledSubtitle => '無効 — 認証なしでアプリを開けます';

  @override
  String get appLockDisableConfirmTitle => 'アプリロックを無効にしますか？';

  @override
  String get appLockDisableConfirmMessage => 'アプリロック保護（生体認証とPIN）がすべて無効になります。';

  @override
  String get appLockDisable => '無効にする';

  @override
  String get appLockDisabledToast => 'アプリロックを無効にしました';

  @override
  String get appLockEnterPin => 'PINを入力';

  @override
  String get appLockAuthenticating => '認証中…';

  @override
  String get appLockWrongPin => 'PINが違います。もう一度お試しください。';

  @override
  String get appLockUseBiometric => '指紋 / Face IDを使用';

  @override
  String get appLockBiometricReason => 'KikoFlu のロック解除';

  @override
  String get appLockBiometric => '生体認証';

  @override
  String get appLockBiometricEnabledSubtitle => '有効 — 指紋または顔認証が利用可能';

  @override
  String get appLockBiometricDisabledSubtitle => '無効 — PINのみモード';

  @override
  String get appLockBiometricNotAvailable => 'このデバイスでは生体認証が利用できないか、登録されていません';

  @override
  String get appLockBiometricEnableReason => '生体認証ロックを有効にする';

  @override
  String get appLockBiometricSubtitle => 'デバイスの指紋または顔認証で素早くロック解除';

  @override
  String get appLockSetupTitle => 'アプリロックを設定';

  @override
  String get appLockSetupPinSubtitle => 'アプリを保護するPINを入力';

  @override
  String get appLockSetupConfirmSubtitle => 'PINを確認';

  @override
  String get appLockChangePin => 'PIN変更';

  @override
  String get appLockChangePinSubtitle => '新しいPINコードを設定';

  @override
  String get appLockPinMismatch => 'PINが一致しません。もう一度お試しください。';

  @override
  String get appLockPinChanged => 'PINを変更しました';

  @override
  String get appLockDigits => '桁';

  @override
  String get appLockAutoLock => '自動ロック';

  @override
  String get appLockAutoLockNever => 'ロックしない';

  @override
  String get appLockAutoLockImmediately => 'すぐに';

  @override
  String get appLockAutoLock1Min => '1分';

  @override
  String get appLockAutoLock5Min => '5分';

  @override
  String get appLockAutoLock15Min => '15分';

  @override
  String get appLockAutoLock30Min => '30分';

  @override
  String get appLockAutoLockMinutes => '分';

  @override
  String get importWork => 'Import';

  @override
  String get selectImportFolder => 'Select Folder to Import';

  @override
  String get importDialogTitle => 'Import Local Work';

  @override
  String importDialogMessage(Object path) {
    return 'Import files from:\n$path';
  }

  @override
  String get workNameTitle => 'Work Name';

  @override
  String get enterWorkName => 'Enter work name...';

  @override
  String get importAction => 'Import';

  @override
  String get importingWork => 'Importing work...';

  @override
  String get importComplete => 'Import complete';

  @override
  String importFailed(Object error) {
    return 'Import failed: $error';
  }

  @override
  String get importedWorkDeleteNotSupported =>
      'Cannot delete files from imported works. Delete the source files directly.';

  @override
  String get importSingleFolder => 'Single Folder';

  @override
  String get importSingleFolderDesc => 'Pick one folder and set a custom title';

  @override
  String get importMultipleFolders => 'Multiple Folders';

  @override
  String get importMultipleFoldersDesc =>
      'Each subfolder becomes one work (folder name = title)';

  @override
  String get selectImportFolderSingle => 'Select a folder to import';

  @override
  String get selectImportFolderMultiple =>
      'Select a folder containing sub-works';

  @override
  String get importingMultipleWorks => 'Importing works...';

  @override
  String importMultipleComplete(Object count) {
    return 'Imported $count works successfully';
  }

  @override
  String importPartialComplete(Object count, Object total) {
    return 'Imported $count/$total works';
  }

  @override
  String get aiFeatures => 'AI Features';

  @override
  String get aiFeaturesSubtitle =>
      'AI-powered transcription & lyrics generation';

  @override
  String get aiModelNotInstalled => 'AI Pack not installed';

  @override
  String get aiModelInstalled => 'AI Pack installed';

  @override
  String aiModelName(Object name) {
    return 'Model: $name';
  }

  @override
  String aiModelSize(Object size) {
    return 'Size: $size';
  }

  @override
  String get aiDownloadModel => 'Download Model';

  @override
  String aiDownloadProgress(Object percent) {
    return 'Downloading... $percent%';
  }

  @override
  String get aiDeleteModel => 'Delete Model';

  @override
  String get aiDeleteModelConfirm =>
      'Are you sure you want to delete the AI model?';

  @override
  String get aiTranscribing => 'Transcribing...';

  @override
  String get aiTranscribeComplete => 'Transcription complete';

  @override
  String aiTranscribeFailed(Object error) {
    return 'Transcription failed: $error';
  }

  @override
  String get aiGenerateLyrics => 'Generate AI Lyrics';

  @override
  String get aiModelRequired =>
      'AI model not installed. Please download it first in Settings → AI Features.';

  @override
  String get aiModelDownloadRequired => 'AI Pack Required';

  @override
  String aiModelDownloadRequiredDesc(Object size) {
    return 'AI Pack is not installed. Download Whisper Base Q5 ($size) model to generate lyrics.';
  }

  @override
  String get aiDownload => 'Download';

  @override
  String aiModelInstalledWithSize(Object name, Object size) {
    return 'Installed: $name ($size)';
  }

  @override
  String get aiStorageUsed => 'Storage Used';
}
