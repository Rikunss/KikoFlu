// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class SRu extends S {
  SRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'KikoFlu Edge';

  @override
  String get navHome => 'Главная';

  @override
  String get navSearch => 'Поиск';

  @override
  String get navMy => 'Моё';

  @override
  String get navSettings => 'Настройки';

  @override
  String get offlineModeMessage =>
      'Автономный режим: нет подключения к сети, доступен только загруженный контент';

  @override
  String get retry => 'Повторить';

  @override
  String get searchTypeKeyword => 'Ключевое слово';

  @override
  String get searchTypeTag => 'Тег';

  @override
  String get searchTypeVa => 'Сэйю';

  @override
  String get searchTypeCircle => 'Кружок';

  @override
  String get searchTypeRjNumber => 'Номер RJ';

  @override
  String get searchHintKeyword => 'Введите название или ключевое слово...';

  @override
  String get searchHintTag => 'Введите название тега...';

  @override
  String get searchHintVa => 'Введите имя сэйю...';

  @override
  String get searchHintCircle => 'Введите название кружка...';

  @override
  String get searchHintRjNumber => 'Введите номер...';

  @override
  String get ageRatingAll => 'Все';

  @override
  String get ageRatingGeneral => 'Для всех';

  @override
  String get ageRatingR15 => 'R-15';

  @override
  String get ageRatingAdult => '18+';

  @override
  String get salesRangeAll => 'Все';

  @override
  String get sortRelease => 'Дата выхода';

  @override
  String get sortCreateAt => 'Дата добавления';

  @override
  String get sortCreateDate => 'Дата каталога';

  @override
  String get sortRating => 'Рейтинг';

  @override
  String get sortReviewCount => 'Отзывы';

  @override
  String get sortRandom => 'Случайно';

  @override
  String get sortDlCount => 'Продажи';

  @override
  String get sortPrice => 'Цена';

  @override
  String get sortNsfw => 'Для всех';

  @override
  String get sortUpdatedAt => 'Дата отметки';

  @override
  String get sortAsc => 'По возрастанию';

  @override
  String get sortDesc => 'По убыванию';

  @override
  String get sortOptions => 'Параметры сортировки';

  @override
  String get sortField => 'Поле сортировки';

  @override
  String get sortDirection => 'Направление сортировки';

  @override
  String get displayModeAll => 'Все';

  @override
  String get displayModePopular => 'Популярное';

  @override
  String get displayModeRecommended => 'Рекомендуемое';

  @override
  String get subtitlePriorityHighest => 'Приоритет';

  @override
  String get subtitlePriorityLowest => 'Отложено';

  @override
  String get translationSourceGoogle => 'Google Переводчик';

  @override
  String get translationSourceLlm => 'LLM Переводчик';

  @override
  String get progressMarked => 'Хочу послушать';

  @override
  String get progressListening => 'Слушаю';

  @override
  String get progressListened => 'Прослушано';

  @override
  String get progressReplay => 'Переслушать';

  @override
  String get progressPostponed => 'Отложено';

  @override
  String get loginTitle => 'Вход';

  @override
  String get register => 'Регистрация';

  @override
  String get addAccount => 'Добавить аккаунт';

  @override
  String get registerAccount => 'Зарегистрировать аккаунт';

  @override
  String get username => 'Имя пользователя';

  @override
  String get password => 'Пароль';

  @override
  String get serverAddress => 'Адрес сервера';

  @override
  String get serverCookie => 'Cookie сервера';

  @override
  String get login => 'Войти';

  @override
  String get loginSuccess => 'Вход выполнен';

  @override
  String get loginFailed => 'Ошибка входа';

  @override
  String get registerFailed => 'Ошибка регистрации';

  @override
  String get usernameMinLength =>
      'Имя пользователя должно содержать не менее 5 символов';

  @override
  String get passwordMinLength => 'Пароль должен содержать не менее 5 символов';

  @override
  String accountAdded(Object username) {
    return 'Аккаунт «$username» добавлен';
  }

  @override
  String get testConnection => 'Проверить соединение';

  @override
  String get testing => 'Проверка...';

  @override
  String get enterServerAddressToTest =>
      'Введите адрес сервера для проверки соединения';

  @override
  String latencyMs(Object ms) {
    return '$msмс';
  }

  @override
  String get connectionFailed => 'Ошибка соединения';

  @override
  String get guestModeTitle => 'Подтверждение гостевого режима';

  @override
  String get guestModeMessage =>
      'Гостевой режим имеет ограничения:\n\n• Нельзя отмечать и оценивать работы\n• Нельзя создавать плейлисты\n• Нельзя синхронизировать прогресс\n\nГостевой режим использует демо-аккаунт, который может работать нестабильно.';

  @override
  String get continueGuestMode => 'Продолжить в гостевом режиме';

  @override
  String get guestAccountAdded => 'Гостевой аккаунт добавлен';

  @override
  String get guestLoginFailed => 'Ошибка гостевого входа';

  @override
  String get guestMode => 'Гостевой режим';

  @override
  String get cancel => 'Отмена';

  @override
  String get confirm => 'Подтвердить';

  @override
  String get close => 'Закрыть';

  @override
  String get delete => 'Удалить';

  @override
  String get save => 'Сохранить';

  @override
  String get edit => 'Редактировать';

  @override
  String get add => 'Добавить';

  @override
  String get create => 'Создать';

  @override
  String get ok => 'ОК';

  @override
  String get search => 'Поиск';

  @override
  String get filter => 'Фильтр';

  @override
  String get advancedFilter => 'Расширенный фильтр';

  @override
  String get enterSearchContent => 'Введите поисковый запрос';

  @override
  String get searchTag => 'Поиск тегов...';

  @override
  String get minRating => 'Мин. рейтинг';

  @override
  String minRatingStars(Object stars) {
    return '$stars звёзд';
  }

  @override
  String get searchHistory => 'История поиска';

  @override
  String get clearSearchHistory => 'Очистить историю поиска';

  @override
  String get clearSearchHistoryConfirm =>
      'Вы уверены, что хотите очистить всю историю поиска?';

  @override
  String get clear => 'Очистить';

  @override
  String get searchHistoryCleared => 'История поиска очищена';

  @override
  String get noSearchHistory => 'Нет истории поиска';

  @override
  String get excludeMode => 'Исключить';

  @override
  String get includeMode => 'Включить';

  @override
  String get noResults => 'Нет результатов';

  @override
  String get loadFailed => 'Ошибка загрузки';

  @override
  String loadFailedWithError(Object error) {
    return 'Ошибка загрузки: $error';
  }

  @override
  String get loading => 'Загрузка...';

  @override
  String get calculating => 'Вычисление...';

  @override
  String get getFailed => 'Не удалось получить';

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get accountManagement => 'Управление аккаунтами';

  @override
  String get accountManagementSubtitle => 'Управление аккаунтами, переключение';

  @override
  String get privacyMode => 'Режим конфиденциальности';

  @override
  String get privacyModeEnabled =>
      'Включён — информация о воспроизведении скрыта';

  @override
  String get privacyModeDisabled => 'Выключен';

  @override
  String get permissionManagement => 'Управление разрешениями';

  @override
  String get permissionManagementSubtitle => 'Уведомления, фоновая работа';

  @override
  String get desktopFloatingLyric => 'Плавающие субтитры';

  @override
  String get floatingLyricEnabled =>
      'Включено — субтитры отображаются на рабочем столе';

  @override
  String get floatingLyricDisabled => 'Выключено';

  @override
  String get floatingLyricTouch => 'Блокировка плавающих субтитров';

  @override
  String get floatingLyricTouchEnabled =>
      'Разблокировано — можно перетаскивать, удерживайте для блокировки';

  @override
  String get floatingLyricTouchDisabled =>
      'Заблокировано — удерживайте субтитры для разблокировки';

  @override
  String get floatingFPS => 'Показать FPS';

  @override
  String get floatingFPSEnabled =>
      'Включено — FPS в левом нижнем углу плавающего окна';

  @override
  String get floatingFPSDisabled => 'Выключено';

  @override
  String get floatingNetworkSpeed => 'Показать скорость сети';

  @override
  String get floatingNetworkSpeedEnabled =>
      'Включено — скорость в правом нижнем углу плавающего окна';

  @override
  String get floatingNetworkSpeedDisabled => 'Выключено';

  @override
  String get styleSettings => 'Настройки стиля';

  @override
  String get styleSettingsSubtitle => 'Шрифт, цвет, прозрачность и т.д.';

  @override
  String get downloadPath => 'Путь загрузки';

  @override
  String get downloadPathSubtitle =>
      'Настроить расположение загруженных файлов';

  @override
  String get maxConcurrentDownloads => 'Макс. одновременных загрузок';

  @override
  String get maxConcurrentDownloadsSubtitle =>
      'Ограничить количество одновременных задач загрузки';

  @override
  String get cacheManagement => 'Управление кешем';

  @override
  String currentCache(Object size) {
    return 'Текущий кеш: $size';
  }

  @override
  String get themeSettings => 'Настройки темы';

  @override
  String get themeSettingsSubtitle => 'Тёмный режим, цвет темы и т.д.';

  @override
  String get uiSettings => 'Настройки интерфейса';

  @override
  String get uiSettingsSubtitle => 'Плеер, страница деталей, карточки и т.д.';

  @override
  String get preferenceSettings => 'Предпочтения';

  @override
  String get preferenceSettingsSubtitle =>
      'Переводчик, блокировки, аудио и т.д.';

  @override
  String get aboutTitle => 'О приложении';

  @override
  String get unknownVersion => 'Неизвестно';

  @override
  String get licenseLoadFailed => 'Не удалось загрузить файл LICENSE';

  @override
  String get licenseEmpty => 'Файл LICENSE пуст';

  @override
  String get failedToLoadAbout => 'Не удалось загрузить информацию';

  @override
  String get newVersionFound => 'Найдена новая версия';

  @override
  String newVersionAvailable(Object current, Object version) {
    return '$version доступна (текущая: $current)';
  }

  @override
  String get versionInfo => 'Информация о версии';

  @override
  String currentVersion(Object version) {
    return 'Текущая версия: $version';
  }

  @override
  String get checkUpdate => 'Проверить обновления';

  @override
  String get author => 'Автор';

  @override
  String get projectRepo => 'Репозиторий проекта';

  @override
  String get openSourceLicense => 'Лицензия открытого ПО';

  @override
  String get cannotOpenLink => 'Не удаётся открыть ссылку';

  @override
  String openLinkFailed(Object error) {
    return 'Не удалось открыть ссылку: $error';
  }

  @override
  String foundNewVersion(Object version) {
    return 'Найдена новая версия $version';
  }

  @override
  String get view => 'Просмотр';

  @override
  String get alreadyLatestVersion => 'Установлена последняя версия';

  @override
  String get checkUpdateFailed =>
      'Не удалось проверить обновления. Проверьте подключение к сети';

  @override
  String get onlineMarks => 'Онлайн-отметки';

  @override
  String get historyRecord => 'История';

  @override
  String get playlists => 'Плейлисты';

  @override
  String get downloaded => 'Загружено';

  @override
  String get downloadTasks => 'Задачи загрузки';

  @override
  String get subtitleLibrary => 'Библиотека субтитров';

  @override
  String get all => 'Все';

  @override
  String get marked => 'Хочу послушать';

  @override
  String get listening => 'Слушаю';

  @override
  String get listened => 'Прослушано';

  @override
  String get replayMark => 'Переслушать';

  @override
  String get postponed => 'Отложено';

  @override
  String get switchToSmallGrid => 'Мелкая сетка';

  @override
  String get switchToList => 'Список';

  @override
  String get switchToLargeGrid => 'Крупная сетка';

  @override
  String get sort => 'Сортировка';

  @override
  String get noPlayHistory => 'Нет истории прослушивания';

  @override
  String get clearHistory => 'Очистить историю';

  @override
  String get clearHistoryTitle => 'Очистить историю';

  @override
  String get clearHistoryConfirm =>
      'Вы уверены, что хотите очистить всю историю? Это действие необратимо.';

  @override
  String get popularNoSort => 'В режиме «Популярное» сортировка недоступна';

  @override
  String get recommendedNoSort =>
      'В режиме «Рекомендуемое» сортировка недоступна';

  @override
  String get showAllWorks => 'Показать все работы';

  @override
  String get showOnlySubtitled => 'Только с субтитрами';

  @override
  String selectedCount(Object count) {
    return 'Выбрано: $count';
  }

  @override
  String get selectAll => 'Выбрать все';

  @override
  String get deselectAll => 'Снять выделение';

  @override
  String get select => 'Выбрать';

  @override
  String get noDownloadTasks => 'Нет задач загрузки';

  @override
  String nFiles(Object count) {
    return '$count файлов';
  }

  @override
  String errorWithMessage(Object error) {
    return 'Ошибка: $error';
  }

  @override
  String get pause => 'Пауза';

  @override
  String get resume => 'Продолжить';

  @override
  String get deletionConfirmTitle => 'Подтвердить удаление';

  @override
  String deletionConfirmMessage(Object count) {
    return 'Удалить $count выбранных задач загрузки? Загруженные файлы тоже будут удалены.';
  }

  @override
  String deletedNFiles(Object count) {
    return 'Удалено файлов: $count';
  }

  @override
  String get downloadStatusPending => 'Ожидание';

  @override
  String get downloadStatusDownloading => 'Загрузка';

  @override
  String get downloadStatusCompleted => 'Завершено';

  @override
  String get downloadStatusFailed => 'Ошибка';

  @override
  String get downloadStatusPaused => 'Приостановлено';

  @override
  String translationFailed(Object error) {
    return 'Ошибка перевода: $error';
  }

  @override
  String copiedToClipboard(Object label, Object text) {
    return 'Скопировано $label: $text';
  }

  @override
  String get loadingFileList => 'Загрузка списка файлов...';

  @override
  String loadFileListFailed(Object error) {
    return 'Не удалось загрузить список файлов: $error';
  }

  @override
  String get playlistTitle => 'Плейлист';

  @override
  String get noAudioPlaying => 'Нет воспроизводимого аудио';

  @override
  String get playbackSpeed => 'Скорость воспроизведения';

  @override
  String get backward10s => 'Назад 10 сек';

  @override
  String get forward10s => 'Вперёд 10 сек';

  @override
  String get sleepTimer => 'Таймер сна';

  @override
  String get repeatMode => 'Режим повтора';

  @override
  String get repeatOff => 'Выкл';

  @override
  String get repeatOne => 'Один трек';

  @override
  String get repeatAll => 'Весь список';

  @override
  String get addMark => 'Добавить отметку';

  @override
  String get viewDetail => 'Подробнее';

  @override
  String get volume => 'Громкость';

  @override
  String get sleepTimerTitle => 'Таймер';

  @override
  String get aboutToStop => 'Скоро остановится';

  @override
  String get remainingTime => 'Оставшееся время';

  @override
  String get finishCurrentTrack => 'Остановить после текущего трека';

  @override
  String addMinutes(Object min) {
    return '+$min мин';
  }

  @override
  String get cancelTimer => 'Отменить таймер';

  @override
  String get duration => 'Длительность';

  @override
  String get specifyTime => 'Указать время';

  @override
  String get selectTimerDuration => 'Выберите длительность таймера';

  @override
  String get selectStopTime => 'Выберите время остановки';

  @override
  String get markWork => 'Отметить работу';

  @override
  String get addToPlaylist => 'Добавить в плейлист';

  @override
  String get remove => 'Удалить';

  @override
  String get createPlaylist => 'Создать плейлист';

  @override
  String get addPlaylist => 'Добавить плейлист';

  @override
  String get playlistName => 'Название плейлиста';

  @override
  String get enterPlaylistName => 'Введите название';

  @override
  String get privacySetting => 'Конфиденциальность';

  @override
  String get playlistDescription => 'Описание (необязательно)';

  @override
  String get addDescription => 'Добавить описание';

  @override
  String get enterPlaylistNameWarning => 'Введите название плейлиста';

  @override
  String get enterPlaylistLink => 'Введите ссылку на плейлист';

  @override
  String get switchAccountTitle => 'Переключить аккаунт';

  @override
  String switchAccountConfirm(Object username) {
    return 'Переключиться на аккаунт «$username»?';
  }

  @override
  String switchedToAccount(Object username) {
    return 'Переключено на аккаунт: $username';
  }

  @override
  String get switchFailed =>
      'Не удалось переключиться. Проверьте данные аккаунта';

  @override
  String switchFailedWithError(Object error) {
    return 'Ошибка переключения: $error';
  }

  @override
  String get noAccounts => 'Нет аккаунтов';

  @override
  String get tapToAddAccount =>
      'Нажмите кнопку внизу справа, чтобы добавить аккаунт';

  @override
  String get currentAccount => 'Текущий аккаунт';

  @override
  String get switchAction => 'Переключить';

  @override
  String get deleteAccount => 'Удалить аккаунт';

  @override
  String deleteAccountConfirm(Object username) {
    return 'Удалить аккаунт «$username»? Это действие необратимо.';
  }

  @override
  String get accountDeleted => 'Аккаунт удалён';

  @override
  String deletionFailedWithError(Object error) {
    return 'Ошибка удаления: $error';
  }

  @override
  String get subtitleLibraryPriority => 'Приоритет библиотеки субтитров';

  @override
  String get selectSubtitlePriority =>
      'Выберите приоритет библиотеки субтитров при автозагрузке:';

  @override
  String get subtitlePriorityHighestDesc =>
      'Сначала искать в библиотеке, потом онлайн/загрузки';

  @override
  String get subtitlePriorityLowestDesc =>
      'Сначала искать онлайн/загрузки, потом в библиотеке';

  @override
  String get defaultSortSettings => 'Сортировка по умолчанию';

  @override
  String get defaultSortUpdated => 'Сортировка по умолчанию обновлена';

  @override
  String get translationSourceSettings => 'Настройки переводчика';

  @override
  String get selectTranslationProvider => 'Выберите службу перевода:';

  @override
  String get needsConfiguration => 'Требуется настройка';

  @override
  String get llmTranslation => 'LLM перевод';

  @override
  String get goToConfigure => 'Настроить';

  @override
  String get subtitlePrioritySettingSubtitle =>
      'Приоритет библиотеки субтитров';

  @override
  String get defaultSortSettingTitle => 'Сортировка на главной по умолчанию';

  @override
  String get translationSource => 'Источник перевода';

  @override
  String get llmSettings => 'Настройки LLM';

  @override
  String get llmSettingsSubtitle => 'API URL, ключ и модель';

  @override
  String get audioFormatPreference => 'Аудиоформат';

  @override
  String get audioFormatSubtitle => 'Приоритет аудиоформатов';

  @override
  String get blockingSettings => 'Блокировки';

  @override
  String get blockingSettingsSubtitle => 'Заблокированные теги, сэйю и кружки';

  @override
  String get audioPassthrough => 'Аудио-проход (Beta)';

  @override
  String get audioPassthroughDescWindows =>
      'Включить эксклюзивный режим WASAPI для lossless (требуется перезапуск)';

  @override
  String get audioPassthroughDescMac =>
      'Включить эксклюзивный режим CoreAudio для lossless';

  @override
  String get audioPassthroughDisableDesc => 'Отключить режим аудио-прохода';

  @override
  String get warning => 'Предупреждение';

  @override
  String get audioPassthroughWarning =>
      'Эта функция не полностью протестирована и может вызвать неожиданный вывод звука. Включить?';

  @override
  String get exclusiveModeEnabled =>
      'Эксклюзивный режим включён (применится после перезапуска)';

  @override
  String get audioPassthroughEnabled => 'Режим аудио-прохода включён';

  @override
  String get audioPassthroughDisabled => 'Режим аудио-прохода отключён';

  @override
  String get tagVoteSupport => 'За';

  @override
  String get tagVoteOppose => 'Против';

  @override
  String get tagVoted => 'Проголосовано';

  @override
  String get votedSupport => 'Вы проголосовали «за»';

  @override
  String get votedOppose => 'Вы проголосовали «против»';

  @override
  String get voteCancelled => 'Голос отменён';

  @override
  String voteFailed(Object error) {
    return 'Ошибка голосования: $error';
  }

  @override
  String get blockThisTag => 'Заблокировать этот тег';

  @override
  String get copyTag => 'Копировать тег';

  @override
  String get addTag => 'Добавить тег';

  @override
  String loadTagsFailed(Object error) {
    return 'Не удалось загрузить теги: $error';
  }

  @override
  String get selectAtLeastOneTag => 'Выберите хотя бы один тег';

  @override
  String get tagSubmitSuccess =>
      'Теги отправлены, ожидается обработка сервером';

  @override
  String get bindEmailFirst => 'Пожалуйста, привяжите email на www.asmr.one';

  @override
  String selectedNTags(Object count) {
    return 'Выбрано тегов: $count:';
  }

  @override
  String get noMatchingTags => 'Нет совпадающих тегов';

  @override
  String get loadFailedRetry => 'Ошибка загрузки. Нажмите для повтора';

  @override
  String get refresh => 'Обновить';

  @override
  String get playlistPrivacyPrivate => 'Приватный';

  @override
  String get playlistPrivacyUnlisted => 'По ссылке';

  @override
  String get playlistPrivacyPublic => 'Публичный';

  @override
  String get systemPlaylistMarked => 'Отмеченное';

  @override
  String get systemPlaylistLiked => 'Понравившееся';

  @override
  String totalNWorks(Object count) {
    return '$count работ';
  }

  @override
  String pageNOfTotal(Object current, Object total) {
    return 'Страница $current / $total';
  }

  @override
  String get translateTitle => 'Перевести';

  @override
  String get translateDescription => 'Перевести описание';

  @override
  String get translating => 'Перевод...';

  @override
  String translationFallbackNotice(Object source) {
    return 'Перевод не удался, автоматически переключено на $source';
  }

  @override
  String get tagLabel => 'Теги';

  @override
  String get vaLabel => 'Сэйю';

  @override
  String get circleLabel => 'Кружок';

  @override
  String get releaseDate => 'Дата выхода';

  @override
  String get ratingLabel => 'Рейтинг';

  @override
  String get salesLabel => 'Продажи';

  @override
  String get priceLabel => 'Цена';

  @override
  String get durationLabel => 'Длительность';

  @override
  String get ageRatingLabel => 'Возрастной рейтинг';

  @override
  String get hasSubtitle => 'С субтитрами';

  @override
  String get noSubtitle => 'Без субтитров';

  @override
  String get description => 'Описание';

  @override
  String get fileList => 'Список файлов';

  @override
  String get series => 'Серия';

  @override
  String get settingsLanguage => 'Язык';

  @override
  String get settingsLanguageSubtitle => 'Переключить язык интерфейса';

  @override
  String get languageSystem => 'Системный';

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
  String get themeModeDark => 'Тёмный режим';

  @override
  String get themeModeLight => 'Светлый режим';

  @override
  String get themeModeSystem => 'Системный';

  @override
  String get themeModeTrueBlack => 'Абсолютно чёрный';

  @override
  String get colorSchemeOceanBlue => 'Океанский синий';

  @override
  String get colorSchemeForestGreen => 'Лесной зелёный';

  @override
  String get colorSchemeSunsetOrange => 'Закатный оранжевый';

  @override
  String get colorSchemeLavenderPurple => 'Лавандовый';

  @override
  String get colorSchemeSakuraPink => 'Сакура';

  @override
  String get colorSchemeCrimsonRed => 'Красный';

  @override
  String get colorSchemeAmberGold => 'Янтарный';

  @override
  String get colorSchemeSlateGray => 'Серый';

  @override
  String get colorSchemeDynamic => 'Динамический цвет';

  @override
  String get noData => 'Нет данных';

  @override
  String get unknownError => 'Неизвестная ошибка';

  @override
  String get networkError => 'Ошибка сети';

  @override
  String get timeout => 'Время ожидания истекло';

  @override
  String get playAll => 'Воспроизвести всё';

  @override
  String get download => 'Скачать';

  @override
  String get downloadAll => 'Скачать всё';

  @override
  String get downloading => 'Загрузка';

  @override
  String get downloadComplete => 'Загрузка завершена';

  @override
  String get downloadFailed => 'Ошибка загрузки';

  @override
  String get startDownload => 'Начать загрузку';

  @override
  String get confirmDeleteDownload =>
      'Удалить эту загрузку? Загруженные файлы тоже будут удалены.';

  @override
  String get deletedSuccessfully => 'Удалено';

  @override
  String get scanSubtitleLibrary => 'Сканировать библиотеку';

  @override
  String get scanning => 'Сканирование...';

  @override
  String get scanComplete => 'Сканирование завершено';

  @override
  String get noSubtitleFiles => 'Файлы субтитров не найдены';

  @override
  String subtitleFilesFound(Object count) {
    return 'Найдено файлов субтитров: $count';
  }

  @override
  String get selectDirectory => 'Выбрать каталог';

  @override
  String get privacyModeSettings => 'Режим конфиденциальности';

  @override
  String get blurCover => 'Размыть обложку';

  @override
  String get maskTitle => 'Скрыть заголовок';

  @override
  String get customTitle => 'Пользовательский заголовок';

  @override
  String get privacyModeDesc =>
      'Скрыть информацию о воспроизведении в уведомлениях и медиа-управлении';

  @override
  String get audioFormatSettingsTitle => 'Настройки аудиоформата';

  @override
  String get preferredFormat => 'Предпочтительный формат';

  @override
  String get cacheSizeLimit => 'Лимит кеша';

  @override
  String get llmApiUrl => 'API URL';

  @override
  String get llmApiKey => 'API-ключ';

  @override
  String get llmModel => 'Модель';

  @override
  String get llmPrompt => 'Системный промпт';

  @override
  String get llmConcurrency => 'Параллелизм';

  @override
  String get llmTestTranslation => 'Тест перевода';

  @override
  String get llmTestSuccess => 'Тест успешен';

  @override
  String get llmTestFailed => 'Тест не пройден';

  @override
  String get subtitleTimingAdjustment => 'Настройка тайминга субтитров';

  @override
  String get playerLyricStyle => 'Стиль текста в плеере';

  @override
  String get floatingLyricStyle => 'Стиль плавающего текста';

  @override
  String get fontSize => 'Размер шрифта';

  @override
  String get fontColor => 'Цвет шрифта';

  @override
  String get backgroundColor => 'Цвет фона';

  @override
  String get transparency => 'Прозрачность';

  @override
  String get windowSize => 'Размер окна';

  @override
  String get playerButtonSettings => 'Кнопки плеера';

  @override
  String get showButton => 'Показать кнопку';

  @override
  String get buttonOrder => 'Порядок кнопок';

  @override
  String get workCardDisplaySettings =>
      'Настройки отображения карточек произведений';

  @override
  String get showTags => 'Показывать теги';

  @override
  String get showVa => 'Показывать сэйю';

  @override
  String get showRating => 'Показывать рейтинг';

  @override
  String get showPrice => 'Показывать цену';

  @override
  String get cardSize => 'Размер карточки';

  @override
  String get compact => 'Компактный';

  @override
  String get medium => 'Средний';

  @override
  String get full => 'Полный';

  @override
  String get workDetailDisplaySettings =>
      'Настройки отображения деталей произведения';

  @override
  String get infoSectionVisibility => 'Видимость разделов';

  @override
  String get imageSize => 'Размер изображения';

  @override
  String get showMetadata => 'Показывать метаданные';

  @override
  String get relatedRecommendations => 'Похожие работы';

  @override
  String moreFromCircle(Object circle) {
    return 'Ещё от $circle';
  }

  @override
  String get myTabsDisplaySettings => 'Настройки страницы «Моё»';

  @override
  String get showTab => 'Показать вкладку';

  @override
  String get tabOrder => 'Порядок вкладок';

  @override
  String get blockedItems => 'Заблокировано';

  @override
  String get blockedTags => 'Заблокированные теги';

  @override
  String get blockedVas => 'Заблокированные сэйю';

  @override
  String get blockedCircles => 'Заблокированные кружки';

  @override
  String get unblock => 'Разблокировать';

  @override
  String get noBlockedItems => 'Нет заблокированных элементов';

  @override
  String get clearCache => 'Очистить кеш';

  @override
  String get clearCacheConfirm => 'Очистить весь кеш?';

  @override
  String get cacheCleared => 'Кеш очищен';

  @override
  String get imagePreview => 'Просмотр изображения';

  @override
  String get saveImage => 'Сохранить изображение';

  @override
  String get imageSaved => 'Изображение сохранено';

  @override
  String get saveImageFailed => 'Ошибка сохранения';

  @override
  String get logout => 'Выход';

  @override
  String get logoutConfirm => 'Выйти из аккаунта?';

  @override
  String get openInBrowser => 'Открыть в браузере';

  @override
  String get copyLink => 'Копировать ссылку';

  @override
  String get linkCopied => 'Ссылка скопирована';

  @override
  String get ratingDistribution => 'Распределение оценок';

  @override
  String reviewsCount(Object count) {
    return 'Отзывов: $count';
  }

  @override
  String ratingsCount(Object count) {
    return 'Всего $count оценок';
  }

  @override
  String get myReviews => 'Мои отзывы';

  @override
  String get noReviews => 'Нет отзывов';

  @override
  String get writeReview => 'Написать отзыв';

  @override
  String get editReview => 'Редактировать отзыв';

  @override
  String get deleteReview => 'Удалить отзыв';

  @override
  String get deleteReviewConfirm => 'Удалить этот отзыв?';

  @override
  String get reviewDeleted => 'Отзыв удалён';

  @override
  String get reviewContent => 'Текст отзыва';

  @override
  String get enterReviewContent => 'Введите текст отзыва...';

  @override
  String get submitReview => 'Отправить';

  @override
  String get reviewSubmitted => 'Отзыв отправлен';

  @override
  String reviewFailed(Object error) {
    return 'Ошибка отзыва: $error';
  }

  @override
  String get notificationPermission => 'Разрешение уведомлений';

  @override
  String get mediaPermission => 'Медиатека';

  @override
  String get storagePermission => 'Хранилище';

  @override
  String get granted => 'Разрешено';

  @override
  String get denied => 'Отказано';

  @override
  String get requestPermission => 'Запросить';

  @override
  String get localDownloads => 'Локальные загрузки';

  @override
  String get offlinePlayback => 'Автономное воспроизведение';

  @override
  String get noDownloadedWorks => 'Нет загруженных работ';

  @override
  String get updateAvailable => 'Доступно обновление';

  @override
  String get ignoreThisVersion => 'Пропустить эту версию';

  @override
  String get remindLater => 'Напомнить позже';

  @override
  String get updateNow => 'Обновить сейчас';

  @override
  String get fetchFailed => 'Не удалось получить';

  @override
  String operationFailedWithError(Object error) {
    return 'Ошибка операции: $error';
  }

  @override
  String get aboutSubtitle => 'Проверка обновлений, лицензии и др.';

  @override
  String get currentCacheSize => 'Текущий размер кэша';

  @override
  String cacheLimitLabelMB(Object size) {
    return 'Лимит: $sizeМБ';
  }

  @override
  String get cacheUsagePercent => 'Использование';

  @override
  String get autoCleanTitle => 'Автоочистка';

  @override
  String get autoCleanDescription =>
      '• Кэш автоматически очищается при превышении лимита\n• Удаление до 80% от лимита\n• Используется стратегия LRU (наименее используемые)';

  @override
  String get autoCleanDescriptionShort =>
      '• Кэш автоматически очищается при превышении лимита\n• Удаление до 80% от лимита';

  @override
  String get confirmClear => 'Подтвердить очистку';

  @override
  String get confirmClearCacheMessage =>
      'Вы уверены, что хотите очистить весь кэш? Это действие нельзя отменить.';

  @override
  String clearCacheFailedWithError(Object error) {
    return 'Ошибка очистки кэша: $error';
  }

  @override
  String get hasNewVersion => 'Новая версия';

  @override
  String get themeMode => 'Режим темы';

  @override
  String get colorTheme => 'Цветовая тема';

  @override
  String get themePreview => 'Предпросмотр темы';

  @override
  String get themeModeSystemDesc => 'Автоматическая адаптация к системной теме';

  @override
  String get themeModeLightDesc => 'Всегда использовать светлую тему';

  @override
  String get themeModeDarkDesc => 'Всегда использовать тёмную тему';

  @override
  String get colorSchemeOceanBlueDesc => 'Синий, синий, синий!';

  @override
  String get colorSchemeSakuraPinkDesc => '( ゜- ゜)つロ Ура~';

  @override
  String get colorSchemeSunsetOrangeDesc => 'Смена тем — обязательно ✍🏻✍🏻✍🏻';

  @override
  String get colorSchemeLavenderPurpleDesc => 'Братан, братан...';

  @override
  String get colorSchemeForestGreenDesc => 'Зелень, зелень, зелень';

  @override
  String get colorSchemeCrimsonRedDesc => 'Красный, красный, красный! 🔴';

  @override
  String get colorSchemeAmberGoldDesc => 'Золотой и яркий!';

  @override
  String get colorSchemeSlateGrayDesc => 'Нейтральный, элегантный';

  @override
  String get colorSchemeDynamicDesc =>
      'Использовать цвета обоев системы (Android 12+)';

  @override
  String get primaryContainer => 'Основной контейнер';

  @override
  String get secondaryContainer => 'Вторичный контейнер';

  @override
  String get tertiaryContainer => 'Третичный контейнер';

  @override
  String get surfaceColor => 'Поверхность';

  @override
  String get playerButtonSettingsSubtitle =>
      'Настроить порядок кнопок управления плеером';

  @override
  String get playerLyricStyleSubtitle =>
      'Настроить стиль субтитров мини- и полноэкранного плеера';

  @override
  String get workDetailDisplaySubtitle =>
      'Управление информацией на странице деталей';

  @override
  String get workCardDisplaySubtitle =>
      'Управление информацией на карточках работ';

  @override
  String get myTabsDisplaySubtitle =>
      'Управление отображением вкладок на странице «Моё»';

  @override
  String get pageSizeSettings => 'Элементов на странице';

  @override
  String pageSizeCurrent(Object size) {
    return 'Текущее: $size элементов/стр.';
  }

  @override
  String currentSettingLabel(Object value) {
    return 'Текущее: $value';
  }

  @override
  String setToValue(Object value) {
    return 'Установлено: $value';
  }

  @override
  String get llmConfigRequiredMessage =>
      'Для перевода LLM требуется API Key. Сначала настройте его в параметрах.';

  @override
  String get autoSwitchedToLlm => 'Автопереключение: перевод LLM';

  @override
  String get translationDescGoogle => 'Требуется доступ к сервисам Google';

  @override
  String get translationDescLlm =>
      'OpenAI-совместимый API, требуется ручная настройка API Key';

  @override
  String get audioPassthroughDescAndroid =>
      'Разрешить вывод необработанного битового потока (AC3/DTS) на внешний декодер. Может занять эксклюзивный доступ к аудио.';

  @override
  String get permissionExplanation => 'Описание разрешений';

  @override
  String get backgroundRunningPermission => 'Разрешение на фоновую работу';

  @override
  String get notificationPermissionDesc =>
      'Для отображения уведомлений о воспроизведении, позволяющих управлять с экрана блокировки и панели уведомлений.';

  @override
  String get backgroundRunningPermissionDesc =>
      'Исключает приложение из оптимизации батареи для непрерывного воспроизведения в фоне.';

  @override
  String get notificationGrantedStatus =>
      'Разрешено — можно отображать уведомления и элементы управления';

  @override
  String get notificationDeniedStatus => 'Не разрешено — нажмите для запроса';

  @override
  String get backgroundGrantedStatus =>
      'Разрешено — приложение может работать в фоне';

  @override
  String get backgroundDeniedStatus => 'Не разрешено — нажмите для запроса';

  @override
  String get notificationPermissionGranted =>
      'Разрешение на уведомления получено';

  @override
  String get notificationPermissionDenied =>
      'Разрешение на уведомления отклонено';

  @override
  String requestNotificationFailed(Object error) {
    return 'Ошибка запроса разрешения на уведомления: $error';
  }

  @override
  String get backgroundPermissionGranted =>
      'Разрешение на фоновую работу получено';

  @override
  String get backgroundPermissionDenied =>
      'Разрешение на фоновую работу отклонено';

  @override
  String requestBackgroundFailed(Object error) {
    return 'Ошибка запроса разрешения на фоновую работу: $error';
  }

  @override
  String permissionRequired(Object permission) {
    return 'Требуется $permission';
  }

  @override
  String permissionPermanentlyDenied(Object permission) {
    return '$permission отклонено навсегда. Включите вручную в настройках системы.';
  }

  @override
  String get openSettings => 'Открыть настройки';

  @override
  String get permissionsAndroidOnly =>
      'Управление разрешениями доступно только на Android';

  @override
  String get permissionsNotNeeded =>
      'На других платформах ручное управление разрешениями не требуется';

  @override
  String get refreshPermissionStatus => 'Обновить статус разрешений';

  @override
  String deleteFileConfirm(Object fileName) {
    return 'Удалить \"$fileName\"?';
  }

  @override
  String deleteSelectedFilesConfirm(Object count) {
    return 'Удалить $count выбранных файлов?';
  }

  @override
  String get deleted => 'Удалено';

  @override
  String cannotOpenFolder(Object path) {
    return 'Не удалось открыть папку: $path';
  }

  @override
  String openFolderFailed(Object error) {
    return 'Ошибка открытия папки: $error';
  }

  @override
  String get reloadingFromDisk => 'Перезагрузка с диска...';

  @override
  String get refreshComplete => 'Обновление завершено';

  @override
  String refreshFailed(Object error) {
    return 'Ошибка обновления: $error';
  }

  @override
  String deleteSelectedWorksConfirm(Object count) {
    return 'Удалить $count выбранных работ?';
  }

  @override
  String partialDeleteFailed(Object error) {
    return 'Частичная ошибка удаления: $error';
  }

  @override
  String deletedNOfTotal(Object success, Object total) {
    return 'Удалено $success/$total задач';
  }

  @override
  String deleteFailedWithError(Object error) {
    return 'Ошибка удаления: $error';
  }

  @override
  String get noWorkMetadataForOffline =>
      'У этой загрузки нет сохранённых данных о работе для просмотра офлайн';

  @override
  String openWorkDetailFailed(Object error) {
    return 'Ошибка открытия деталей работы: $error';
  }

  @override
  String get noLocalDownloads => 'Нет локальных загрузок';

  @override
  String get exitSelection => 'Выйти из выбора';

  @override
  String get reload => 'Перезагрузить';

  @override
  String get openFolder => 'Открыть папку';

  @override
  String get playlistLink => 'Ссылка на плейлист';

  @override
  String get playlistLinkHint =>
      'Вставьте ссылку на плейлист, например:\nhttps://www.asmr.one/playlist?id=...';

  @override
  String get unrecognizedPlaylistLink =>
      'Нераспознанная ссылка или ID плейлиста';

  @override
  String get addingPlaylist => 'Добавление плейлиста...';

  @override
  String get playlistAddedSuccess => 'Плейлист успешно добавлен';

  @override
  String get addFailed => 'Ошибка добавления';

  @override
  String get playlistNotFound => 'Плейлист не существует или был удалён';

  @override
  String get noPermissionToAccessPlaylist =>
      'Нет прав доступа к этому плейлисту';

  @override
  String get networkConnectionFailed =>
      'Ошибка сетевого подключения, проверьте сеть';

  @override
  String addFailedWithError(Object error) {
    return 'Ошибка добавления: $error';
  }

  @override
  String get creatingPlaylist => 'Создание плейлиста...';

  @override
  String playlistCreatedSuccess(Object name) {
    return 'Плейлист \"$name\" создан';
  }

  @override
  String createFailedWithError(Object error) {
    return 'Ошибка создания: $error';
  }

  @override
  String get noPlaylists => 'Нет плейлистов';

  @override
  String get noPlaylistsDescription =>
      'Вы ещё не создали и не добавили в избранное ни одного плейлиста';

  @override
  String get myPlaylists => 'Мои плейлисты';

  @override
  String totalNItems(Object count) {
    return 'Всего $count записей';
  }

  @override
  String get systemPlaylistCannotDelete => 'Системные плейлисты нельзя удалить';

  @override
  String get deletePlaylist => 'Удалить плейлист';

  @override
  String get unfavoritePlaylist => 'Убрать из избранного';

  @override
  String get deletePlaylistConfirm =>
      'Удаление необратимо. Пользователи, добавившие этот плейлист в избранное, потеряют к нему доступ. Продолжить?';

  @override
  String unfavoritePlaylistConfirm(Object name) {
    return 'Убрать \"$name\" из избранного?';
  }

  @override
  String get unfavorite => 'Убрать из избранного';

  @override
  String get deleting => 'Удаление...';

  @override
  String get deleteSuccess => 'Успешно удалено';

  @override
  String get onlyOwnerCanEdit => 'Редактировать может только автор плейлиста';

  @override
  String get editPlaylist => 'Редактировать плейлист';

  @override
  String get playlistNameRequired => 'Название плейлиста не может быть пустым';

  @override
  String get privacyDescPrivate => 'Только вы можете просматривать';

  @override
  String get privacyDescUnlisted =>
      'Только люди со ссылкой могут просматривать';

  @override
  String get privacyDescPublic => 'Любой может просматривать';

  @override
  String get addWorks => 'Добавить работы';

  @override
  String get addWorksInputHint =>
      'Введите текст с номерами работ, RJ-номера определяются автоматически';

  @override
  String get workId => 'Номер работы';

  @override
  String get workIdHint => 'Например: RJ123456\nrj233333';

  @override
  String detectedNWorkIds(Object count) {
    return 'Обнаружено $count номеров работ';
  }

  @override
  String addNWorks(Object count) {
    return 'Добавить $count';
  }

  @override
  String get noValidWorkIds =>
      'Не найдено действительных номеров работ (начинающихся с RJ)';

  @override
  String addingNWorks(Object count) {
    return 'Добавление $count работ...';
  }

  @override
  String addedNWorksSuccess(Object count) {
    return 'Успешно добавлено $count работ';
  }

  @override
  String get removeWork => 'Удалить работу';

  @override
  String removeWorkConfirm(Object title) {
    return 'Удалить «$title» из плейлиста?';
  }

  @override
  String get removeSuccess => 'Успешно удалено';

  @override
  String removeFailedWithError(Object error) {
    return 'Ошибка удаления: $error';
  }

  @override
  String get saving => 'Сохранение...';

  @override
  String get saveSuccess => 'Сохранено';

  @override
  String saveFailedWithError(Object error) {
    return 'Ошибка сохранения: $error';
  }

  @override
  String get noWorks => 'Нет работ';

  @override
  String get playlistNoWorksDescription =>
      'В этот плейлист ещё не добавлено ни одной работы';

  @override
  String get lastUpdated => 'Последнее обновление';

  @override
  String get createdTime => 'Дата создания';

  @override
  String nWorksCount(Object count) {
    return '$count произведений';
  }

  @override
  String nPlaysCount(Object count) {
    return '$count воспроизведений';
  }

  @override
  String get removeFromPlaylist => 'Удалить из плейлиста';

  @override
  String get checkNetworkOrRetry =>
      'Проверьте сетевое подключение или повторите попытку позже';

  @override
  String get reachedEnd => 'Вы достигли конца~';

  @override
  String excludedNWorks(Object count) {
    return 'Исключено $count работ';
  }

  @override
  String pageExcludedNWorks(Object count) {
    return 'На этой странице исключено $count работ';
  }

  @override
  String get noSubtitlesAvailable => 'Субтитры отсутствуют';

  @override
  String get translateLyrics => 'Перевести текст';

  @override
  String get showOriginalLyrics => 'Показать оригинал';

  @override
  String get showTranslatedLyrics => 'Показать перевод';

  @override
  String get translatingLyrics => 'Перевод...';

  @override
  String get lyricTranslationFailed => 'Не удалось перевести текст';

  @override
  String get unlock => 'Разблокировать';

  @override
  String get backToCover => 'Вернуться к обложке';

  @override
  String get lyricHintTapCover =>
      'Нажмите на обложку или название для перехода к субтитрам';

  @override
  String get floatingSubtitle => 'Плавающие субтитры';

  @override
  String get appendMode => 'Режим добавления';

  @override
  String get appendModeStatusOn => 'Режим добавления: Вкл';

  @override
  String get appendModeStatusOff => 'Режим добавления: Выкл';

  @override
  String get playlistEmpty => 'Плейлист пуст';

  @override
  String get clearQueue => 'Очистить очередь';

  @override
  String get clearQueueConfirm =>
      'Вы уверены, что хотите очистить очередь воспроизведения?';

  @override
  String get saveAsPlaylist => 'Сохранить как плейлист';

  @override
  String get newPlaylistNameHint => 'Введите название плейлиста';

  @override
  String get appendModeEnabled => 'Режим добавления включён';

  @override
  String get appendModeHint =>
      'Следующие нажатия на аудио добавят треки в конец текущего плейлиста, а не заменят его.\nДубликаты не добавляются.';

  @override
  String get gotIt => 'Понятно';

  @override
  String nMinutes(Object count) {
    return '$count мин';
  }

  @override
  String nHours(Object count) {
    return '$count ч';
  }

  @override
  String get titleLabel => 'Название';

  @override
  String get rjNumberLabel => 'RJ номер';

  @override
  String get tapToViewRatingDetail => 'Нажмите для просмотра деталей рейтинга';

  @override
  String priceInYen(Object price) {
    return '$price иен';
  }

  @override
  String soldCount(Object count) {
    return 'Продано: $count';
  }

  @override
  String get circleAndVaSection => 'Кружок | Сэйю';

  @override
  String get subtitleBadge => 'Субтитры';

  @override
  String get otherEditions => 'Другие версии';

  @override
  String tenThousandSuffix(Object count) {
    return '$count тыс.';
  }

  @override
  String get packingWork => 'Упаковка работы...';

  @override
  String get workDirectoryNotExist => 'Каталог работы не существует';

  @override
  String get packingFailed => 'Ошибка упаковки';

  @override
  String exportSuccess(Object path) {
    return 'Экспорт выполнен: $path';
  }

  @override
  String exportFailed(Object error) {
    return 'Ошибка экспорта: $error';
  }

  @override
  String get exportAsZip => 'Экспорт в ZIP';

  @override
  String get offlineBadge => 'Офлайн';

  @override
  String loadFilesFailed(Object error) {
    return 'Ошибка загрузки файлов: $error';
  }

  @override
  String get unknown => 'Неизвестно';

  @override
  String get noPlayableAudioFiles => 'Воспроизводимые аудиофайлы не найдены';

  @override
  String cannotFindAudioFile(Object title) {
    return 'Аудиофайл не найден: $title';
  }

  @override
  String nowPlayingNOfTotal(Object current, Object title, Object total) {
    return 'Воспроизведение: $title ($current/$total)';
  }

  @override
  String get noAudioCannotLoadSubtitle =>
      'Нет воспроизводимого аудио, невозможно загрузить субтитры';

  @override
  String get loadSubtitle => 'Загрузить субтитры';

  @override
  String get loadSubtitleConfirm =>
      'Загрузить этот файл как субтитры для текущего аудио?';

  @override
  String get subtitleFile => 'Файл субтитров';

  @override
  String get currentAudio => 'Текущее аудио';

  @override
  String get subtitleAutoRestoreNote =>
      'При переключении аудио субтитры автоматически вернутся к стандартному подбору';

  @override
  String get confirmLoad => 'Подтвердить загрузку';

  @override
  String get loadingSubtitle => 'Загрузка субтитров...';

  @override
  String subtitleLoadSuccess(Object title) {
    return 'Субтитры загружены: $title';
  }

  @override
  String subtitleLoadFailed(Object error) {
    return 'Ошибка загрузки субтитров: $error';
  }

  @override
  String get cannotPreviewImageMissingInfo =>
      'Невозможно предпросмотр изображения: недостаточно данных';

  @override
  String get cannotFindImageFile => 'Файл изображения не найден';

  @override
  String get cannotPreviewTextMissingInfo =>
      'Невозможно предпросмотр текста: недостаточно данных';

  @override
  String get cannotPreviewPdfMissingInfo =>
      'Невозможно предпросмотр PDF: недостаточно данных';

  @override
  String get cannotPlayVideoMissingId =>
      'Невозможно воспроизвести видео: отсутствует ID файла';

  @override
  String get cannotPlayVideoMissingParams =>
      'Невозможно воспроизвести видео: отсутствуют параметры';

  @override
  String get cannotPlayDirectly => 'Невозможно воспроизвести напрямую';

  @override
  String get noVideoPlayerFound => 'Поддерживаемый видеоплеер не найден.';

  @override
  String get youCan => 'Вы можете:';

  @override
  String get copyLinkToExternalPlayer =>
      '1. Скопировать ссылку во внешний плеер (MX Player, VLC и др.)';

  @override
  String get openInBrowserOption => '2. Открыть в браузере';

  @override
  String playVideoError(Object error) {
    return 'Ошибка воспроизведения видео: $error';
  }

  @override
  String get noFiles => 'Нет файлов';

  @override
  String get resourceFiles => 'Файлы ресурсов';

  @override
  String resourceFilesTranslated(Object count) {
    return 'Файлы ресурсов (переведено $count)';
  }

  @override
  String get translationOriginal => 'Ориг';

  @override
  String get translationTranslated => 'Перев';

  @override
  String copiedName(Object title) {
    return 'Имя скопировано: $title';
  }

  @override
  String translationComplete(Object count) {
    return 'Перевод завершён: $count элементов';
  }

  @override
  String get noContentToTranslate => 'Нет содержимого для перевода';

  @override
  String get preparingTranslation => 'Подготовка перевода...';

  @override
  String translatingProgress(Object current, Object total) {
    return 'Перевод $current/$total';
  }

  @override
  String nItems(Object count) {
    return '$count элементов';
  }

  @override
  String get loadAsSubtitle => 'Загрузить как субтитры';

  @override
  String get preview => 'Предпросмотр';

  @override
  String openVideoFileError(Object error) {
    return 'Ошибка открытия видеофайла: $error';
  }

  @override
  String cannotOpenVideoFile(Object message) {
    return 'Невозможно открыть видеофайл: $message';
  }

  @override
  String get noFileTreeInfo => 'Нет информации о дереве файлов';

  @override
  String get workFolderNotExist => 'Папка работы не существует';

  @override
  String get cannotPlayAudioMissingId =>
      'Невозможно воспроизвести аудио: отсутствует ID файла';

  @override
  String get audioFileNotExist => 'Аудиофайл не существует';

  @override
  String get noPreviewableImages => 'Изображения для предпросмотра не найдены';

  @override
  String get cannotPreviewTextMissingId =>
      'Невозможно предпросмотр текста: отсутствует ID файла';

  @override
  String get cannotFindFilePath => 'Путь к файлу не найден';

  @override
  String fileNotExist(Object title) {
    return 'Файл не существует: $title';
  }

  @override
  String get cannotPreviewPdfMissingId =>
      'Невозможно предпросмотр PDF: отсутствует ID файла';

  @override
  String get videoFileNotExist => 'Видеофайл не существует';

  @override
  String get cannotOpenVideo => 'Невозможно открыть видео';

  @override
  String errorInfo(Object message) {
    return 'Ошибка: $message';
  }

  @override
  String get installVideoPlayerApp =>
      'Установите видеоплеер (VLC, MX Player и др.)';

  @override
  String get filePathLabel => 'Путь к файлу:';

  @override
  String get noDownloadedFiles => 'Нет загруженных файлов';

  @override
  String get offlineFiles => 'Офлайн-файлы';

  @override
  String unsupportedFileType(Object title) {
    return 'Этот тип файлов не поддерживается: $title';
  }

  @override
  String get deleteFilePrompt => 'Вы уверены, что хотите удалить этот файл?';

  @override
  String deletedItem(Object title) {
    return 'Удалено: $title';
  }

  @override
  String get selectAtLeastOneFile => 'Выберите хотя бы один файл';

  @override
  String addedNFilesToDownloadQueue(Object count) {
    return '$count файлов добавлено в очередь загрузки';
  }

  @override
  String downloadedAndSelected(Object downloaded, Object selected) {
    return 'Загружено $downloaded · Выбрано $selected';
  }

  @override
  String downloadN(Object count) {
    return 'Скачать ($count)';
  }

  @override
  String get checkingDownloadedFiles => 'Проверка загруженных файлов...';

  @override
  String get noDownloadableFiles => 'Нет файлов для загрузки';

  @override
  String get selectFilesToDownload => 'Выбрать файлы для загрузки';

  @override
  String downloadedNCount(Object count) {
    return 'Загружено $count';
  }

  @override
  String selectedNCount(Object count) {
    return 'Выбрано $count';
  }

  @override
  String get pleaseEnterServerAddress => 'Введите адрес сервера';

  @override
  String get pleaseEnterUsername => 'Введите имя пользователя';

  @override
  String get pleaseEnterPassword => 'Введите пароль';

  @override
  String get notTestedYet => 'Ещё не тестировалось';

  @override
  String latencyResultDetail(Object latency, Object status) {
    return 'Задержка $latency ($status)';
  }

  @override
  String connectionFailedWithDetail(Object error) {
    return 'Ошибка подключения: $error';
  }

  @override
  String get noAccountTapToRegister => 'Нет аккаунта? Нажмите для регистрации';

  @override
  String get haveAccountTapToLogin => 'Есть аккаунт? Нажмите для входа';

  @override
  String get cannotDeleteActiveAccount =>
      'Невозможно удалить текущий активный аккаунт';

  @override
  String get selectAccount => 'Выбрать аккаунт';

  @override
  String get noSavedAccounts => 'Нет сохранённых аккаунтов';

  @override
  String get addAccountToGetStarted => 'Добавьте аккаунт, чтобы начать';

  @override
  String get unknownHost => 'Неизвестный хост';

  @override
  String lastUsedTime(Object time) {
    return 'Последнее использование: $time';
  }

  @override
  String daysAgo(Object count) {
    return '$count дней назад';
  }

  @override
  String hoursAgo(Object count) {
    return '$count часов назад';
  }

  @override
  String minutesAgo(Object count) {
    return '$count минут назад';
  }

  @override
  String get justNow => 'Только что';

  @override
  String get confirmDelete => 'Подтвердить удаление';

  @override
  String deleteSelectedConfirm(Object count) {
    return 'Удалить $count выбранных элементов?';
  }

  @override
  String deletedNOfTotalItems(Object success, Object total) {
    return 'Удалено $success/$total элементов';
  }

  @override
  String get importingSubtitleFile => 'Импорт файла субтитров...';

  @override
  String get preparingImport => 'Подготовка импорта...';

  @override
  String get preparingExtract => 'Подготовка распаковки...';

  @override
  String get importSubtitleFile => 'Импорт файла субтитров';

  @override
  String get supportedSubtitleFormats =>
      'Поддержка .srt, .vtt, .lrc и других форматов субтитров';

  @override
  String get importFolder => 'Импорт папки';

  @override
  String get importFolderDesc =>
      'Сохраняет структуру папок, импортирует только файлы субтитров';

  @override
  String get importArchive => 'Импорт архива';

  @override
  String get importArchiveDesc =>
      'Поддержка ZIP-архивов без пароля.\nДля массового импорта сожмите все в один архив.';

  @override
  String get subtitleLibraryGuide => 'Руководство по библиотеке субтитров';

  @override
  String get subtitleLibraryFunction => 'Функция библиотеки субтитров';

  @override
  String get subtitleLibraryFunctionDesc =>
      'Хранение импортированных/сохранённых субтитров с поддержкой авто/ручной загрузки при воспроизведении';

  @override
  String get subtitleAutoLoad => 'Автозагрузка субтитров';

  @override
  String get subtitleAutoLoadDesc =>
      'При воспроизведении аудио система автоматически ищет подходящие субтитры:';

  @override
  String get smartCategoryAndMark => 'Умная классификация и маркировка';

  @override
  String get open => 'Открыть';

  @override
  String get moveTo => 'Переместить в';

  @override
  String get rename => 'Переименовать';

  @override
  String get newName => 'Новое имя';

  @override
  String get renameSuccess => 'Переименование выполнено';

  @override
  String get renameFailed => 'Ошибка переименования';

  @override
  String deleteItemConfirm(Object title) {
    return 'Удалить \"$title\"?';
  }

  @override
  String get deleteFolderContentsWarning =>
      'Всё содержимое папки будет удалено.';

  @override
  String get deleteFailed => 'Ошибка удаления';

  @override
  String subtitleLoaded(Object title) {
    return 'Субтитры загружены: $title';
  }

  @override
  String get moveSuccess => 'Перемещение выполнено';

  @override
  String get moveFailed => 'Ошибка перемещения';

  @override
  String previewFailed(Object error) {
    return 'Ошибка предпросмотра: $error';
  }

  @override
  String openFailed(Object error) {
    return 'Ошибка открытия: $error';
  }

  @override
  String get back => 'Назад';

  @override
  String get subtitleLibraryEmpty => 'Библиотека субтитров пуста';

  @override
  String get tapToImportSubtitle => 'Нажмите + для импорта субтитров';

  @override
  String get importSubtitle => 'Импорт субтитров';

  @override
  String get sampleSubtitleContent => '♪ Пример субтитров ♪';

  @override
  String get presetStyles => 'Предустановленные стили';

  @override
  String get backgroundOpacity => 'Непрозрачность фона';

  @override
  String get colorSettings => 'Настройки цвета';

  @override
  String get shapeSettings => 'Настройки формы';

  @override
  String get cornerRadius => 'Радиус скругления';

  @override
  String get horizontalPadding => 'Горизонтальный отступ';

  @override
  String get verticalPadding => 'Вертикальный отступ';

  @override
  String get resetStyle => 'Сбросить стиль';

  @override
  String get resetStyleConfirm => 'Восстановить стиль по умолчанию?';

  @override
  String get restoreDefaultStyle => 'Восстановить стиль по умолчанию';

  @override
  String get reset => 'Сброс';

  @override
  String noBlockedItemsOfType(Object type) {
    return 'Нет заблокированных $type';
  }

  @override
  String unblockedItem(Object item) {
    return 'Разблокировано: $item';
  }

  @override
  String addBlockedItem(Object type) {
    return 'Заблокировать $type';
  }

  @override
  String blockedItemName(Object type) {
    return 'Название $type';
  }

  @override
  String enterBlockedItemHint(Object type) {
    return 'Введите $type для блокировки';
  }

  @override
  String blockedItemAdded(Object item) {
    return 'Заблокировано: $item';
  }

  @override
  String workCountLabel(Object count) {
    return 'Работ: $count';
  }

  @override
  String get miniPlayer => 'Мини-плеер';

  @override
  String get lineHeight => 'Высота строки';

  @override
  String get portraitPlayerBelowCover => 'Портретный плеер (под обложкой)';

  @override
  String get fullscreenSubtitleMode =>
      'Полноэкранные субтитры (портрет/ландшафт)';

  @override
  String get activeSubtitleFontSize => 'Размер активных субтитров';

  @override
  String get inactiveSubtitleFontSize => 'Размер неактивных субтитров';

  @override
  String get restoreDefaultSettings => 'Восстановить настройки по умолчанию';

  @override
  String get guideInPrefix => 'В ';

  @override
  String get guideParsedFolder => '<Распознанные>';

  @override
  String get guideFindWorkDesc =>
      ' папке найти соответствующие произведения\nПоддерживаемый формат папки: RJ123456';

  @override
  String get guideSavedFolder => '<Сохранённые>';

  @override
  String get guideFindSubtitleDesc => ' папке найти отдельные файлы субтитров';

  @override
  String get guideMatchRule =>
      'Правило соответствия: имя файла субтитров совпадает с именем аудиофайла (с расширением или без)';

  @override
  String get guideRecognizedWorkPrefix =>
      'Распознанные произведения получают зелёный ';

  @override
  String get guideTagSuffix => ' тег, а значки аудиофайлов получают ';

  @override
  String get guideSubtitleMatchSuffix =>
      ' отметку, указывающую на совпадение в библиотеке субтитров';

  @override
  String get guideAutoRecognizeRJ =>
      'Автоматическое распознавание формата RJ при импорте, категоризация в <Распознанные>';

  @override
  String get guideAutoAddRJPrefix =>
      'Папки с числовыми именами автоматически получают префикс RJ (напр. 123456 → RJ123456)';

  @override
  String get unknownFile => 'Неизвестный файл';

  @override
  String deleteWithCount(Object count) {
    return 'Удалить ($count)';
  }

  @override
  String get searchSubtitles => 'Поиск субтитров...';

  @override
  String nFilesWithSize(Object count, Object size) {
    return '$count файлов • $size';
  }

  @override
  String get rootDirectory => 'Корень';

  @override
  String get goToParent => 'На уровень выше';

  @override
  String moveToTarget(Object name) {
    return 'Переместить в: $name';
  }

  @override
  String get noSubfoldersHere => 'В этой директории нет подпапок';

  @override
  String addedToPlaylist(Object name) {
    return 'Добавлено в плейлист \"$name\"';
  }

  @override
  String removedFromPlaylist(Object name) {
    return 'Удалено из плейлиста \"$name\"';
  }

  @override
  String get alreadyFavorited => 'В избранном';

  @override
  String loadImageFailedWithError(Object error) {
    return 'Не удалось загрузить изображение\n$error';
  }

  @override
  String get noImageAvailable => 'Нет доступных изображений';

  @override
  String get storagePermissionRequiredForImage =>
      'Для сохранения изображений требуется разрешение на хранилище';

  @override
  String get savedToGallery => 'Сохранено в галерею';

  @override
  String get saveCoverImage => 'Сохранить обложку';

  @override
  String savedToPath(Object path) {
    return 'Сохранено в: $path';
  }

  @override
  String get doubleTapToZoom =>
      'Двойное нажатие для увеличения · Щипок для масштабирования';

  @override
  String getStatusFailed(Object error) {
    return 'Не удалось получить статус: $error';
  }

  @override
  String get deleteRecord => 'Удалить запись';

  @override
  String deletePlayRecordConfirm(Object title) {
    return 'Удалить запись воспроизведения для \"$title\"?';
  }

  @override
  String get notPlayedYet => 'Ещё не воспроизводилось';

  @override
  String playbackFailed(Object error) {
    return 'Ошибка воспроизведения: $error';
  }

  @override
  String get storagePermissionRequired => 'Требуется разрешение на хранилище';

  @override
  String get storagePermissionForGalleryDesc =>
      'Для сохранения изображений требуется доступ к галерее. Предоставьте разрешение в настройках.';

  @override
  String get goToSettings => 'Перейти в настройки';

  @override
  String get imageSavedToGallery => 'Изображение сохранено в галерею';

  @override
  String imageSavedToPath(Object path) {
    return 'Изображение сохранено: $path';
  }

  @override
  String get pullDownForNextPage => 'Потяните вниз для следующей страницы';

  @override
  String get releaseForNextPage =>
      'Отпустите для перехода на следующую страницу';

  @override
  String get jumpTo => 'Перейти';

  @override
  String get goToPageTitle => 'Перейти на страницу';

  @override
  String pageNumberRange(Object max) {
    return 'Страница (1-$max)';
  }

  @override
  String get enterPageNumber => 'Введите номер страницы';

  @override
  String enterValidPageNumber(Object max) {
    return 'Введите корректный номер страницы (1-$max)';
  }

  @override
  String get previousPage => 'Предыдущая';

  @override
  String get nextPage => 'Следующая';

  @override
  String get localPdfNotExist => 'Локальный PDF-файл не существует';

  @override
  String get cannotOpenPdf => 'Невозможно открыть PDF-файл';

  @override
  String loadPdfFailed(Object error) {
    return 'Не удалось загрузить PDF: $error';
  }

  @override
  String pdfPageOfTotal(Object current, Object total) {
    return 'Страница $current из $total';
  }

  @override
  String get loadingPdf => 'Загрузка PDF...';

  @override
  String get pdfPathInvalid => 'Некорректный путь к PDF-файлу';

  @override
  String get desktopPdfPreviewNotSupported =>
      'Предварительный просмотр PDF на рабочем столе пока не поддерживается';

  @override
  String get openWithSystemApp => 'Открыть системным приложением';

  @override
  String renderPdfFailed(Object error) {
    return 'Ошибка рендеринга PDF: $error';
  }

  @override
  String get ratingDetails => 'Подробности оценки';

  @override
  String get selectSaveDirectory => 'Выбрать папку для сохранения';

  @override
  String get noSubtitleContentToSave =>
      'Нет содержимого субтитров для сохранения';

  @override
  String get savedToSubtitleLibrary => 'Сохранено в библиотеку субтитров';

  @override
  String get saveToLocal => 'Сохранить локально';

  @override
  String get selectDirectoryToSaveFile => 'Выбрать папку для сохранения файла';

  @override
  String get saveToSubtitleLibrary => 'Сохранить в библиотеку субтитров';

  @override
  String get saveToSubtitleLibraryDesc =>
      'Сохранить в папку \"Сохранённые\" в библиотеке субтитров';

  @override
  String get saveToFile => 'Сохранить в файл';

  @override
  String get noContentToSave => 'Нет содержимого для сохранения';

  @override
  String fileSavedToPath(Object path) {
    return 'Файл сохранён: $path';
  }

  @override
  String get localFileNotExist =>
      'Локальный файл не существует, попробуйте перезагрузить';

  @override
  String loadTextFailed(Object error) {
    return 'Не удалось загрузить текст: $error';
  }

  @override
  String get previewMode => 'Режим предпросмотра';

  @override
  String get editMode => 'Режим редактирования';

  @override
  String get showOriginal => 'Показать оригинал';

  @override
  String get translateContent => 'Перевести содержимое';

  @override
  String get editTextContentHint => 'Редактировать текст...';

  @override
  String get markButton => 'Отметить';

  @override
  String get bookmarkRemoved => 'Закладка удалена';

  @override
  String setProgressAndRating(Object progress, Object rating) {
    return 'Установлено: $progress, оценка: $rating звёзд';
  }

  @override
  String setProgressTo(Object progress) {
    return 'Установлено: $progress';
  }

  @override
  String ratingSetTo(Object rating) {
    return 'Оценка: $rating звёзд';
  }

  @override
  String get updated => 'Обновлено';

  @override
  String addTagFailed(Object error) {
    return 'Не удалось добавить тег: $error';
  }

  @override
  String addWithCount(Object count) {
    return 'Добавить ($count)';
  }

  @override
  String get undo => 'Отменить';

  @override
  String nStars(Object count) {
    return '$count звёзд';
  }

  @override
  String get voteRemoved => 'Голос отменён';

  @override
  String get votedUp => 'Голос за';

  @override
  String get votedDown => 'Голос против';

  @override
  String voteFailedWithError(Object error) {
    return 'Ошибка голосования: $error';
  }

  @override
  String get voteFor => 'За';

  @override
  String get voteAgainst => 'Против';

  @override
  String get voted => 'Проголосовали';

  @override
  String tagBlockedWithName(Object name) {
    return 'Тег заблокирован: $name';
  }

  @override
  String get subtitleParseFailedUnsupportedFormat =>
      'Ошибка анализа, неподдерживаемый формат';

  @override
  String get lyricPresetDynamic => 'Динамичный';

  @override
  String get lyricPresetClassic => 'Классический';

  @override
  String get lyricPresetModern => 'Современный';

  @override
  String get lyricPresetMinimal => 'Минимальный';

  @override
  String get lyricPresetVibrant => 'Яркий';

  @override
  String get lyricPresetElegant => 'Элегантный';

  @override
  String get lyricPresetDynamicDesc =>
      'Следует за темой системы, автоматические цвета';

  @override
  String get lyricPresetClassicDesc => 'Чёрный фон, белый текст, классика';

  @override
  String get lyricPresetModernDesc => 'Градиентный фон, стильный современный';

  @override
  String get lyricPresetMinimalDesc =>
      'Лёгкая прозрачность, просто и элегантно';

  @override
  String get lyricPresetVibrantDesc => 'Яркие цвета, полны энергии';

  @override
  String get lyricPresetElegantDesc =>
      'Глубокий синий, изысканная элегантность';

  @override
  String get floatingLyricLoading => '♪ Загрузка субтитров ♪';

  @override
  String get subtitleFileNotExist => 'Файл не существует';

  @override
  String get subtitleMissingInfo => 'Недостаточно информации';

  @override
  String get privacyDefaultTitle => 'Воспроизведение аудио';

  @override
  String get offlineModeStartup => 'Ошибка подключения, запуск в офлайн-режиме';

  @override
  String get playlistInfoNotLoaded => 'Информация о плейлисте не загружена';

  @override
  String get encodingUnrecognized =>
      'Кодировка файла не распознана, невозможно корректно отобразить';

  @override
  String editPlaylistFailed(Object error) {
    return 'Не удалось редактировать плейлист: $error';
  }

  @override
  String unsupportedFileTypeWithTitle(Object title) {
    return 'Невозможно открыть этот тип файла: $title';
  }

  @override
  String get settingsSaved => 'Настройки сохранены';

  @override
  String get restoredToDefault => 'Восстановлены настройки по умолчанию';

  @override
  String get restoreDefault => 'По умолчанию';

  @override
  String get saveSettings => 'Сохранить настройки';

  @override
  String get addAtLeastOneSearchCondition =>
      'Добавьте хотя бы одно условие поиска';

  @override
  String get privacyModeSettingsTitle => 'Настройки приватного режима';

  @override
  String get whatIsPrivacyMode => 'Что такое приватный режим?';

  @override
  String get privacyModeDescription =>
      'При включении информация о воспроизведении в уведомлениях и на экране блокировки будет размыта для защиты конфиденциальности.';

  @override
  String get enablePrivacyMode => 'Включить приватный режим';

  @override
  String get privacyModeEnabledSubtitle =>
      'Включено - информация о воспроизведении будет скрыта';

  @override
  String get privacyModeDisabledSubtitle =>
      'Отключено - информация отображается нормально';

  @override
  String get blurOptions => 'Параметры размытия';

  @override
  String get blurNotificationCover => 'Размытие обложки в уведомлениях';

  @override
  String get blurNotificationCoverSubtitle =>
      'Размытие обложки в системных уведомлениях, на экране блокировки и в центре управления';

  @override
  String get blurInAppCover => 'Размытие обложки в приложении';

  @override
  String get blurInAppCoverSubtitle =>
      'Размытие обложки в плеере, списках и других экранах';

  @override
  String get replaceTitle => 'Заменить заголовок';

  @override
  String get replaceTitleSubtitle =>
      'Заменить настоящее название пользовательским';

  @override
  String get replaceTitleContent => 'Содержимое замены заголовка';

  @override
  String get setReplaceTitle => 'Установить замену заголовка';

  @override
  String get enterDisplayTitle => 'Введите отображаемый заголовок';

  @override
  String get replaceTitleSaved => 'Замена заголовка сохранена';

  @override
  String get effectExample => 'Пример эффекта';

  @override
  String get downloadPathSettings => 'Настройки пути загрузки';

  @override
  String loadPathFailedWithError(Object error) {
    return 'Не удалось загрузить путь: $error';
  }

  @override
  String get platformNotSupportCustomPath =>
      'Пользовательский путь загрузки не поддерживается на этой платформе';

  @override
  String activeDownloadsWarning(Object count) {
    return 'Выполняется $count загрузок. Завершите или отмените их перед сменой пути';
  }

  @override
  String setPathFailedWithError(Object error) {
    return 'Не удалось установить путь: $error';
  }

  @override
  String get confirmMigrateFiles => 'Подтвердите перенос файлов';

  @override
  String get migrateFilesToNewDir =>
      'Существующие загруженные файлы будут перенесены в новый каталог:';

  @override
  String get migrationMayTakeTime =>
      'Эта операция может занять некоторое время в зависимости от количества и размера файлов.';

  @override
  String get confirmMigrate => 'Подтвердить перенос';

  @override
  String get restoreDefaultPath => 'Восстановить путь по умолчанию';

  @override
  String get restoreDefaultPathConfirm =>
      'Восстановить путь загрузки по умолчанию и перенести все файлы.\n\nПродолжить?';

  @override
  String get defaultPathRestored => 'Путь по умолчанию восстановлен';

  @override
  String resetPathFailedWithError(Object error) {
    return 'Не удалось восстановить путь по умолчанию: $error';
  }

  @override
  String get migratingFiles => 'Перенос файлов...';

  @override
  String get doNotCloseApp => 'Не закрывайте приложение';

  @override
  String get currentDownloadPath => 'Текущий путь загрузки';

  @override
  String get customPath => 'Пользовательский путь';

  @override
  String get defaultPath => 'Путь по умолчанию';

  @override
  String get changeCustomPath => 'Изменить пользовательский путь';

  @override
  String get setCustomPath => 'Установить пользовательский путь';

  @override
  String get usageInstructions => 'Инструкция по использованию';

  @override
  String get downloadPathUsageDesc =>
      '• После изменения пути все существующие файлы будут автоматически перенесены\n• Не закрывайте приложение во время переноса\n• Рекомендуется выбрать каталог с достаточным объёмом памяти\n• При восстановлении пути по умолчанию файлы также будут перенесены обратно';

  @override
  String get llmTranslationSettings => 'Настройки LLM-перевода';

  @override
  String get apiEndpointUrl => 'URL-адрес API';

  @override
  String get openaiCompatibleEndpoint => 'URL-адрес, совместимый с OpenAI';

  @override
  String get pleaseEnterApiUrl => 'Введите URL-адрес API';

  @override
  String get pleaseEnterValidUrl => 'Введите действительный URL';

  @override
  String get pleaseEnterApiKey => 'Введите API-ключ';

  @override
  String get modelName => 'Название модели';

  @override
  String get pleaseEnterModelName => 'Введите название модели';

  @override
  String get concurrencyCount => 'Параллельность';

  @override
  String get concurrencyDescription =>
      'Количество одновременных запросов на перевод, рекомендуется 3-5';

  @override
  String get promptSection => 'Промпт (Prompt)';

  @override
  String get promptDescription =>
      'Поскольку система использует блочный перевод, убедитесь, что промпт чётко требует выводить только результат перевода без пояснений.';

  @override
  String get enterSystemPrompt => 'Введите системный промпт...';

  @override
  String get pleaseEnterPrompt => 'Введите промпт';

  @override
  String get restoreDefaultPrompt => 'Восстановить промпт по умолчанию';

  @override
  String get confirmRestoreButtonOrder =>
      'Восстановить порядок кнопок по умолчанию?';

  @override
  String get buttonDisplayRules => 'Правила отображения кнопок';

  @override
  String buttonDisplayRulesDesc(Object maxVisible) {
    return '• Первые $maxVisible кнопок отображаются внизу плеера\n• Остальные кнопки доступны в меню «Ещё»';
  }

  @override
  String get shownInPlayer => 'Отображается в плеере';

  @override
  String get shownInMoreMenu => 'Отображается в меню «Ещё»';

  @override
  String get audioFormatPriority => 'Приоритет аудиоформатов';

  @override
  String get confirmRestoreAudioFormat =>
      'Восстановить приоритет аудиоформатов по умолчанию?';

  @override
  String get priorityDescription => 'Описание приоритетов';

  @override
  String get audioFormatPriorityDesc =>
      '• При открытии страницы произведения автоматически раскрывается папка с аудио наиболее приоритетного формата';

  @override
  String get ratingInfo => 'Информация о рейтинге';

  @override
  String get showRatingAndReviewCount =>
      'Показывать рейтинг и количество оценок';

  @override
  String get priceInfo => 'Информация о цене';

  @override
  String get showWorkPrice => 'Показывать цену произведения';

  @override
  String get durationInfo => 'Информация о длительности';

  @override
  String get showWorkDuration => 'Показывать длительность произведения';

  @override
  String get showWorkTotalDuration =>
      'Показывать общую длительность произведения';

  @override
  String get salesInfo => 'Информация о продажах';

  @override
  String get showWorkSalesCount => 'Показывать количество продаж';

  @override
  String get externalLinkInfo => 'Внешние ссылки';

  @override
  String get showExternalLinks =>
      'Показывать внешние ссылки (DLsite, офиц. сайт и др.)';

  @override
  String get releaseDateInfo => 'Дата публикации';

  @override
  String get showWorkReleaseDate => 'Показывать дату публикации произведения';

  @override
  String get translateButtonLabel => 'Кнопка перевода';

  @override
  String get showTranslateButton =>
      'Показывать кнопку перевода заголовка произведения';

  @override
  String get subtitleTagLabel => 'Метка субтитров';

  @override
  String get showSubtitleTagOnCover => 'Показывать метку субтитров на обложке';

  @override
  String get recommendationsLabel => 'Похожие рекомендации';

  @override
  String get showRecommendations =>
      'Показывать похожие рекомендации на странице произведения';

  @override
  String get circleInfo => 'Информация о кружке';

  @override
  String get showWorkCircle => 'Показывать кружок произведения';

  @override
  String get showSubtitleTagOnCard =>
      'Показывать метку субтитров на карточке произведения';

  @override
  String get showOnlineMarks => 'Показывать произведения с онлайн-метками';

  @override
  String get showStats => 'Показывать статистику';

  @override
  String get cannotBeDisabled => 'Нельзя отключить';

  @override
  String get showPlaylists => 'Показывать созданные плейлисты';

  @override
  String get showSubtitleLibrary =>
      'Показывать управление библиотекой субтитров';

  @override
  String get playlistPrivacyPrivateDesc => 'Только вы можете просматривать';

  @override
  String get playlistPrivacyUnlistedDesc =>
      'Могут просматривать только те, у кого есть ссылка';

  @override
  String get playlistPrivacyPublicDesc => 'Может просматривать любой';

  @override
  String get convertWavAfterDownload => 'Конвертировать WAV в FLAC/ALAC';

  @override
  String get convertWavAfterDownloadDesc =>
      'После загрузки WAV автоматически конвертировать в lossless FLAC (или ALAC на iOS) для экономии ~50% места';

  @override
  String get convertWavAfterDownloadEnabled =>
      'Включено — WAV будут конвертированы после загрузки';

  @override
  String get convertWavAfterDownloadDisabled =>
      'Отключено — WAV сохраняются как есть';

  @override
  String get convertWavFfmpegNotFound =>
      'FFmpeg не найден. Установите FFmpeg или проверьте PATH.';

  @override
  String get convertingAudio => 'Конвертация аудио…';

  @override
  String get clearTranslationCache => 'Очистить кэш переводов';

  @override
  String get translationCacheCleared => 'Кэш переводов очищен';

  @override
  String get platformHintAndroid =>
      'Android: Будет использован системный выбор файлов, может потребоваться разрешение на хранилище';

  @override
  String get platformHintIOS =>
      'iOS: Из-за системных ограничений используется путь по умолчанию. Файлы можно просмотреть через системный файловый менеджер';

  @override
  String get platformHintWindows =>
      'Windows: Можно выбрать любую доступную директорию';

  @override
  String get platformHintMacOS =>
      'macOS: Можно выбрать любую доступную директорию';

  @override
  String get platformHintLinux =>
      'Linux: Можно выбрать любую доступную директорию';

  @override
  String get platformHintDefault =>
      'Выберите директорию для сохранения загруженных файлов';

  @override
  String get subtitleFolderParsed => 'Разобранные';

  @override
  String get subtitleFolderSaved => 'Сохранённые';

  @override
  String get subtitleFolderUnknown => 'Неизвестные';

  @override
  String get sortDownloadDate => 'Дата загрузки';

  @override
  String get sortWorkId => 'ID';

  @override
  String get searchDownloads => 'Поиск загруженных...';

  @override
  String get logTitle => 'Логи приложения';

  @override
  String get logSubtitle => 'Просмотр и экспорт логов';

  @override
  String get logSearchHint => 'Поиск в логах...';

  @override
  String get logFilterAll => 'Все';

  @override
  String get logCopy => 'Копировать логи';

  @override
  String get logExport => 'Экспорт лог-файла';

  @override
  String get logClear => 'Очистить логи';

  @override
  String get logCopied => 'Логи скопированы в буфер обмена';

  @override
  String logExported(Object path) {
    return 'Логи экспортированы в $path';
  }

  @override
  String logCount(Object count) {
    return '$count записей';
  }

  @override
  String get logAutoScroll => 'Автопрокрутка';

  @override
  String get logEmpty => 'Логов пока нет';

  @override
  String get crossfadeTitle => 'Кроссфейд';

  @override
  String crossfadeEnabledWithDuration(Object ms) {
    return 'Кроссфейд: ${ms}ms';
  }

  @override
  String get gaplessPlaybackEnabled =>
      'Бесшовное воспроизведение (без кроссфейда)';

  @override
  String get crossfadeDurationLabel => 'Длительность кроссфейда';

  @override
  String get crossfadeMinLabel => '0.5с';

  @override
  String get crossfadeMaxLabel => '10с';

  @override
  String get crossfadeDescription =>
      'Плавный переход между треками. При отключении бесшовное воспроизведение минимизирует паузы.';

  @override
  String get equalizerTitle => 'Эквалайзер';

  @override
  String get equalizerEnabled => 'Эквалайзер включён';

  @override
  String get equalizerDisabled => 'Эквалайзер выключен';

  @override
  String get equalizerActive => 'Активен';

  @override
  String get equalizerPresets => 'Пресеты';

  @override
  String get equalizerCustomBands => 'Пользовательские полосы';

  @override
  String get equalizerCustom => 'Пользовательский';

  @override
  String get equalizerReset => 'Сбросить';

  @override
  String get equalizerNotSupported =>
      'Эквалайзер недоступен на этом устройстве';

  @override
  String get equalizerNotSupportedAndroid =>
      'Аудиосессия ещё не инициализирована. Сначала воспроизведите трек.';

  @override
  String get equalizerNotSupportedOther =>
      'Аппаратный эквалайзер не поддерживается на этой платформе. Настройки будут сохранены для использования при поддержке.';

  @override
  String get equalizerInfo =>
      'На Android эквалайзер применяется через аппаратные аудиоэффекты. На других платформах настройки EQ сохраняются для будущего использования.';

  @override
  String get searchSettings => 'Поиск настроек...';

  @override
  String get searchSettingsTitle => 'Поиск настроек';

  @override
  String get searchSettingsComingSoon =>
      'Полный поиск по настройкам будет доступен в будущем обновлении.';

  @override
  String get preferredSampleRate => 'Предпочтительная частота дискретизации';

  @override
  String get preferredSampleRateSubtitle =>
      'Цель вывода Hi-res аудио (Android)';

  @override
  String get preferredSampleRateAuto => 'Авто (следовать файлу)';

  @override
  String get preferredSampleRateDesc =>
      'Устанавливает предпочтительную частоту дискретизации для вывода аудио. Более высокие значения могут снизить совместимость, но улучшить качество на поддерживаемых ЦАП.';

  @override
  String get settingsPlayback => 'Воспроизведение';

  @override
  String get settingsPlaybackSubtitle => 'Эквалайзер, кроссфейд, аудиоформат';

  @override
  String get settingsAppearance => 'Внешний вид';

  @override
  String get settingsAppearanceSubtitle => 'Тема, язык, настройки отображения';

  @override
  String get settingsDownloadsStorage => 'Загрузки и хранилище';

  @override
  String get settingsDownloadsStorageSubtitle =>
      'Путь загрузки, управление кешем';

  @override
  String get settingsPrivacyContent => 'Приватность и контент';

  @override
  String get settingsPrivacyContentSubtitle =>
      'Режим конфиденциальности, блокировки';

  @override
  String get settingsTranslation => 'Перевод';

  @override
  String get settingsTranslationSubtitle => 'Источник перевода, настройки LLM';

  @override
  String get settingsAccount => 'Аккаунт';

  @override
  String get settingsAccountSubtitle => 'Аккаунты сервера, плавающие субтитры';

  @override
  String get settingsAdvanced => 'Дополнительно';

  @override
  String get settingsAdvancedSubtitle =>
      'Порядок сортировки, логи, все настройки';

  @override
  String get settingsAboutSubtitle => 'Версия, обновления, лицензии';

  @override
  String get advancedInfoBanner =>
      'Эти настройки редко меняются после первоначальной настройки.';

  @override
  String get advancedSectionDisplaySorting => 'Отображение и сортировка';

  @override
  String get advancedDefaultSortOrderSubtitle =>
      'Дата выхода, название, рейтинг и др.';

  @override
  String get advancedMyTabsDisplaySubtitle =>
      'Показать/скрыть вкладки на странице «Моё»';

  @override
  String get advancedSectionContentFiltering => 'Фильтрация контента';

  @override
  String get advancedSubtitlePrioritySubtitle => 'Высший и низший приоритет';

  @override
  String get advancedSectionDebugLegacy => 'Отладка и устаревшее';

  @override
  String get advancedAllSettingsLegacy => 'Все настройки (устаревшие)';

  @override
  String get advancedAllSettingsLegacySubtitle =>
      'Оригинальный полный экран настроек';

  @override
  String get hiResExclusiveMode => 'Hi-Res эксклюзивный режим';

  @override
  String get hiResExclusiveModeSubtitle =>
      'Использовать нативный ExoPlayer для FLAC/WAV hi-res треков';

  @override
  String get hiResExclusiveModeDesc =>
      'При включении hi-res треки (FLAC/WAV >48кГц) воспроизводятся через нативный ExoPlayer. Возможна кратковременная пауза при переключении плееров.';

  @override
  String get hiResExclusiveModeEnabled => 'Hi-Res эксклюзивный режим включён';

  @override
  String get hiResExclusiveModeDisabled => 'Hi-Res эксклюзивный режим выключен';

  @override
  String get enable => 'Включить';

  @override
  String get listeningStatsTitle => 'Статистика прослушивания';

  @override
  String get listeningStatsSubtitle => 'Ваши привычки и история прослушивания';

  @override
  String get statsWorksPlayed => 'Прослушано работ';

  @override
  String get statsCompleted => 'Завершено';

  @override
  String get statsListeningTime => 'Время прослушивания';

  @override
  String get statsStreakDays => 'Дней подряд';

  @override
  String get statsDays => 'дней';

  @override
  String get statsDailyActivity => 'Активность за 14 дней';

  @override
  String get statsTopVAs => 'Лучшие сэйю';

  @override
  String get statsTopCircles => 'Лучшие кружки';

  @override
  String get statsRecentPlays => 'Недавние';

  @override
  String get statsNoData => 'Статистики пока нет';

  @override
  String get statsNoDataDesc =>
      'Начните слушать работы, и статистика появится здесь.';

  @override
  String get statsTabDaily => 'День';

  @override
  String get statsTabWeekly => 'Неделя';

  @override
  String get statsTabMonthly => 'Месяц';

  @override
  String get statsWeeklyReport => 'Недельный отчёт (4 недели)';

  @override
  String get statsMonthlyReport => 'Месячный отчёт (6 месяцев)';

  @override
  String get statsHeatmap => 'Тепловая карта';

  @override
  String get statsHeatmapDesc => 'Активность за последние 12 недель';

  @override
  String get statsMilestones => 'Достижения';

  @override
  String get statsMilestoneDesc =>
      'Достижения, полученные во время вашего пути прослушивания';

  @override
  String get statsMilestoneFirstSteps => 'Первые шаги';

  @override
  String get statsMilestoneFirstStepsDesc => 'Воспроизведите первую работу';

  @override
  String get statsMilestoneGettingStarted => 'Начало положено';

  @override
  String get statsMilestoneGettingStartedDesc =>
      'Воспроизведите 10 разных работ';

  @override
  String get statsMilestoneListener => 'Преданный слушатель';

  @override
  String get statsMilestoneListenerDesc => 'Воспроизведите 50 разных работ';

  @override
  String get statsMilestoneCentury => 'Сотня';

  @override
  String get statsMilestoneCenturyDesc => 'Воспроизведите 100 разных работ';

  @override
  String get statsMilestoneComplete => 'Завершено!';

  @override
  String get statsMilestoneCompleteDesc => 'Закончите первую работу';

  @override
  String get statsMilestoneDoubleDigits => 'Две цифры';

  @override
  String get statsMilestoneDoubleDigitsDesc => 'Прослушайте 10 часов';

  @override
  String get statsMilestoneLongHaul => 'Марафонец';

  @override
  String get statsMilestoneLongHaulDesc => 'Прослушайте 50 часов';

  @override
  String get statsMilestoneHundredHours => 'Клуб 100 часов';

  @override
  String get statsMilestoneHundredHoursDesc => 'Прослушайте 100 часов';

  @override
  String get statsMilestoneConsistent => 'Постоянство';

  @override
  String get statsMilestoneConsistentDesc => 'Достигните 7-дневной серии';

  @override
  String get statsMilestoneUnstoppable => 'Неудержимый';

  @override
  String get statsMilestoneUnstoppableDesc => 'Достигните 30-дневной серии';

  @override
  String get bitPerfectPlayback => 'Бит-перфект воспроизведение';

  @override
  String get bitPerfectPlaybackSubtitleOff => 'Обнаружение USB ЦАП отключено';

  @override
  String get bitPerfectPlaybackSubtitleOn =>
      'Прямой вывод на USB ЦАП через libusb';

  @override
  String get bitPerfectPlaybackSelectDevice => 'Выбрать USB ЦАП';

  @override
  String get bitPerfectPlaybackSelectHint => 'Выберите USB аудиоустройство...';

  @override
  String get bitPerfectPlaybackNoDevice => 'USB ЦАП не обнаружен';

  @override
  String get bitPerfectPlaybackRefreshTooltip => 'Обновить список устройств';

  @override
  String get bitPerfectPlaybackConfirmDesc =>
      'При включении подключённый USB ЦАП будет обнаружен, и аудио может передаваться напрямую, минуя микшер Android для безупречного бит-перфект воспроизведения.';

  @override
  String get bitPerfectPlaybackEnabled =>
      'Бит-перфект воспроизведение включено';

  @override
  String get bitPerfectPlaybackDisabled =>
      'Бит-перфект воспроизведение отключено';

  @override
  String get bitPerfectPlaybackDeviceUpdated => 'USB ЦАП устройство обновлено';

  @override
  String get bitPerfectPlaybackListRefreshed => 'Список USB устройств обновлён';

  @override
  String get bitPerfectPlaybackInfoTooltip => 'О бит-перфект воспроизведении';

  @override
  String get bitPerfectPlaybackInfo =>
      'Бит-перфект воспроизведение отправляет исходные аудиоданные без изменений на внешний ЦАП для максимально возможной точности.\n\nОбычный аудиомикшер Android передискретизирует всё аудио до 48кГц, ухудшая hi-res контент. Этот режим направляет аудио напрямую на подключённый USB ЦАП через драйвер libusb, минуя микшер Android.';

  @override
  String get bitPerfectPlaybackPermissionDenied =>
      'Разрешение USB отклонено. Пожалуйста, предоставьте доступ USB в настройках.';

  @override
  String get playNext => 'Воспроизвести следующую';

  @override
  String get noAudioTracks => 'Аудиодорожки не найдены';

  @override
  String playingNextTracks(Object count) {
    return 'Далее: $count дорожек';
  }

  @override
  String get localFileBrowser => 'Локальный файловый браузер';

  @override
  String get browseFiles => 'Обзор файлов';

  @override
  String get progressSync => 'Синхронизация прогресса между устройствами';

  @override
  String get progressSyncSubtitle =>
      'Синхронизация прогресса воспроизведения с сервером для бесшовного продолжения на других устройствах';

  @override
  String get progressSyncEnabled =>
      'Включено — прогресс синхронизируется с сервером';

  @override
  String get progressSyncDisabled => 'Отключено';

  @override
  String get autoTranslateLyrics => 'Автоматический перевод текста';

  @override
  String get autoTranslateLyricsEnabled =>
      'Включено — текст переводится автоматически';

  @override
  String get autoTranslateLyricsDisabled => 'Выключено';

  @override
  String autoTranslateBannerTranslating(Object language) {
    return 'Автоматический перевод на $language…';
  }

  @override
  String autoTranslateBannerDone(Object language) {
    return 'Переведено на $language';
  }

  @override
  String get backupTitle => 'Резервное копирование и восстановление';

  @override
  String get backupSubtitle => 'Экспорт или восстановление данных приложения';

  @override
  String get backupInfoDescription =>
      'Создайте резервную копию данных приложения, включая аккаунты, настройки, историю, плейлисты и библиотеку субтитров. Восстановите данные из файла резервной копии в любое время.';

  @override
  String get backupExportTitle => 'Экспорт';

  @override
  String get backupExportSubtitle => 'Создать полную резервную копию';

  @override
  String get backupCreateBackup => 'Создать резервную копию';

  @override
  String get backupCreateBackupDesc => 'Сохранить все данные в .zip файл';

  @override
  String get backupExportSuccess => 'Резервная копия создана';

  @override
  String backupSavedTo(Object path, Object size) {
    return 'Резервная копия сохранена:\n$path\n\nРазмер файла: $size';
  }

  @override
  String backupExportFailed(Object error) {
    return 'Резервное копирование не удалось:\n$error';
  }

  @override
  String get backupSelectExportDir =>
      'Выберите место сохранения резервной копии';

  @override
  String get backupRestoreTitle => 'Восстановление';

  @override
  String get backupRestoreSubtitle => 'Восстановить из резервной копии';

  @override
  String get backupRestoreFromBackup => 'Восстановить из резервной копии';

  @override
  String get backupRestoreFromBackupDesc =>
      'Выберите .zip файл резервной копии для восстановления';

  @override
  String get backupSelectImportFile => 'Выберите файл резервной копии';

  @override
  String get backupRestoreConfirmTitle => 'Восстановить данные?';

  @override
  String get backupRestoreConfirmMessage =>
      'Это заменит все текущие данные приложения данными из резервной копии. После восстановления приложение нужно перезапустить.\n\nПродолжить?';

  @override
  String get backupRestoreSuccessTitle => 'Восстановление завершено';

  @override
  String get backupRestoreSuccess => 'Все данные успешно восстановлены.';

  @override
  String get backupRestoreWarnings => 'Предупреждения:';

  @override
  String backupRestoreFailed(Object error) {
    return 'Восстановление не удалось:\n$error';
  }

  @override
  String get backupRestartApp => 'Перезапустить приложение';

  @override
  String get backupRestartRequired => 'Требуется перезапуск';

  @override
  String get backupRestartRequiredDesc =>
      'Перезапустите приложение, чтобы восстановленные данные вступили в силу.';

  @override
  String get backupError => 'Ошибка резервного копирования';

  @override
  String get backupDataIncluded => 'Включённые данные';

  @override
  String get backupDatabases => 'Базы данных';

  @override
  String get backupHiveBoxes => 'Состояние приложения';

  @override
  String get backupPreferences => 'Предпочтения';

  @override
  String get backupAllSettings =>
      'Все настройки, умные плейлисты и предпочтения';

  @override
  String get smartPlaylist => 'Умный плейлист';

  @override
  String get smartPlaylists => 'Умные плейлисты';

  @override
  String get smartPlaylistSubtitle => 'Автоматически создан по правилам';

  @override
  String get searchRules => 'Правила поиска';

  @override
  String activeRules(Object count) {
    return 'Активные правила ($count)';
  }

  @override
  String get regularPlaylist => 'Обычный плейлист';

  @override
  String get audioBookmarksTitle => 'Закладки';

  @override
  String get audioBookmarksEmpty => 'Закладок пока нет';

  @override
  String get audioBookmarksEmptyTrack =>
      'Нет закладок для этого трека.\nНажмите на значок закладки, чтобы добавить.';

  @override
  String get audioBookmarksHint =>
      'Отмечайте любимые моменты во время прослушивания';

  @override
  String audioBookmarkAdded(Object position) {
    return 'Закладка добавлена в $position';
  }

  @override
  String get audioBookmarksView => 'Просмотр';

  @override
  String get audioBookmarksEditNote => 'Редактировать заметку';

  @override
  String get audioBookmarksNoteHint => 'Добавить заметку для этой закладки...';

  @override
  String get audioBookmarksDeleteConfirm => 'Удалить эту закладку?';

  @override
  String get appLockTitle => 'Блокировка приложения';

  @override
  String get appLockEnabledSubtitle =>
      'Включено — требуется биометрия или PIN для открытия';

  @override
  String get appLockDisabledSubtitle =>
      'Отключено — приложение открывается без аутентификации';

  @override
  String get appLockDisableConfirmTitle => 'Отключить блокировку приложения?';

  @override
  String get appLockDisableConfirmMessage =>
      'Это отключит всю защиту приложения, включая биометрию и PIN-код.';

  @override
  String get appLockDisable => 'Отключить';

  @override
  String get appLockDisabledToast => 'Блокировка приложения отключена';

  @override
  String get appLockEnterPin => 'Введите PIN-код';

  @override
  String get appLockAuthenticating => 'Аутентификация…';

  @override
  String get appLockWrongPin => 'Неверный PIN-код. Попробуйте снова.';

  @override
  String get appLockUseBiometric => 'Использовать отпечаток / Face ID';

  @override
  String get appLockBiometricReason => 'Разблокировать KikoFlu';

  @override
  String get appLockBiometric => 'Биометрия';

  @override
  String get appLockBiometricEnabledSubtitle =>
      'Включено — отпечаток или лицо доступны';

  @override
  String get appLockBiometricDisabledSubtitle => 'Отключено — только PIN-код';

  @override
  String get appLockBiometricNotAvailable =>
      'Биометрия недоступна или не настроена на этом устройстве';

  @override
  String get appLockBiometricEnableReason =>
      'Включить биометрическую разблокировку';

  @override
  String get appLockBiometricSubtitle =>
      'Используйте отпечаток пальца или лицо для быстрой разблокировки';

  @override
  String get appLockSetupTitle => 'Настройка блокировки приложения';

  @override
  String get appLockSetupPinSubtitle => 'Введите PIN-код для защиты приложения';

  @override
  String get appLockSetupConfirmSubtitle => 'Подтвердите PIN-код';

  @override
  String get appLockChangePin => 'Изменить PIN';

  @override
  String get appLockChangePinSubtitle => 'Установить новый PIN-код';

  @override
  String get appLockPinMismatch => 'PIN-коды не совпадают. Попробуйте снова.';

  @override
  String get appLockPinChanged => 'PIN-код успешно изменён';

  @override
  String get appLockDigits => 'цифр';

  @override
  String get appLockAutoLock => 'Автоблокировка';

  @override
  String get appLockAutoLockNever => 'Никогда';

  @override
  String get appLockAutoLockImmediately => 'Сразу';

  @override
  String get appLockAutoLock1Min => '1 минута';

  @override
  String get appLockAutoLock5Min => '5 минут';

  @override
  String get appLockAutoLock15Min => '15 минут';

  @override
  String get appLockAutoLock30Min => '30 минут';

  @override
  String get appLockAutoLockMinutes => 'минут';

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
}
