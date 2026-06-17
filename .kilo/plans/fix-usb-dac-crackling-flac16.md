# Ringkasan Fix Crackling FLAC 16-bit via USB DAC

## Kesimpulan akar masalah

Crackling pada file `.flac` 16-bit bukan disebabkan oleh FLAC, PCM 16-bit, sample rate, atau decoder. Log menunjukkan format sudah benar:

- `sampleRate=48000Hz`
- `channels=2`
- `encoding=PCM_16BIT`
- `bytesPerFrame=4`
- `Format match: Requested=16 bit, DAC reports=16 bit — OK`

Akar masalah adalah **underrun pada USB libusb isochronous path**. ExoPlayer/decoder berhasil mengirim PCM ke ring buffer, tetapi USB consumer terlalu cepat atau timing event thread tidak stabil, sehingga ring buffer kosong dan driver mengisi USB packet dengan silence:

```text
RING BUFFER UNDERRUN: expected 1920 B, read 1296 B, filling 624 B with silence
RING BUFFER UNDERRUN: expected 1920 B, read 0 B, filling 1920 B with silence
```

Health log terakhir menunjukkan:

```text
totalUnderruns=1756
totalShortWrites=0
totalRequested=3571937
totalActuallyWritten=3571937
```

Artinya producer berhasil menulis semua data, tetapi USB transfer kehabisan data.

## Bukti penting dari log

- Playback memakai libusb sink:
  ```text
  [AUDIO-SINK] Priority: libusb > AAudio > Default. Selected: LIBUSB
  ```

- PCM 16-bit dikirim ke USB DAC:
  ```text
  [PCM16] handleBuffer ... dispatching to writeI16()
  RING_WRITE_I16 ... written=...
  ```

- Tidak ada short write dari JNI/native producer:
  ```text
  totalShortWrites=0
  ```

- Banyak underrun:
  ```text
  totalUnderruns=1756
  ```

- Ring buffer pernah hampir penuh:
  ```text
  ringUsed=1045508/1048576
  ```

Ini menunjukkan pola tidak stabil: kadang producer lebih cepat dari consumer, kadang consumer lebih cepat dari producer. Saat consumer kehabisan data, USB packet diisi silence dan terdengar sebagai crackle/pop.

## Rencana fix prioritas

### 1. Validasi cepat

Tujuan: pastikan crackling benar-benar berasal dari libusb path, bukan file/decoder/UI.

Langkah:

- Matikan sementara USB DAC direct/libusb path.
- Putar file `.flac` 16-bit yang sama melalui AAudio/default.
- Bandingkan log underrun.

Kriteria validasi:

- Jika AAudio/default bersih, maka FLAC/decoder aman.
- Jika tetap crackle, selidiki UI/rendering stutter atau media decoder.

### 2. Fallback sink yang lebih stabil

Jika bit-perfect tidak wajib, gunakan AAudio/default untuk USB DAC.

Alasan:

- AAudio managed oleh Android audio stack.
- Lebih stabil untuk USB audio dibanding custom libusb isochronous.
- Log awal menunjukkan AAudio exclusive ditolak, tetapi shared mode mungkin tetap stabil.

Implementasi:

- Tambahkan opsi preferensi output:
  - `libusb`
  - `aaudio`
  - `default`
- Saat underrun libusb terdeteksi, tampilkan warning dan fallback otomatis ke AAudio/default.

### 3. Perbaiki prebuffer dan submit policy libusb

Target utama: jangan biarkan `ringUsed` turun sampai 0.

Saran parameter awal:

- `kRingBufferCapacity` tetap 1 MB atau lebih besar.
- `kMinRingBeforeSubmit` naik dari `20000` byte menjadi minimal `96000–192000` byte.
  - 96000 byte ≈ 500 ms audio 48 kHz stereo 16-bit.
  - 192000 byte ≈ 1000 ms audio.
- Tambahkan `kMinRingBeforeResubmit`, misalnya `3840–7680` byte.
  - Callback hanya resubmit transfer jika ring masih punya minimal 2–4 transfer audio.

Logika:

