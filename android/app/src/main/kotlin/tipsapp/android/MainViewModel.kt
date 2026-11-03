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
            _state.update { it.copy(date = date.toString(), hasApiKey = hasKey, budget = budget) }
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
            } catch (e: Exception) {
                _state.update { it.copy(loading = false, error = e.message ?: e.toString()) }
            }
        }
    }

    fun saveSettings(key: String?, budget: Int) {
        viewModelScope.launch(Dispatchers.IO) {
            if (key != null) repo.apiKey = key
            repo.callBudget = budget.coerceIn(20, 7000)
            _state.update { it.copy(hasApiKey = repo.apiKey.isNotBlank(), budget = repo.callBudget) }
        }
    }
}
