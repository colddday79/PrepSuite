package app.prepsuite.android.feature.voice

import android.graphics.RuntimeShader
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import app.prepsuite.android.designsystem.Prep
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.sin
import kotlin.random.Random

@Composable
fun rememberReduceMotion(): Boolean {
    val context = LocalContext.current
    return remember {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
}

// Stand-in loudness for the interviewer's voice until TTS audio can be analysed directly.
fun speechEnvelope(t: Float): Float {
    val syllables = abs(sin(t * 9.3f)) * 0.55f + abs(sin(t * 5.1f + 1.3f)) * 0.25f
    val phrase = 0.65f + 0.35f * sin(t * 1.7f)
    return (syllables * phrase).coerceIn(0f, 1f)
}

@Composable
fun PresenceOrb(
    time: () -> Float,
    level: () -> Float,
    energy: () -> Float,
    warmth: () -> Float,
    modifier: Modifier = Modifier,
) {
    if (Build.VERSION.SDK_INT >= 33) {
        val shader = rememberOrbShader()
        if (shader != null) {
            ShaderOrb(shader, time, level, energy, warmth, modifier)
            return
        }
    }
    FallbackOrb(level, energy, warmth, modifier)
}

@RequiresApi(33)
@Composable
private fun rememberOrbShader(): RuntimeShader? = remember {
    runCatching { RuntimeShader(ORB_AGSL) }
        .onFailure { Log.w("PrepSuite", "Orb shader unavailable; using fallback", it) }
        .getOrNull()
}

@RequiresApi(33)
@Composable
private fun ShaderOrb(
    shader: RuntimeShader,
    time: () -> Float,
    level: () -> Float,
    energy: () -> Float,
    warmth: () -> Float,
    modifier: Modifier,
) {
    val c = Prep.colors
    val brush = remember(shader) { ShaderBrush(shader) }
    val cool = c.voiceCool.toArgb()
    val warm = c.voiceWarm.toArgb()
    Spacer(
        modifier.drawBehind {
            shader.setFloatUniform("uResolution", size.width, size.height)
            shader.setFloatUniform("uTime", time())
            shader.setFloatUniform("uLevel", level())
            shader.setFloatUniform("uEnergy", energy())
            shader.setFloatUniform("uWarmth", warmth())
            shader.setColorUniform("uCool", cool)
            shader.setColorUniform("uWarm", warm)
            drawRect(brush)
        },
    )
}

@Composable
private fun FallbackOrb(level: () -> Float, energy: () -> Float, warmth: () -> Float, modifier: Modifier) {
    val c = Prep.colors
    Canvas(modifier) {
        val l = level()
        val tint = lerp(c.voiceCool, c.voiceWarm, warmth())
        val r = size.minDimension / 2f * 0.62f * (1f + 0.02f * energy() + 0.06f * l)
        drawCircle(Brush.radialGradient(listOf(tint.copy(alpha = 0.18f + 0.2f * l), Color.Transparent), center, r * 1.7f), r * 1.7f)
        drawCircle(
            Brush.radialGradient(
                listOf(Color.White.copy(alpha = 0.55f + 0.3f * l), tint.copy(alpha = 0.5f), tint.copy(alpha = 0.06f)),
                center,
                r,
            ),
            r,
        )
    }
}

// Sixty hairline ticks; during an answer one tick lights per two seconds, so a full ring is the two-minute cap.
@Composable
fun TickRing(
    phase: VoicePhase,
    time: () -> Float,
    progress: () -> Float,
    warmth: () -> Float,
    modifier: Modifier = Modifier,
) {
    val c = Prep.colors
    val ringAlpha by animateFloatAsState(
        when (phase) {
            VoicePhase.Idle -> 0.25f
            VoicePhase.Speaking -> 0.45f
            VoicePhase.YourTurn -> 0.55f
            VoicePhase.Listening -> 0.7f
            VoicePhase.Thinking -> 0.45f
            VoicePhase.Review -> 0f
        },
        tween(600),
        label = "ringAlpha",
    )
    val thinking = phase == VoicePhase.Thinking
    val cometAlpha by animateFloatAsState(
        if (thinking) 1f else 0f,
        tween(400, delayMillis = if (thinking) 250 else 0),
        label = "comet",
    )
    Canvas(modifier) {
        val hair = 1.dp.toPx()
        val r = size.minDimension / 2f - 2.dp.toPx()
        val light = lerp(c.voiceCool, c.voiceWarm, warmth())
        val lit = (progress().coerceIn(0f, 1f) * 60f).toInt()
        for (i in 0 until 60) {
            val a = (i * 6f - 90f) * PI.toFloat() / 180f
            val dir = Offset(cos(a), sin(a))
            val len = (if (i % 5 == 0) 8.dp else 3.5.dp).toPx()
            val on = i < lit
            val tickColor = if (on) (if (i >= 52) c.pending else light) else c.voiceFaint
            drawLine(
                color = tickColor,
                start = center + dir * (r - len),
                end = center + dir * r,
                strokeWidth = if (on) hair * 1.5f else hair,
                cap = StrokeCap.Round,
                alpha = if (on) 0.95f else ringAlpha,
            )
        }
        val inner = r - 16.dp.toPx()
        rotate(time() * 3f) {
            drawArc(
                color = c.voiceFaint,
                startAngle = 0f,
                sweepAngle = 300f,
                useCenter = false,
                topLeft = center - Offset(inner, inner),
                size = Size(inner * 2, inner * 2),
                style = Stroke(0.75.dp.toPx()),
                alpha = ringAlpha * 0.8f,
            )
        }
        if (cometAlpha > 0f) {
            rotate(time() * 225f) {
                drawArc(
                    brush = Brush.sweepGradient(0f to Color.Transparent, 0.25f to light, 1f to light, center = center),
                    startAngle = 0f,
                    sweepAngle = 90f,
                    useCenter = false,
                    topLeft = center - Offset(inner, inner),
                    size = Size(inner * 2, inner * 2),
                    style = Stroke(1.5.dp.toPx(), cap = StrokeCap.Round),
                    alpha = cometAlpha,
                )
            }
        }
    }
}

private class Mote(val x: Float, val y: Float, val depth: Float, val phase: Float)

@Composable
fun DustField(time: () -> Float, color: Color, modifier: Modifier = Modifier) {
    val motes = remember {
        val rnd = Random(20260923)
        List(36) { Mote(rnd.nextFloat(), rnd.nextFloat(), 0.3f + rnd.nextFloat() * 0.7f, rnd.nextFloat() * 6.28f) }
    }
    Canvas(modifier) {
        val t = time()
        motes.forEach { m ->
            val y = (((m.y - t * 0.004f * m.depth) % 1f) + 1f) % 1f
            val x = m.x + sin(t * 0.2f + m.phase) * 0.01f
            drawCircle(
                color = color,
                radius = (0.6f + m.depth * 0.9f).dp.toPx(),
                center = Offset(x * size.width, y * size.height),
                alpha = 0.05f + 0.16f * m.depth,
            )
        }
    }
}

@Composable
fun Waveform(levels: List<Float>, color: Color, modifier: Modifier = Modifier) {
    Canvas(modifier.fillMaxWidth().height(44.dp)) {
        val bars = 56
        val gap = 2.dp.toPx()
        val w = (size.width - gap * (bars - 1)) / bars
        for (i in 0 until bars) {
            val v = if (levels.isEmpty()) 0f else {
                val from = i * levels.size / bars
                val to = max(from + 1, (i + 1) * levels.size / bars).coerceAtMost(levels.size)
                (from until to).maxOfOrNull { levels[it] } ?: 0f
            }
            val h = max(2.dp.toPx(), v * size.height)
            drawRoundRect(
                color = color,
                topLeft = Offset(i * (w + gap), (size.height - h) / 2f),
                size = Size(w, h),
                cornerRadius = CornerRadius(w / 2f),
                alpha = 0.35f + 0.65f * v,
            )
        }
    }
}

// Analytic sphere with two noise shells for depth, a fresnel rim and an analytic bloom. No raymarching,
// so the per-pixel cost stays small enough for mid-range phones.
private const val ORB_AGSL = """
uniform float2 uResolution;
uniform float uTime;
uniform float uLevel;
uniform float uEnergy;
uniform float uWarmth;
layout(color) uniform half4 uCool;
layout(color) uniform half4 uWarm;

const float RADIUS = 0.62;

float hash13(float3 p) {
    float3 q = fract(p * 0.1031);
    q += dot(q, q.zyx + 31.32);
    return fract((q.x + q.y) * q.z);
}

float vnoise(float3 x) {
    float3 i = floor(x);
    float3 f = fract(x);
    float3 u = f * f * (3.0 - 2.0 * f);
    float n000 = hash13(i);
    float n100 = hash13(i + float3(1.0, 0.0, 0.0));
    float n010 = hash13(i + float3(0.0, 1.0, 0.0));
    float n110 = hash13(i + float3(1.0, 1.0, 0.0));
    float n001 = hash13(i + float3(0.0, 0.0, 1.0));
    float n101 = hash13(i + float3(1.0, 0.0, 1.0));
    float n011 = hash13(i + float3(0.0, 1.0, 1.0));
    float n111 = hash13(i + float3(1.0, 1.0, 1.0));
    float nx00 = mix(n000, n100, u.x);
    float nx10 = mix(n010, n110, u.x);
    float nx01 = mix(n001, n101, u.x);
    float nx11 = mix(n011, n111, u.x);
    return mix(mix(nx00, nx10, u.y), mix(nx01, nx11, u.y), u.z);
}

float fbm3(float3 p) {
    float3 q = p;
    float s = 0.0;
    float a = 0.5;
    for (int i = 0; i < 3; i++) {
        s += a * vnoise(q);
        q = q * 2.02 + float3(1.7, 9.2, 3.1);
        a *= 0.5;
    }
    return s / 0.875;
}

half4 main(float2 fragCoord) {
    float2 p = (fragCoord - 0.5 * uResolution) / (0.5 * min(uResolution.x, uResolution.y));
    float d = length(p);
    float t = uTime;
    float3 tint = mix(float3(uCool.rgb), float3(uWarm.rgb), uWarmth);

    float2 dir = p / max(d, 0.0001);
    float wob = vnoise(float3(dir * 1.4, t * 0.35)) - 0.5;
    float radius = RADIUS * (1.0 + 0.02 * uEnergy + uLevel * (0.03 + 0.10 * wob));
    float r = d / radius;

    float3 white = float3(0.94, 0.97, 1.0);
    float3 col = float3(0.0);
    if (r < 1.0) {
        float z = sqrt(1.0 - r * r);
        float3 n = float3(p / radius, z);
        // Slow rotation about the vertical axis so the filaments read as a 3D volume.
        float ca = cos(t * 0.12);
        float sa = sin(t * 0.12);
        float3 q = float3(ca * n.x + sa * n.z, n.y, -sa * n.x + ca * n.z);
        float speed = 0.5 + uEnergy;

        // Ridged turbulence gives thin luminous filaments instead of a cloudy fill.
        float f1 = fbm3(q * 1.6 + float3(0.0, t * 0.05 * speed, 0.0));
        float filaments = pow(1.0 - abs(2.0 * f1 - 1.0), 7.0);
        // A finer inner layer drifting the other way adds parallax depth.
        float f2 = fbm3(q * 2.6 - float3(t * 0.04 * speed, 0.0, t * 0.03) + 11.0);
        float inner = pow(1.0 - abs(2.0 * f2 - 1.0), 10.0) * z;

        col = tint * (0.05 + 0.08 * uEnergy) * z;
        col += mix(tint, white, 0.35) * filaments * (0.35 + 0.55 * uEnergy + 0.9 * uLevel) * (0.35 + 0.65 * z);
        col += tint * inner * (0.25 + 0.6 * uLevel);
        col += white * exp(-r * r * 7.0) * (0.10 + 0.25 * uEnergy + 0.55 * uLevel);
        col += mix(tint, white, 0.5) * pow(1.0 - z, 5.0) * (1.1 + 1.2 * uLevel);
        col *= 1.0 - smoothstep(0.985, 1.0, r);
    }
    float halo = exp(-max(r - 1.0, 0.0) * 6.0) * smoothstep(0.9, 1.0, r);
    col += tint * halo * (0.10 + 0.35 * uLevel + 0.10 * uEnergy);
    col *= 1.0 - smoothstep(0.82, 1.0, d);
    col = 1.0 - exp(-col * 1.6);
    col += (hash13(float3(fragCoord, t * 60.0)) - 0.5) / 255.0;
    col = max(col, float3(0.0));
    float a = clamp(max(col.r, max(col.g, col.b)), 0.0, 1.0);
    return half4(half3(col), half(a));
}
"""
