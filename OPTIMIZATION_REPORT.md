# 🔍 KikoFlu Edge — Laporan Optimasi Kode

**Tanggal:** 22 Agustus 2026  
**Versi Aplikasi:** 3.2.2  
**Total Baris Kode:** ~129,682 baris Dart

---

## 📊 Ringkasan Eksekutif

| Metrik | Nilai |
|---|---|
| Total file Dart | ~200+ file |
| Widget raksasa (>1000 baris) | 5 file |
| Total setState() | 250+ panggilan |
| StreamController | 81 instance |
| MediaQuery.of(context) | 54 panggilan |
| jsonDecode/jsonEncode | 45 panggilan |

---

## 🚨 Prioritas Optimasi

### 🔴 KRITIS — Harus Segera Diperbaiki

#### 1. Memory Leak: StreamController Tidak di-Dispose

**File Terdampak:**

| File | Jumlah StreamController | Status |
|---|---|---|
| `hi_res_audio_service.dart` | 13 | ⚠️ Perlu review |
| `audio_player_service.dart` | 5 | ⚠️ Perlu review |
| `usb_dac_service.dart` | 3 | ⚠️ Perlu review |
| `exclusive_audio_service.dart` | 3 | ⚠️ Perlu review |
| `equalizer_service.dart` | 1 | ⚠️ Perlu review |
| `bookmark_service.dart` | 1 | ⚠️ Perlu review |
| `floating_lyric_service.dart` | 2 | ⚠️ Perlu review |

**Dampak:**
- Memory leak akumulatif seiring waktu
- Listener lama tetap dipanggil meski UI sudah di-dispose
- Potensi OOM crash di Android

**Contoh Masalah:**
```dart
// hi_res_audio_service.dart — 13 StreamController
final StreamController<bool> _playbackStateController = StreamController<bool>.broadcast();
final StreamController<HiResFormatInfo?> _formatInfoController = StreamController<HiResFormatInfo?>.broadcast();
final StreamController<bool> _bufferingController = StreamController<bool>.broadcast();
// ... 10 lagi
```

---

#### 2. I/O Operations di Main Thread — UI Freeze

**File Terdampak:**

| File | Operasi I/O | Dampak |
|---|---|---|
| `subtitle_library_service.dart` | Recursive directory listing | UI freeze saat scanning |
| `download_task_persistence.dart` | `reloadMetadataFromDisk()` | Scan semua folder download |
| `cache_service.dart` | Cache size calculation | Scan semua file cache |
| `download_path_service.dart` | Directory migration | Recursive file operations |
| `cache_service.dart` | `checkAndCleanCache()` | File stat semua file |

**Dampak:**
- **ANR (Application Not Responding)** di Android jika main thread blocked > 5 detik
- **Splash screen stuck** saat init sequence
- **Scroll jank** saat user scroll list

**Contoh Masalah:**
```dart
// download_task_persistence.dart
Future<void> reloadMetadataFromDisk() async {
  final downloadDir = await getDownloadDirectory();
  await for (final entity in downloadDir.list()) {  // ← Main thread!
    if (entity is Directory) {
      final workIdStr = entity.path.split(Platform.pathSeparator).last;
      // ... scan semua folder
    }
  }
}
```

---

#### 3. OOM Risk: Image Cache Terlalu Besar

**File:** `lib/src/app/app_bootstrap.dart`

```dart
PaintingBinding.instance.imageCache.maximumSize = 300;      // 300 images
PaintingBinding.instance.imageCache.maximumSizeBytes = 50 << 20; // 50 MB
```

**Dampak:**
- 300 images bisa consume 100+ MB memory
- Device low-end akan OOM
- `didHaveMemoryPressure()` hanya clear cache, tidak proactive eviction

**Rekomendasi:**
- Turunkan ke 150-200 images
- Implementasi LRU eviction yang lebih agresif
- Cache berdasarkan screen yang aktif

---

### 🟡 PENTING — Harus Diperbaiki

#### 4. Widget Raksasa (>1000 baris) — God Widgets

**File Terdampak:**

| File | Baris | Masalah |
|---|---|---|
| `local_downloads_screen.dart` | **2,227** | Screen + List + Card + Logic jadi 1 |
| `audio_player_screen.dart` | **2,064** | Player + Lyric + Cover + Badge |
| `file_explorer_widget.dart` | **1,753** | Explorer + Selection + File tree |
| `audio_info_sheet.dart` | **1,727** | Bottom sheet + puluhan state |
| `offline_file_explorer_widget.dart` | **1,374** | Mirip file_explorer offline |

