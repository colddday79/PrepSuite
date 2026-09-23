package app.prepsuite.android.designsystem

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

@Composable
fun PrimaryButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true) {
    val c = Prep.colors
    Box(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 52.dp)
            .clip(RoundedCornerShape(Radius.control))
            .background(if (enabled) c.text else c.surface2)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = Space.xl, vertical = Space.m),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, style = Prep.type.label, color = if (enabled) c.bg else c.text3)
    }
}

@Composable
fun QuietButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    color: Color = Prep.colors.text2,
    enabled: Boolean = true,
) {
    val tint = if (enabled) color else Prep.colors.text3.copy(alpha = 0.6f)
    Row(
        modifier = modifier
            .heightIn(min = 48.dp)
            .clip(RoundedCornerShape(Radius.control))
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = Space.m),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Space.s),
    ) {
        if (icon != null) PrepIcon(icon, null, tint, size = 20.dp)
        Text(text, style = Prep.type.label, color = tint)
    }
}

@Composable
fun IconAction(icon: ImageVector, description: String, onClick: () -> Unit, modifier: Modifier = Modifier, tint: Color = Prep.colors.text2) {
    Box(
        modifier = modifier
            .size(48.dp)
            .clip(CircleShape)
            .clickable(role = Role.Button, onClick = onClick)
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) {
        PrepIcon(icon, null, tint, size = 22.dp)
    }
}

@Composable
fun TopBar(title: String? = null, onBack: (() -> Unit)? = null, actions: @Composable RowScope.() -> Unit = {}) {
    Row(
        modifier = Modifier.fillMaxWidth().height(56.dp).padding(horizontal = Space.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (onBack != null) IconAction(PrepIcons.Back, "Back", onBack)
        if (title != null) {
            Text(
                title,
                style = Prep.type.titleM,
                color = Prep.colors.text,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f).padding(start = if (onBack == null) Space.l else Space.xs),
            )
        } else {
            Spacer(Modifier.weight(1f))
        }
        actions()
    }
}

@Composable
fun Hairline(modifier: Modifier = Modifier, color: Color = Prep.colors.line) {
    Box(modifier.fillMaxWidth().height(1.dp).background(color))
}

@Composable
fun SectionLabel(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        style = Prep.type.meta,
        color = Prep.colors.text3,
        modifier = modifier.padding(horizontal = Space.gutter).padding(top = Space.xxl, bottom = Space.s),
    )
}

@Composable
fun ListRow(
    title: String,
    modifier: Modifier = Modifier,
    meta: String? = null,
    value: String? = null,
    leading: ImageVector? = null,
    titleColor: Color = Prep.colors.text,
    onClick: (() -> Unit)? = null,
    trailing: (@Composable () -> Unit)? = null,
) {
    val c = Prep.colors
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = Space.gutter, vertical = Space.m),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Space.m),
    ) {
        if (leading != null) PrepIcon(leading, null, c.text2, size = 20.dp)
        Column(Modifier.weight(1f)) {
            Text(title, style = Prep.type.bodyL, color = titleColor)
            if (meta != null) Text(meta, style = Prep.type.meta, color = c.text3)
        }
        if (value != null) Text(value, style = Prep.type.body, color = c.text2)
        when {
            trailing != null -> trailing()
            onClick != null -> PrepIcon(PrepIcons.Chevron, null, c.text3, size = 18.dp)
        }
    }
}

@Composable
fun RadioRow(title: String, selected: Boolean, onClick: () -> Unit, meta: String? = null) {
    val c = Prep.colors
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .selectable(selected = selected, role = Role.RadioButton, onClick = onClick)
            .padding(horizontal = Space.gutter, vertical = Space.m),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Space.l),
    ) {
        Box(
            Modifier.size(20.dp).border(1.5.dp, if (selected) c.text else c.lineStrong, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            if (selected) Box(Modifier.size(10.dp).clip(CircleShape).background(c.text))
        }
        Column(Modifier.weight(1f)) {
            Text(title, style = Prep.type.bodyL, color = c.text)
            if (meta != null) Text(meta, style = Prep.type.meta, color = c.text3)
        }
    }
}

@Composable
fun FilterChip(text: String, selected: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val c = Prep.colors
    val shape = RoundedCornerShape(Radius.chip)
    Row(
        modifier = modifier
            .minimumInteractiveComponentSize()
            .heightIn(min = 36.dp)
            .clip(shape)
            .then(if (selected) Modifier.background(c.text) else Modifier.border(1.dp, c.line, shape))
            .selectable(selected = selected, role = Role.Tab, onClick = onClick)
            .padding(horizontal = Space.m),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (selected) PrepIcon(PrepIcons.Check, null, c.bg, size = 14.dp)
        Text(text, style = Prep.type.meta.copy(fontWeight = FontWeight(500)), color = if (selected) c.bg else c.text2)
    }
}

