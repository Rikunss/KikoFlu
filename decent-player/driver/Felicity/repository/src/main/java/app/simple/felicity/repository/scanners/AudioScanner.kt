package app.simple.felicity.repository.scanners

import android.util.Log
import app.simple.felicity.preferences.LibraryPreferences
import java.io.File

class AudioScanner() {

    companion object {
        private const val TAG = "AudioScanner"

        private val AUDIO_EXTENSIONS = hashSetOf(
                "mp3", // MPEG Layer III Audio
                "m4a", // MPEG-4 Audio
                "aac", // Advanced Audio Coding
                "ts", // MPEG Transport Stream
                "flac", // Free Lossless Audio Codec
                "mid", // MIDI Audio
                "xmf", // eXtensible Music Format
                "mxmf", // Mobile eXtensible Music Format
                "rtttl", // Ring Tone Text Transfer Language
                "rtx", // Ring Tone XML
                "ota", // Over The Air
                "imy", // iMelody
                "ogg", // Ogg Vorbis Audio
                "opus", // Opus Audio Codec
                "wav", // Waveform Audio File Format
                "alac", // Apple Lossless Audio Codec
                "aiff", // Audio Interchange File Format
                "wma", // Windows Media Audio
                "ape", // Monkey's Audio
                "dsd", // Direct Stream Digital
                "pcm", // Pulse-Code Modulation
                "dsf", // DSD Stream File
                "dff" // DSD Interchange File Format
        )

        private val DSD_EXTENSIONS = hashSetOf("dsf", "dff", "dsd")

        /** Directories to always exclude (messaging apps, system sounds, etc.) */
        private val EXCLUDED_DIRS = listOf(
            "/WhatsApp/",
            "/WhatsApp Business/",
            "/Telegram/",
            "/Signal/",
            "/Android/media/com.whatsapp",
            "/Android/media/org.telegram",
            "/Android/media/org.thoughtcrime.securesms",
            "/Notifications/",
            "/Ringtones/",
            "/Alarms/",
            "/Recordings/",
        )
    }

    fun getAudioFiles(root: File): List<File> {
        if (!root.exists() || !root.isDirectory) {
            Log.e(TAG, "Invalid root directory: ${root.absolutePath}")
            return emptyList()
        } else {
            Log.d(TAG, "Scanning for audio files in: ${root.absolutePath}")
        }

        // Read user preferences fresh on every scan
        val skipNomedia = LibraryPreferences.isSkipNomedia()
        val skipHiddenFiles = LibraryPreferences.isSkipHiddenFiles()
        val skipHiddenFolders = LibraryPreferences.isSkipHiddenFolders()
        val skipDsd = LibraryPreferences.isSkipDsd()

        return collectAudio(root, skipNomedia, skipHiddenFiles, skipHiddenFolders, skipDsd)
    }

    private fun File.isAudioFile(skipDsd: Boolean): Boolean {
        val ext = extension.lowercase()
        if (ext.isEmpty()) return false
        if (!AUDIO_EXTENSIONS.contains(ext)) return false
        if (skipDsd && DSD_EXTENSIONS.contains(ext)) return false
        return true
    }

    private fun collectAudio(
            root: File,
            skipNomedia: Boolean,
            skipHiddenFiles: Boolean,
            skipHiddenFolders: Boolean,
            skipDsd: Boolean
    ): List<File> {
        val result = mutableListOf<File>()

        root.walkTopDown()
            .onEnter { dir ->
                if (skipNomedia && File(dir, ".nomedia").exists()) {
                    Log.d(TAG, "Skipping .nomedia folder: ${dir.absolutePath}")
                    return@onEnter false
                }
                if (skipHiddenFolders && dir.name.startsWith(".")) {
                    Log.d(TAG, "Skipping hidden folder: ${dir.absolutePath}")
                    return@onEnter false
                }
                // Skip messaging app media (WhatsApp, Telegram, etc.)
                if (EXCLUDED_DIRS.any { dir.absolutePath.contains(it, ignoreCase = true) }) {
                    return@onEnter false
                }
                return@onEnter true
            }
            .forEach { file ->
                if (file.isFile && file.length() > 0 && file.isAudioFile(skipDsd)) {
                    if (skipHiddenFiles && file.name.startsWith(".")) {
                        Log.d(TAG, "Skipping hidden file: ${file.absolutePath}")
                        return@forEach
                    }
                    result.add(file)
                }
            }

        return result
    }
}

