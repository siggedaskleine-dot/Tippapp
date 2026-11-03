package tipsapp.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import tipsapp.core.model.MatchStatus
import tipsapp.core.model.Sport
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

class MainActivity : ComponentActivity() {
    private val vm: MainViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            val scheme = if (isSystemInDarkTheme()) darkColorScheme(primary = Color(0xFF4CC38A)) else lightColorScheme(primary = Color(0xFF0B6E4F))
            MaterialTheme(colorScheme = scheme) {
                Surface(Modifier.fillMaxSize()) { App(vm) }
            }
        }
    }
}

private enum class Screen(val title: String) { TOP("Bästa spel"), FOOTBALL("Fotboll"), HOCKEY("Hockey"), SETTINGS("Inställningar") }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun App(vm: MainViewModel) {
    val state by vm.state.collectAsStateWithLifecycle()
    var tab by rememberSaveable { mutableStateOf(Screen.TOP) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text("Dagens tips", fontWeight = FontWeight.Bold)
                        Text(
                            state.updatedAt?.let { "Uppdaterad ${fmtTime(it)}" } ?: state.date,
                            style = MaterialTheme.typography.labelSmall,
                        )
                    }
                },
                actions = {
                    if (state.loading) CircularProgressIndicator(Modifier.size(24.dp).padding(end = 4.dp), strokeWidth = 2.dp)
                    else IconButton(onClick = vm::refresh) { Icon(Icons.Filled.Refresh, contentDescription = "Uppdatera") }
                },
            )
        },
    ) { pad ->
        Column(Modifier.padding(pad).fillMaxSize()) {
            ScrollableTabRow(selectedTabIndex = tab.ordinal, edgePadding = 8.dp) {
                Screen.entries.forEach { t -> Tab(selected = tab == t, onClick = { tab = t }, text = { Text(t.title) }) }
            }
            state.error?.let { Text("Fel: $it", color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(12.dp)) }
            state.aiError?.let { Text("AI: $it", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(horizontal = 12.dp)) }
            if (!state.hasApiKey && tab != Screen.SETTINGS) {
                Text(
                    "Lägg in din api-football-nyckel under Inställningar för att få fotbollen. Hockeyn fungerar utan nyckel.",
                    style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(12.dp),
                )
            }
            when (tab) {
                Screen.TOP -> TopList(state, vm)
                Screen.FOOTBALL -> MatchList(state.matches.filter { it.match.sport == Sport.FOOTBALL }, state, vm)
                Screen.HOCKEY -> MatchList(state.matches.filter { it.match.sport == Sport.HOCKEY }, state, vm)
                Screen.SETTINGS -> Settings(state, vm)
            }
        }
    }
}