@Composable
fun SegmentedChoice(options: List<String>, selected: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier) {
    val c = Prep.colors
    val shape = RoundedCornerShape(Radius.control)
    Row(
        modifier = modifier.fillMaxWidth().height(48.dp).clip(shape).border(1.dp, c.line, shape).padding(4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        options.forEachIndexed { index, label ->
            val on = index == selected
            Box(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxHeight()
                    .clip(RoundedCornerShape(8.dp))
                    .background(if (on) c.text else Color.Transparent)
                    .selectable(selected = on, role = Role.RadioButton, onClick = { onSelect(index) }),
                contentAlignment = Alignment.Center,
            ) {
                Text(label, style = Prep.type.label, color = if (on) c.bg else c.text2)
            }
        }
    }
}

@Composable
fun Tag(text: String, modifier: Modifier = Modifier, color: Color = Prep.colors.text2) {
    Text(
        text,
        style = Prep.type.meta,
        color = color,
        modifier = modifier
            .border(1.dp, color.copy(alpha = 0.4f), RoundedCornerShape(Radius.chip))
            .padding(horizontal = 6.dp, vertical = 1.dp),
    )
}

@Composable
fun PrepToggle(checked: Boolean, onCheckedChange: (Boolean) -> Unit, modifier: Modifier = Modifier) {
    val c = Prep.colors
    val t by animateFloatAsState(if (checked) 1f else 0f, tween(Motion.FADE, easing = Motion.standard), label = "toggle")
    Box(
        modifier = modifier
            .minimumInteractiveComponentSize()
            .size(width = 48.dp, height = 28.dp)
            .clip(CircleShape)
            .background(lerp(c.surface2, c.accentTint, t))
            .border(1.dp, lerp(c.lineStrong, c.accent, t), CircleShape)
            .toggleable(value = checked, role = Role.Switch, onValueChange = onCheckedChange)
            .padding(4.dp),
    ) {
        Box(Modifier.offset(x = 20.dp * t).size(20.dp).clip(CircleShape).background(lerp(c.text3, c.accent, t)))
    }
}

@Composable
fun TextInput(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    minLines: Int = 1,
    singleLine: Boolean = false,
    leading: ImageVector? = null,
) {
    val c = Prep.colors
    var focused by remember { mutableStateOf(false) }
    val shape = RoundedCornerShape(Radius.control)
    BasicTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier.fillMaxWidth().onFocusChanged { focused = it.isFocused },
        textStyle = Prep.type.bodyL.copy(color = c.text),
        cursorBrush = SolidColor(c.accent),
        singleLine = singleLine,
        minLines = minLines,
        decorationBox = { inner ->
            Row(
                modifier = Modifier
                    .clip(shape)
                    .border(if (focused) 1.5.dp else 1.dp, if (focused) c.accent else c.lineStrong, shape)
                    .padding(horizontal = Space.l, vertical = 14.dp),
                verticalAlignment = if (minLines > 1) Alignment.Top else Alignment.CenterVertically,
            ) {
                if (leading != null) {
                    PrepIcon(leading, null, c.text3, size = 20.dp)
                    Spacer(Modifier.width(Space.m))
                }
                Box(Modifier.weight(1f)) {
                    if (value.isEmpty()) Text(placeholder, style = Prep.type.bodyL, color = c.text3)
                    inner()
                }
            }
        },
    )
}

@Composable
fun QuoteBlock(text: String, modifier: Modifier = Modifier) {
    Text(
        "“$text”",
        style = Prep.type.quote,
        color = Prep.colors.text,
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radius.control))
            .background(Prep.colors.surface2)
            .padding(Space.l),
    )
}

@Composable
fun Notice(text: String, modifier: Modifier = Modifier, color: Color = Prep.colors.text2) {
    val shape = RoundedCornerShape(Radius.control)
    Text(
        text,
        style = Prep.type.body,
        color = color,
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(Prep.colors.surface1)
            .border(1.dp, Prep.colors.line, shape)
            .padding(Space.l),
    )
}

@Composable
fun ConfirmDialog(title: String, body: String, confirmLabel: String, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    val c = Prep.colors
    AlertDialog(
        onDismissRequest = onDismiss,
        confirmButton = { QuietButton(confirmLabel, onConfirm, color = c.danger) },
        dismissButton = { QuietButton("Cancel", onDismiss) },
        title = { Text(title, style = Prep.type.titleM, color = c.text) },
        text = { Text(body, style = Prep.type.body, color = c.text2) },
        containerColor = c.surface2,
        shape = RoundedCornerShape(Radius.sheet),
    )
}
