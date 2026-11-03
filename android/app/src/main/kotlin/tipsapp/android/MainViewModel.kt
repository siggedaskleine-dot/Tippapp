package tipsapp.android

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import tipsapp.core.model.SourceReport

data class UiState(
    val loading: Boolean = false,
    val date: String = "",
    val updatedAt: String? = null,
    val matches: List<AnalyzedMatch> = emptyList(),
    val sources: List<SourceReport> = emptyList(),
    val error: String? = null,
    val hasApiKey: Boolean = false,
    val hasAnthropicKey: Boolean = false,
    val aiComments: Map<String, String> = emptyMap(),
    val aiBusy: Set<String> = emptySet(),
    val aiError: String? = null,
    val budget: Int = 300,
)

class MainViewModel(app: Application) : AndroidViewModel(app) {
    private val repo = Repository(app)
    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state

    init {
        viewModelScope.launch {
            val date = repo.today()
            val (cached, hasKey, budget) = withContext(Dispatchers.IO) { Triple(repo.loadCached(date), repo.apiKey.isNotBlank(), repo.callBudget) }
            val (hasAi, ai) = withContext(Dispatchers.IO) { repo.anthropicKey.isNotBlank() to repo.loadAiComments(date) }
            _state.update { it.copy(date = date.toString(), hasApiKey = hasKey, budget = budget, hasAnthropicKey = hasAi, aiComments = ai) }
            if (cached != null) {
                val analyzed = withContext(Dispatchers.Default) { repo.analyze(cached) }
                _state.update { it.copy(matches = analyzed, sources = cached.sources, updatedAt = cached.generatedAt) }
            } else refresh()
        }
    }

    fun refresh() {
        if (_state.value.loading) return
        _state.update { it.copy(loading = true, error = null) }
        viewModelScope.launch {
            try {
                val date = repo.today()
                val day = withContext(Dispatchers.IO) { repo.refresh(date) }
                val analyzed = withContext(Dispatchers.Default) { repo.analyze(day) }
                _state.update { it.copy(loading = false, date = date.toString(), matches = analyzed, sources = day.sources, updatedAt = day.generatedAt) }
                autoAiForTopPicks()
            } catch (e: Exception) {
                _state.update { it.copy(loading = false, error = e.message ?: e.toString()) }
            }
        }
    }

    /** AI-kommentarer skrivs automatiskt för dagens bästa spel (max 10), övriga på begäran. */
    private fun autoAiForTopPicks() {
        val s = _state.value
        if (!s.hasAnthropicKey) return
        topPicks(s.matches).take(10).filter { it.match.id !in s.aiComments }.forEach { requestAi(it) }
    }

    fun requestAi(am: AnalyzedMatch) {
        val id = am.match.id
        if (id in _state.value.aiBusy) return
        _state.update { it.copy(aiBusy = it.aiBusy + id, aiError = null) }
        viewModelScope.launch {
            try {
                val text = withContext(Dispatchers.IO) { repo.writeAiComment(am).also { repo.saveAiComment(repo.today(), id, it) } }
                _state.update { it.copy(aiBusy = it.aiBusy - id, aiComments = it.aiComments + (id to text)) }
            } catch (e: Exception) {
                _state.update { it.copy(aiBusy = it.aiBusy - id, aiError = e.message ?: e.toString()) }
            }
        }
    }

    fun saveSettings(key: String?, budget: Int, anthropicKey: String? = null) {
        viewModelScope.launch(Dispatchers.IO) {
            if (anthropicKey != null) repo.anthropicKey = anthropicKey
            if (key != null) repo.apiKey = key
            repo.callBudget = budget.coerceIn(20, 7000)
            _state.update { it.copy(hasApiKey = repo.apiKey.isNotBlank(), hasAnthropicKey = repo.anthropicKey.isNotBlank(), budget = repo.callBudget) }
        }
    }
}

/** Dagens bästa spel: positivt spelvärde, ej startade, högst poäng först. */
fun topPicks(list: List<AnalyzedMatch>): List<AnalyzedMatch> =
    list.filter { val ev = it.analysis?.pick?.expectedValue; ev != null && ev >= tipsapp.core.analysis.Analyzer.MIN_EDGE && it.match.status == tipsapp.core.model.MatchStatus.SCHEDULED }
        .sortedByDescending { it.analysis!!.score }
