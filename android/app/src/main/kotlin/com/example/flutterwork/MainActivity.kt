package com.example.flutterwork

import android.content.ContentValues
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.IOException
import kotlin.math.max
import kotlin.math.min

class MainActivity : FlutterActivity() {
    companion object {
        private const val METHOD_CHANNEL = "paint_timelapse/video_export"
        private const val PROGRESS_CHANNEL = "paint_timelapse/video_export_progress"
        private const val METHOD_EXPORT_MP4 = "exportMp4ToGallery"
        private const val MIME_TYPE = "video/avc"
        private const val TIMEOUT_US = 10_000L
    }

    private var progressSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, PROGRESS_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    progressSink = events
                }

                override fun onCancel(arguments: Any?) {
                    progressSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != METHOD_EXPORT_MP4) {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val args = call.arguments as? Map<*, *>
                val exportId = args?.get("exportId") as? String
                val fileName = args?.get("fileName") as? String
                val rawPath = args?.get("rawPath") as? String
                val frameCount = args?.get("frameCount") as? Int
                val width = args?.get("width") as? Int
                val height = args?.get("height") as? Int
                val frameDurationMs = args?.get("frameDurationMs") as? Int

                if (exportId.isNullOrBlank() ||
                    fileName.isNullOrBlank() ||
                    rawPath.isNullOrBlank() ||
                    frameCount == null ||
                    width == null ||
                    height == null ||
                    frameDurationMs == null ||
                    frameCount <= 0 ||
                    width <= 0 ||
                    height <= 0 ||
                    frameDurationMs <= 0
                ) {
                    result.error("invalid_args", "Missing or invalid export arguments", null)
                    return@setMethodCallHandler
                }

                Thread {
                    try {
                        val rawFile = File(rawPath)
                        if (!rawFile.exists()) {
                            throw IOException("Raw frame file not found")
                        }

                        val tempVideo = File(cacheDir, "$exportId.mp4")
                        if (tempVideo.exists()) {
                            tempVideo.delete()
                        }

                        encodeRawFramesToMp4(
                            rawFile = rawFile,
                            outputMp4 = tempVideo,
                            width = width,
                            height = height,
                            frameCount = frameCount,
                            frameDurationMs = frameDurationMs,
                            onProgress = { progress ->
                                emitProgress(exportId, progress * 0.95)
                            }
                        )

                        val savedUri = saveMp4ToGallery(tempVideo, fileName)
                            ?: throw IOException("Unable to save MP4 to gallery")

                        tempVideo.delete()
                        emitProgress(exportId, 1.0)
                        runOnUiThread {
                            result.success(savedUri.toString())
                        }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("export_failed", e.message, null)
                        }
                    }
                }.start()
            }
    }

    private fun emitProgress(exportId: String, progress: Double) {
        val clamped = progress.coerceIn(0.0, 1.0)
        runOnUiThread {
            progressSink?.success(
                mapOf(
                    "exportId" to exportId,
                    "progress" to clamped
                )
            )
        }
    }

    private fun encodeRawFramesToMp4(
        rawFile: File,
        outputMp4: File,
        width: Int,
        height: Int,
        frameCount: Int,
        frameDurationMs: Int,
        onProgress: (Double) -> Unit
    ) {
        val frameRgbaSize = width * height * 4
        val minExpectedBytes = frameRgbaSize.toLong() * frameCount.toLong()
        if (rawFile.length() < minExpectedBytes) {
            throw IOException("Raw frame file is incomplete")
        }

        val codec = MediaCodec.createEncoderByType(MIME_TYPE)
        val colorFormat = selectColorFormat(codec)
        val frameRate = max(1, 1000 / frameDurationMs)
        val bitRate = max(1_000_000, width * height * 6)

        val format = MediaFormat.createVideoFormat(MIME_TYPE, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, colorFormat)
            setInteger(MediaFormat.KEY_BIT_RATE, bitRate)
            setInteger(MediaFormat.KEY_FRAME_RATE, frameRate)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }

        codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        codec.start()

        val muxer = MediaMuxer(outputMp4.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        val bufferInfo = MediaCodec.BufferInfo()
        var trackIndex = -1
        var muxerStarted = false
        val rgbaBuffer = ByteArray(frameRgbaSize)
        val yuvBuffer = ByteArray(width * height * 3 / 2)

        FileInputStream(rawFile).use { input ->
            for (frameIndex in 0 until frameCount) {
                if (!readFully(input, rgbaBuffer)) {
                    throw IOException("Failed to read frame data")
                }

                val isPlanar = colorFormat == MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Planar
                rgbaToYuv420(
                    rgba = rgbaBuffer,
                    yuv = yuvBuffer,
                    width = width,
                    height = height,
                    semiPlanar = !isPlanar,
                )

                var queued = false
                while (!queued) {
                    val inputIndex = codec.dequeueInputBuffer(TIMEOUT_US)
                    if (inputIndex < 0) {
                        val drainResult = drainEncoder(codec, muxer, bufferInfo, trackIndex, muxerStarted)
                        trackIndex = drainResult.trackIndex
                        muxerStarted = drainResult.muxerStarted
                        continue
                    }

                    val inputBuffer = codec.getInputBuffer(inputIndex)
                        ?: throw IOException("Encoder input buffer unavailable")
                    inputBuffer.clear()
                    inputBuffer.put(yuvBuffer)
                    val presentationUs = frameIndex.toLong() * frameDurationMs.toLong() * 1000L
                    codec.queueInputBuffer(
                        inputIndex,
                        0,
                        yuvBuffer.size,
                        presentationUs,
                        0
                    )
                    queued = true
                }

                val drainResult = drainEncoder(codec, muxer, bufferInfo, trackIndex, muxerStarted)
                trackIndex = drainResult.trackIndex
                muxerStarted = drainResult.muxerStarted
                onProgress((frameIndex + 1).toDouble() / frameCount.toDouble())
            }
        }

        var eosQueued = false
        while (!eosQueued) {
            val inputIndex = codec.dequeueInputBuffer(TIMEOUT_US)
            if (inputIndex >= 0) {
                val eosPtsUs = frameCount.toLong() * frameDurationMs.toLong() * 1000L
                codec.queueInputBuffer(
                    inputIndex,
                    0,
                    0,
                    eosPtsUs,
                    MediaCodec.BUFFER_FLAG_END_OF_STREAM
                )
                eosQueued = true
            } else {
                val drainResult = drainEncoder(codec, muxer, bufferInfo, trackIndex, muxerStarted)
                trackIndex = drainResult.trackIndex
                muxerStarted = drainResult.muxerStarted
            }
        }

        var endOfStreamReached = false
        while (!endOfStreamReached) {
            val drainResult = drainEncoder(codec, muxer, bufferInfo, trackIndex, muxerStarted)
            trackIndex = drainResult.trackIndex
            muxerStarted = drainResult.muxerStarted
            endOfStreamReached = drainResult.endOfStream
        }

        codec.stop()
        codec.release()
        if (muxerStarted) {
            muxer.stop()
        }
        muxer.release()
    }

    private data class DrainResult(
        val trackIndex: Int,
        val muxerStarted: Boolean,
        val endOfStream: Boolean
    )

    private fun drainEncoder(
        codec: MediaCodec,
        muxer: MediaMuxer,
        bufferInfo: MediaCodec.BufferInfo,
        currentTrackIndex: Int,
        currentMuxerStarted: Boolean
    ): DrainResult {
        var trackIndex = currentTrackIndex
        var muxerStarted = currentMuxerStarted
        var endOfStream = false

        while (true) {
            val outputIndex = codec.dequeueOutputBuffer(bufferInfo, TIMEOUT_US)
            when {
                outputIndex == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    break
                }

                outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    if (muxerStarted) {
                        throw IOException("Encoder format changed twice")
                    }
                    trackIndex = muxer.addTrack(codec.outputFormat)
                    muxer.start()
                    muxerStarted = true
                }

                outputIndex >= 0 -> {
                    val outputBuffer = codec.getOutputBuffer(outputIndex)
                        ?: throw IOException("Encoder output buffer unavailable")

                    if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0) {
                        bufferInfo.size = 0
                    }

                    if (bufferInfo.size > 0) {
                        if (!muxerStarted || trackIndex < 0) {
                            throw IOException("Muxer not started before encoded data")
                        }
                        outputBuffer.position(bufferInfo.offset)
                        outputBuffer.limit(bufferInfo.offset + bufferInfo.size)
                        muxer.writeSampleData(trackIndex, outputBuffer, bufferInfo)
                    }
                    codec.releaseOutputBuffer(outputIndex, false)

                    if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        endOfStream = true
                        break
                    }
                }
            }
        }

        return DrainResult(trackIndex, muxerStarted, endOfStream)
    }

    private fun selectColorFormat(codec: MediaCodec): Int {
        val capabilities = codec.codecInfo.getCapabilitiesForType(MIME_TYPE)
        val preferred = intArrayOf(
            MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420SemiPlanar,
            MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Planar,
            MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible
        )
        for (preferredColor in preferred) {
            if (capabilities.colorFormats.any { it == preferredColor }) {
                return preferredColor
            }
        }
        throw IOException("No supported YUV420 color format found")
    }

    private fun readFully(input: FileInputStream, target: ByteArray): Boolean {
        var offset = 0
        while (offset < target.size) {
            val read = input.read(target, offset, target.size - offset)
            if (read <= 0) return false
            offset += read
        }
        return true
    }

    private fun rgbaToYuv420(
        rgba: ByteArray,
        yuv: ByteArray,
        width: Int,
        height: Int,
        semiPlanar: Boolean
    ) {
        val frameSize = width * height
        var yIndex = 0
        var uIndex = frameSize
        var vIndex = frameSize + (frameSize / 4)

        var uvInterleavedIndex = frameSize
        for (j in 0 until height) {
            for (i in 0 until width) {
                val rgbaIndex = ((j * width) + i) * 4
                val r = rgba[rgbaIndex].toInt() and 0xFF
                val g = rgba[rgbaIndex + 1].toInt() and 0xFF
                val b = rgba[rgbaIndex + 2].toInt() and 0xFF

                val y = clamp(((66 * r + 129 * g + 25 * b + 128) shr 8) + 16)
                val u = clamp(((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128)
                val v = clamp(((112 * r - 94 * g - 18 * b + 128) shr 8) + 128)

                yuv[yIndex++] = y.toByte()

                if (j % 2 == 0 && i % 2 == 0) {
                    if (semiPlanar) {
                        yuv[uvInterleavedIndex++] = u.toByte()
                        yuv[uvInterleavedIndex++] = v.toByte()
                    } else {
                        yuv[uIndex++] = u.toByte()
                        yuv[vIndex++] = v.toByte()
                    }
                }
            }
        }
    }

    private fun clamp(value: Int): Int {
        return min(255, max(0, value))
    }

    private fun saveMp4ToGallery(sourceVideo: File, fileName: String): Uri? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = applicationContext.contentResolver
            val collection = MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, "video/mp4")
                put(
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    "${Environment.DIRECTORY_MOVIES}/ColoringTimelapse"
                )
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }

            val uri = resolver.insert(collection, values) ?: return null
            try {
                resolver.openOutputStream(uri)?.use { output ->
                    sourceVideo.inputStream().use { input ->
                        input.copyTo(output)
                    }
                } ?: throw IOException("Unable to open MediaStore output stream")

                val readyValues = ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                }
                resolver.update(uri, readyValues, null, null)
                return uri
            } catch (e: Exception) {
                resolver.delete(uri, null, null)
                throw e
            }
        }

        val moviesDir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES),
            "ColoringTimelapse"
        )
        if (!moviesDir.exists()) {
            moviesDir.mkdirs()
        }
        val outputFile = File(moviesDir, fileName)
        sourceVideo.copyTo(outputFile, overwrite = true)
        MediaScannerConnection.scanFile(
            applicationContext,
            arrayOf(outputFile.absolutePath),
            arrayOf("video/mp4"),
            null
        )
        return Uri.fromFile(outputFile)
    }
}