@Composable
private fun TopList(state: UiState, vm: MainViewModel) {
    val top = remember(state.matches) { topPicks(state.matches).take(15) }
    if (top.isEmpty()) {
        Empty(if (state.loading) "Hämtar dagens matcher …" else "Inga spel med tydligt värde hittades ännu. Tryck på uppdatera.")
        return
    }
    LazyColumn(contentPadding = PaddingValues(12.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        items(top, key = { it.match.id }) { MatchCard(it, state, vm, expandedByDefault = true) }
    }
}

@Composable
private fun MatchList(list: List<AnalyzedMatch>, state: UiState, vm: MainViewModel) {
    if (list.isEmpty()) { Empty(if (state.loading) "Hämtar …" else "Inga matcher idag."); return }
    val grouped = remember(list) { list.groupBy { "${it.match.league.country?.let { c -> "$c · " } ?: ""}${it.match.league.name}" }.toSortedMap() }
    LazyColumn(contentPadding = PaddingValues(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        grouped.forEach { (league, ms) ->
            item(key = "h:$league") { Text(league, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(top = 8.dp)) }
            items(ms, key = { it.match.id }) { MatchCard(it, state, vm, expandedByDefault = false) }
        }
    }
}

@Composable
private fun MatchCard(am: AnalyzedMatch, state: UiState, vm: MainViewModel, expandedByDefault: Boolean) {
    val m = am.match; val a = am.analysis
    var expanded by remember { mutableStateOf(expandedByDefault) }
    val ai = state.aiComments[m.id]
    ElevatedCard(Modifier.fillMaxWidth().clickable { expanded = !expanded }) {
        Column(Modifier.padding(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(fmtTime(m.kickoff), style = MaterialTheme.typography.labelMedium, modifier = Modifier.width(48.dp))
                Text("${m.home.name} – ${m.away.name}", fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                if (m.homeGoals != null && m.status != MatchStatus.SCHEDULED) Text("${m.homeGoals}–${m.awayGoals}", fontWeight = FontWeight.Bold)
            }
            if (expandedByDefault) Text(m.league.name, style = MaterialTheme.typography.labelSmall)
            if (a != null) {
                Spacer(Modifier.height(6.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        a.pick.selection + (a.pick.odds?.let { " @ ${"%.2f".format(Locale.US, it)}" } ?: ""),
                        color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f),
                    )
                    a.pick.expectedValue?.let { ev ->
                        Text("${if (ev >= 0) "+" else ""}${(ev * 100).toInt()} %", color = if (ev > 0) Color(0xFF2E9E62) else Color.Gray, style = MaterialTheme.typography.labelMedium)
                    }
                    Spacer(Modifier.width(8.dp))
                    Text("★".repeat(a.confidence) + "☆".repeat(5 - a.confidence), style = MaterialTheme.typography.labelMedium)
                }
                Text(a.pick.market, style = MaterialTheme.typography.labelSmall, color = Color.Gray)
                m.publicBetting.firstOrNull()?.let { pb ->
                    Text(
                        "${pb.source}: " + pb.shares.entries.joinToString("  ") { "${it.key} ${it.value.toInt()} %" },
                        style = MaterialTheme.typography.labelSmall,
                    )
                }
                if (expanded) {
                    Spacer(Modifier.height(6.dp))
                    if (ai != null) {
                        Text("AI-kommentar", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                        Text(ai, style = MaterialTheme.typography.bodySmall)
                        Spacer(Modifier.height(4.dp))
                        Text(a.comment, style = MaterialTheme.typography.labelSmall, color = Color.Gray)
                    } else {
                        Text(a.comment, style = MaterialTheme.typography.bodySmall)
                        if (state.hasAnthropicKey) {
                            if (m.id in state.aiBusy) Text("AI skriver …", style = MaterialTheme.typography.labelSmall)
                            else TextButton(onClick = { vm.requestAi(am) }) { Text("Skriv AI-kommentar") }
                        }
                    }
                }
            } else if (expanded) {
                Text("Ingen analys (för lite data eller matchen är spelad).", style = MaterialTheme.typography.bodySmall, color = Color.Gray)
            }
        }
    }
}

@Composable
private fun Settings(state: UiState, vm: MainViewModel) {
    var key by remember { mutableStateOf("") }
    var aiKey by remember { mutableStateOf("") }
    var budget by remember(state.budget) { mutableStateOf(state.budget.toString()) }
    var saved by remember { mutableStateOf(false) }
    LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item {
            Text("api-football-nyckel", style = MaterialTheme.typography.titleSmall)
            Text(if (state.hasApiKey) "En nyckel är sparad (krypterat på telefonen). Fyll i en ny för att byta." else "Ingen nyckel sparad.", style = MaterialTheme.typography.bodySmall)
            OutlinedTextField(key, { key = it; saved = false }, label = { Text("Nyckel") }, singleLine = true,
                visualTransformation = PasswordVisualTransformation(), modifier = Modifier.fillMaxWidth())
        }
        item {
            Text("Anthropic-nyckel för AI-kommentarer (valfri)", style = MaterialTheme.typography.titleSmall)
            Text(
                if (state.hasAnthropicKey) "En nyckel är sparad. AI skriver kommentarer till dagens bästa spel, och till andra matcher när du trycker." else "Utan nyckel skriver appen kommentarerna själv. Nyckel skapas på console.anthropic.com.",
                style = MaterialTheme.typography.bodySmall,
            )
            OutlinedTextField(aiKey, { aiKey = it; saved = false }, label = { Text("sk-ant-…") }, singleLine = true,
                visualTransformation = PasswordVisualTransformation(), modifier = Modifier.fillMaxWidth())
        }
        item {
            Text("Max anrop per uppdatering", style = MaterialTheme.typography.titleSmall)
            Text("Pro-planen ger 7 500 anrop per dygn. 300 tar ungefär en minut och täcker matcherna med odds i de viktigaste ligorna. Svaren sparas, så nästa uppdatering samma dag blir billigare.", style = MaterialTheme.typography.bodySmall)
            OutlinedTextField(budget, { budget = it.filter(Char::isDigit); saved = false }, singleLine = true,
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), modifier = Modifier.fillMaxWidth())
        }
        item {
            Button(onClick = {
                vm.saveSettings(key.takeIf { it.isNotBlank() }, budget.toIntOrNull() ?: 300, aiKey.takeIf { it.isNotBlank() })
                key = ""; aiKey = ""
                saved = true
            }) { Text("Spara") }
            if (saved) Text("Sparat. Tryck på uppdatera uppe till höger.", style = MaterialTheme.typography.bodySmall)
        }
        item {
            Text("Källor vid senaste hämtningen", style = MaterialTheme.typography.titleSmall)
            if (state.sources.isEmpty()) Text("Ingen hämtning ännu.", style = MaterialTheme.typography.bodySmall)
            state.sources.forEach { s ->
                Text("${if (s.ok) "✓" else "✗"} ${s.source}: ${s.matches} matcher, ${s.apiCallsUsed} anrop${s.message?.let { "\n   $it" } ?: ""}", style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

@Composable
private fun Empty(text: String) {
    Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) { Text(text, color = Color.Gray) }
}

private val hhmm = DateTimeFormatter.ofPattern("HH:mm")
private fun fmtTime(iso: String): String = runCatching {
    OffsetDateTime.parse(iso).atZoneSameInstant(ZoneId.of("Europe/Stockholm")).format(hhmm)
}.getOrDefault("")