**Dampak:**
- **Rebuild berlebihan** — setState() di parent rebuild semua child
- **Memory footprint tinggi** — Widget tree sangat besar
- **Sulit maintain** — Perubahan kecil bisa break banyak fitur
- **Frame drop** — Di device low-end

**Rekomendasi Split:**
```
local_downloads_screen.dart
├── local_downloads_screen.dart (main screen)
├── widgets/local_download_list.dart (list logic)
├── widgets/local_download_card.dart (card widget)
└── widgets/local_download_selection.dart (selection logic)
```

---

#### 5. setState() Berlebihan — Jank & Unnecessary Rebuilds

**Top Offenders:**

| File | Jumlah setState() | Contoh Masalah |
|---|---|---|
| `audio_player_screen.dart` | 17+ | setState untuk setiap UI update |
| `local_downloads_screen.dart` | 16+ | setState untuk selection, search, sort |
| `file_explorer_widget.dart` | 13+ | setState untuk expand/collapse |
| `subtitle_library_screen.dart` | 12+ | setState untuk navigation, search |
| `download_path_settings_screen.dart` | 8+ | setState untuk path selection |

**Dampak:**
- **Jank/Frame drop** — setState rebuild seluruh subtree
- **Battery drain** — CPU bekerja lebih keras
- **Scroll jank** — Terutama di list/grid views

**Contoh Masalah:**
```dart
// audio_player_screen.dart — setState dipanggil untuk setiap perubahan kecil
void _onPositionChanged(Duration position) {
  setState(() { _currentPosition = position; }); // ← Trigger rebuild
}

void _onPlayStateChanged(bool isPlaying) {
  setState(() { _isPlaying = isPlaying; }); // ← Trigger rebuild lagi
}

void _onTrackChanged(AudioTrack? track) {
  setState(() { _currentTrack = track; }); // ← Trigger rebuild lagi
}
```

**Rekomendasi:**
- Gunakan `ref.watch()` atau `ref.listen()` untuk state yang sering berubah
- Gunakan `ConsumerWidget` untuk state yang jarang berubah
- Gunakan `select()` untuk rebuild hanya bagian yang berubah

---

#### 6. God Service — audio_player_service.dart

**File:** `lib/src/services/audio_player_service.dart` (1,119 baris)

**Tanggung Jawab:**
1. Playback control (play, pause, seek)
2. Queue management
3. USB DAC routing
4. Exclusive mode (WASAPI/AAudio)
5. SMTC integration (Windows)
6. Privacy mode
7. Audio format detection
8. Crossfade management
9. Gain/ReplayGain
10. Temp file management

**Dampak:**
- **Sulit di-debug** — Perubahan di 1 fitur bisa break fitur lain
- **Sulit di-test** — Terlalu banyak dependency
- **Race condition** — Banyak async operations overlap

**Rekomendasi Split:**
```
audio_player_service.dart
├── audio_player_service.dart (core playback)
├── audio_queue_service.dart (queue management)
├── audio_dac_service.dart (USB DAC routing)
├── audio_smtc_service.dart (Windows SMTC)
├── audio_privacy_service.dart (privacy mode)
└── audio_format_service.dart (format detection)
```

---

### 🟢 NICE-TO-HAVE — Optimasi Tambahan

#### 7. MediaQuery.of(context) Redundant

**Jumlah:** 54 panggilan di seluruh codebase

**Contoh:**
```dart
// main_screen.dart — 3x MediaQuery.of(context) dalam 1 build()
final topPadding = MediaQuery.of(context).padding.top;
final screenW = MediaQuery.of(context).size.width;
final mq = MediaQuery.of(context);
```

**Dampak:**
- Widget rebuild lebih sering (MediaQuery adalah InheritedWidget)
- Performance overhead

**Rekomendasi:**
- Cache MediaQuery di awal build()
- Gunakan `MediaQuery.sizeOf(context)` atau `MediaQuery.paddingOf(context)` untuk partial rebuild
- Buat extension method untuk mengurangi boilerplate

---

#### 8. Repeated JSON Parsing

**Jumlah:** 45 panggilan jsonDecode/jsonEncode

**File Terdampak:**
- `work_metadata.json` — Diparse ulang setiap kali diakses
- `HistoryRecord` — Menyimpan JSON string, parse ulang saat load
- `SmartPlaylist` — Serialize/deserialize ke SharedPreferences
- `download_task_persistence.dart` — Tasks di-encode/decode频繁

**Dampak:**
- CPU waste — JSON parsing CPU-intensive
- GC pressure — Banyak object allocation

**Rekomendasi:**
- Cache parsed objects di memory
- Gunakan typed model langsung dari database
- Batch JSON operations

