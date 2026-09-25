package app.prepsuite.android.feature.voice

import android.graphics.SurfaceTexture
import android.media.MediaPlayer
import android.view.Surface
import android.view.TextureView
import androidx.annotation.RawRes
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView

// Plays the Blender-rendered presence loop. It is rendered on black, so Screen blending drops the
// background and lets the voice canvas show through; the level pulse keeps it reacting to speech.
@Composable
fun PresenceVideo(
    @RawRes video: Int,
    level: () -> Float,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val player = remember {
        MediaPlayer().apply {
            context.resources.openRawResourceFd(video).use { setDataSource(it.fileDescriptor, it.startOffset, it.length) }
            isLooping = true
            setVolume(0f, 0f)
        }
    }
    DisposableEffect(player) { onDispose { player.release() } }

    AndroidView(
        factory = { ctx ->
            TextureView(ctx).apply {
                isOpaque = false
                surfaceTextureListener = object : TextureView.SurfaceTextureListener {
                    override fun onSurfaceTextureAvailable(texture: SurfaceTexture, width: Int, height: Int) {
                        player.setSurface(Surface(texture))
                        player.setOnPreparedListener { it.start() }
                        player.prepareAsync()
                    }

                    override fun onSurfaceTextureSizeChanged(texture: SurfaceTexture, width: Int, height: Int) = Unit
                    override fun onSurfaceTextureDestroyed(texture: SurfaceTexture): Boolean {
                        runCatching { player.setSurface(null) }
                        return true
                    }

                    override fun onSurfaceTextureUpdated(texture: SurfaceTexture) = Unit
                }
            }
        },
        modifier = modifier.graphicsLayer {
            val pulse = 1f + 0.05f * level()
            scaleX = pulse
            scaleY = pulse
            compositingStrategy = CompositingStrategy.Offscreen
            blendMode = BlendMode.Screen
        },
    )
}
