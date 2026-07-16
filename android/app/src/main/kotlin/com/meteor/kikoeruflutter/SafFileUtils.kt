package com.meteor.kikoeruflutter

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/**
 * SAF (Storage Access Framework) file utilities for importing folders
 * from content:// URIs on Android 11+.
 *
 * file_picker v8 on Android 11+ returns SAF content URIs (content://...)
 * instead of real file paths. Dart's [File] and [Directory] APIs cannot
 * read from content URIs, so we need to copy files through Android's
 * ContentResolver via DocumentFile.
 *
 * Channel methods:
 *  - "copyFromSafUri": Copies an entire SAF directory tree to a local path.
 *    Arguments: { "safUri": String, "destDir": String }
 *    Returns: null on success, or throws on error.
 */
class SafFileUtils {
    companion object {
        const val CHANNEL = "com.kikoeru.flutter/saf_file_utils"

        fun register(flutterEngine: FlutterEngine, context: Context) {
            val channel = MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                CHANNEL
            )
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "copyFromSafUri" -> {
                        val safUri = call.argument<String>("safUri")
                        val destDir = call.argument<String>("destDir")
                        if (safUri == null || destDir == null) {
                            result.error("INVALID_ARGS", "safUri and destDir are required", null)
                            return@setMethodCallHandler
                        }
                        try {
                            copyFromSafUri(context, safUri, destDir)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("COPY_FAILED", e.message ?: "Unknown error", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }

        /**
         * Recursively copy all files from a SAF tree URI to a local directory.
         */
        private fun copyFromSafUri(context: Context, safUri: String, destDirPath: String) {
            val uri = Uri.parse(safUri)

            try {
                context.contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            } catch (_: SecurityException) {
            }

            val treeDocumentFile = DocumentFile.fromTreeUri(context, uri)
                ?: throw IllegalStateException("Cannot open SAF tree URI: $safUri")

            val destDir = File(destDirPath)
            if (!destDir.exists()) {
                destDir.mkdirs()
            }

            copyFilesRecursive(context, treeDocumentFile, destDir)
        }

        private fun copyFilesRecursive(context: Context, documentFile: DocumentFile, destDir: File) {
            for (child in documentFile.listFiles()) {
                val name = child.name ?: continue
                if (name.startsWith(".")) continue

                if (child.isDirectory) {
                    val subDir = File(destDir, name)
                    subDir.mkdirs()
                    copyFilesRecursive(context, child, subDir)
                } else if (child.isFile) {
                    try {
                        val inputStream = context.contentResolver.openInputStream(child.uri)
                        val outputFile = File(destDir, name)
                        inputStream?.use { input ->
                            FileOutputStream(outputFile).use { output ->
                                input.copyTo(output)
                            }
                        }
                    } catch (e: Exception) {
                    }
                }
            }
        }
    }
}
