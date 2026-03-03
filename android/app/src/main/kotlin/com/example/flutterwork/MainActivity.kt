package com.example.flutterwork

import android.content.ContentValues
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.IOException

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "paint_timelapse/gallery"
        private const val METHOD_SAVE_GIF = "saveGifToGallery"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != METHOD_SAVE_GIF) {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val args = call.arguments as? Map<*, *>
                val bytes = args?.get("bytes") as? ByteArray
                val fileName = args?.get("fileName") as? String

                if (bytes == null || bytes.isEmpty() || fileName.isNullOrBlank()) {
                    result.error("invalid_args", "Missing bytes or fileName", null)
                    return@setMethodCallHandler
                }

                try {
                    val savedUri = saveGifToGallery(bytes, fileName)
                    if (savedUri == null) {
                        result.error("save_failed", "Could not save GIF to gallery", null)
                    } else {
                        result.success(savedUri.toString())
                    }
                } catch (e: Exception) {
                    result.error("save_failed", e.message, null)
                }
            }
    }

    private fun saveGifToGallery(bytes: ByteArray, fileName: String): Uri? {
        val resolver = applicationContext.contentResolver
        val collectionUri = MediaStore.Images.Media.getContentUri(
            MediaStore.VOLUME_EXTERNAL_PRIMARY
        )
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, "image/gif")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    "${Environment.DIRECTORY_PICTURES}/ColoringTimelapse"
                )
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
        }

        val uri = resolver.insert(collectionUri, values) ?: return null
        try {
            resolver.openOutputStream(uri)?.use { stream ->
                stream.write(bytes)
                stream.flush()
            } ?: throw IOException("Could not open gallery output stream")

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val pendingValues = ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                }
                resolver.update(uri, pendingValues, null, null)
            }
            return uri
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
    }
}