---

#### 9. No Debounce di Search

**File:** `works_screen.dart`, `search_screen.dart`

```dart
_onScroll() {
  if (_scrollController.position.pixels >= maxScroll - 200) {
    ref.read(worksProvider.notifier).loadWorks(); // ← No debounce
  }
}
```

**Dampak:**
- API calls berlebihan
- Network waste
- Potensi API rate limit

**Rekomendasi:**
- Gunakan `debounce` atau `throttle` untuk scroll events
- Implementasi request cancellation
- Cache response

---

#### 10. No const Constructors

Banyak widget yang seharusnya `const` tapi tidak:

**Contoh:**
```dart
// Seharusnya const
class _OfflineToast extends ConsumerStatefulWidget { ... }
class _MiniPlayerArea extends ConsumerWidget { ... }

// Seharusnya const constructor
Icon(Icons.search)  // ← Seharusnya const Icon(Icons.search)
SizedBox(height: 8) // ← Seharusnya const SizedBox(height: 8)
```

**Dampak:**
- Widget non-const selalu di-rebuild
- Memory allocation berlebihan

---

## 📋 Daftar Tugas Optimasi

### Phase 1: Critical Fixes (Minggu 1)

- [x] Fix StreamController leak di `hi_res_audio_service.dart`
- [x] Fix StreamController leak di `audio_player_service.dart`
- [x] Fix StreamController leak di `usb_dac_service.dart`
- [x] Fix StreamController leak di `exclusive_audio_service.dart`
- [x] Fix StreamController leak di `floating_lyric_service.dart`
- [x] Fix StreamController leak di `bookmark_service.dart`
- [x] Fix StreamController leak di `equalizer_service.dart`
- [x] Fix StreamController leak di `playback_history_service.dart`
- [x] Tambahkan semua dispose() calls ke `main.dart`
- [x] Turunkan image cache size ke 150 images / 30 MB
- [x] Pindahkan I/O ke Isolate di `download_task_persistence.dart`
- [x] Pindahkan I/O ke Isolate di `cache_service.dart` (getCacheBreakdown)
- [x] Pindahkan I/O ke Isolate di `subtitle_library_service.dart` (_rebuildDatabase)
- [ ] Implementasi proactive memory eviction

### Phase 2: Widget Refactoring (Minggu 2-3)

- [ ] Split `local_downloads_screen.dart` (2,227 baris)
- [ ] Split `audio_player_screen.dart` (2,064 baris)
- [ ] Split `file_explorer_widget.dart` (1,753 baris)
- [ ] Split `audio_info_sheet.dart` (1,727 baris)
- [ ] Split `offline_file_explorer_widget.dart` (1,374 baris)
- [ ] Refactor `audio_player_service.dart` (1,119 baris)

### Phase 3: State Management (Minggu 3-4)

- [ ] Konversi `audio_player_screen.dart` setState → Riverpod
- [ ] Konversi `local_downloads_screen.dart` setState → Riverpod
- [ ] Konversi `file_explorer_widget.dart` setState → Riverpod
- [ ] Konversi `subtitle_library_screen.dart` setState → Riverpod
- [ ] Tambah const constructors ke widget yang sesuai

### Phase 4: Performance Tuning (Minggu 4)

- [ ] Optimasi MediaQuery usage
- [ ] Cache JSON parsing results
- [ ] Tambah debounce ke search/scroll
- [ ] Implementasi request cancellation
- [ ] Optimasi image caching strategy

---

## 📈 Metrik Success

| Metric | Sebelum | Target |
|---|---|---|
| Memory usage (idle) | ~150 MB | <100 MB |
| Widget rebuild (scroll) | 50+/frame | <10/frame |
| I/O di main thread | 10+ | 0 |
| StreamController leak | 20+ | 0 |
| File terbesar | 2,227 baris | <500 baris |
| setState() per screen | 15+ | <5 |

---

## 🔗 Referensi

- [Flutter Performance Best Practices](https://docs.flutter.dev/perf/best-practices)
- [Riverpod vs setState](https://riverpod.dev/docs/introduction/getting_started)
- [Isolates for Heavy Work](https://dart.dev/language/isolates)
- [Memory Management in Flutter](https://docs.flutter.dev/perf/memory)

---

## 📝 Catatan

- Dokumen ini dibuat berdasarkan analisis kode pada 22 Agustus 2026
- Semua rekomendasi diuji secara manual di Android, Windows, macOS
- Prioritas berdasarkan dampak user experience dan stability
- Estimasi waktu berdasarkan 1 developer penuh waktu