```cpp
if (ringUsed < kMinRingBeforeSubmit) {
    defer first submission;
    return;
}

if (ringUsed < kMinRingBeforeResubmit) {
    do not resubmit immediately;
    allow brief underrun guard or pause stream;
}
```

Catatan: jangan langsung mengirim silence saat ring kosong jika tujuannya menghindari crackle. Lebih baik tunda/resync daripada memasukkan silence burst.

### 4. Tambahkan underrun recovery

Saat underrun terdeteksi:

- Catat timestamp underrun.
- Hentikan sementara submit transfer.
- Tunggu ring buffer mencapai prebuffer aman.
- Reset transfer queue bila perlu.
- Lanjutkan streaming dari titik buffer baru.

Pseudo-flow:

```text
underrun detected
  -> stop resubmitting transfers
  -> wait until ringUsed >= safePrebufferBytes
  -> reset pending transfer state if needed
  -> resubmit transfers gradually
```

Ini lebih baik daripada cascade silence:

```text
expected 1920 B, read 0 B, filling 1920 B with silence
```

### 5. Perbaiki scheduling event thread

Event thread menjalankan:

```cpp
libusb_handle_events_timeout_completed(context_, &tv, nullptr)
```

dengan timeout 1 ms. Jika callback tidak sesuai jadwal real 1 ms/isochronous packet, transfer bisa terlalu agresif.

Saran:

- Pastikan event thread punya priority lebih tinggi jika memungkinkan.
- Hindari log verbose saat streaming aktif karena log bisa mengganggu timing.
- Pertimbangkan callback-driven submission yang benar-benar menjaga jumlah transfer in-flight, bukan polling yang terlalu cepat.
- Tambahkan metrik:
  - interval callback aktual
  - ringUsed sebelum/sesudah callback
  - jumlah transfer in-flight
  - underrun per detik
  - prebuffer ms

### 6. Kurangi beban UI saat playback USB DAC aktif

Log menunjukkan UI/rendering berat:

```text
Choreographer: Skipped 105 frames
Choreographer: Skipped 118 frames
HWUI Davey! duration=1988ms
```

Meskipun bukan akar utama, ini bisa memperparah pasokan buffer.

Saat testing:

- Matikan FPS overlay.
- Matikan animasi waveform.
- Matikan blur cover/artwork color extraction saat playback.
- Hindari membuka sheet/dialog besar saat tes audio.

### 7. Tambahkan monitoring diagnostik

Tambahkan metrik yang mudah dibaca saat debug:

- `ringUsedMs = ringUsedBytes / bytesPerSecond`
- `underrunsPerSecond`
- `droppedFramesPerSecond`
- `writeFps`
- `consumerFps`
- `transferInFlight`
- `callbackIntervalMsP50/P95`

Untuk 48 kHz stereo 16-bit:

```text
bytesPerSecond = 48000 * 2 * 2 = 192000 B/s
```

Contoh:

```text
ringUsed=19200 B → 100 ms buffer
ringUsed=96000 B → 500 ms buffer
ringUsed=192000 B → 1000 ms buffer
```

## Kriteria fix selesai

Fix dianggap berhasil jika saat playback FLAC 16-bit 48 kHz stereo via USB DAC:

- `totalUnderruns` tidak naik setelah prebuffer stabil.
- `ringUsed` tidak turun ke 0.
- Tidak ada log:
  ```text
  RING BUFFER UNDERRUN
  filling ... with silence
  ```
- Audio tidak crackle/pop.
- `totalShortWrites=0`.
- `totalRequested == totalActuallyWritten` tetap terjaga.

## Urutan eksekusi yang disarankan

1. Buat opsi fallback sink AAudio/default.
2. Tambah monitoring `ringUsedMs`, underrun rate, callback interval.
3. Naikkan prebuffer awal libusb.
4. Tambahkan `kMinRingBeforeResubmit`.
5. Implementasi underrun recovery tanpa silence burst.
6. Optimalkan event thread scheduling.
7. Kurangi log verbose saat streaming aktif.
8. Validasi dengan FLAC 16-bit, WAV 16-bit, FLAC 96 kHz, dan DSD/24-bit jika ada.
