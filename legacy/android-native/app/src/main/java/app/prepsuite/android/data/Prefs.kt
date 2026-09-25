package app.prepsuite.android.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.prepStore: DataStore<Preferences> by preferencesDataStore(name = "prep")

class Prefs(private val context: Context) {
    private val onboardedKey = booleanPreferencesKey("onboarded")
    private val quietKey = booleanPreferencesKey("quiet_mode")
    private val roleKey = stringPreferencesKey("role")
    private val lengthKey = intPreferencesKey("session_length")
    private val notesKey = stringPreferencesKey("experience_notes")

    val onboarded: Flow<Boolean> = context.prepStore.data.map { it[onboardedKey] ?: false }
    val quietMode: Flow<Boolean> = context.prepStore.data.map { it[quietKey] ?: false }
    val role: Flow<RolePack> = context.prepStore.data.map { p -> RolePack.entries.firstOrNull { it.name == p[roleKey] } ?: RolePack.General }
    val experienceNotes: Flow<String?> = context.prepStore.data.map { it[notesKey] }
    val sessionLength: Flow<Int> = context.prepStore.data.map { it[lengthKey] ?: 1 }

    suspend fun completeOnboarding(role: RolePack, notes: String) {
        context.prepStore.edit {
            it[roleKey] = role.name
            it[notesKey] = notes
            it[onboardedKey] = true
        }
    }

    suspend fun setExperienceNotes(value: String) {
        context.prepStore.edit { it[notesKey] = value }
    }

    suspend fun setOnboarded(value: Boolean) {
        context.prepStore.edit { it[onboardedKey] = value }
    }

    suspend fun setQuietMode(value: Boolean) {
        context.prepStore.edit { it[quietKey] = value }
    }

    suspend fun setRole(value: RolePack) {
        context.prepStore.edit { it[roleKey] = value.name }
    }

    suspend fun setSessionLength(value: Int) {
        context.prepStore.edit { it[lengthKey] = value }
    }
}
