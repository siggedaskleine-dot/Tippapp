# Tipsapp – datagrund (steg 1)

Hämtar dagens matcher med odds, form, tabeller och inbördes möten, och samlar allt i en
gemensam modell (`MatchDay` → `Match`) som analysmotorn (steg 2) och Android-appen (steg 4) bygger på.

## Teknik

- **Kotlin** (JVM 17) med OkHttp och kotlinx.serialization. Modulen `core` är ren Kotlin utan
  serverberoenden, så den kan läggas in direkt i Android-appen. Appen hämtar då själv från
  källorna, och ingen egen server behövs.
- `cli` är ett litet kommandoradsprogram för att köra och testa hämtningen på en dator.

## Källor

| Sport | Liga | Källa | Odds | Form | Tabell | Inbördes |
|---|---|---|---|---|---|---|
| Fotboll | alla ligor | api-football v3 (din Pro-nyckel) | ja | ja | ja | ja |
| Hockey | NHL | NHL:s öppna API, api-web.nhle.com | ja, partner-odds (bästa försök) | ja | ja | ja (2 säsonger) |
| Hockey | SHL | shl.se:s publika API (`/api/sports-v2`, `/api/statistics-v2`) | nej | ja | ja | ja (innevarande säsong) |
| Hockey | Hockeyallsvenskan | Kambi/Unibets öppna oddsflöde | ja | nej | nej | nej |
| Hockey | odds SHL/NHL | Kambi/Unibets öppna oddsflöde | ja (1X2, vinnare inkl. övertid, över/under) | – | – | – |
| Fotboll | vad andra spelar på | Svenska Spel (Stryk-, Europa-, Topptipset) | Svenska folkets streck + tio tidningars tips | – | – | – |

### api-football och kvoten
En hämtning gör: 1 anrop `/fixtures?date=`, N anrop `/odds?date=&page=` (hela dagens odds), 1 anrop
`/standings` per liga och 1 anrop `/predictions` per match (ger form, inbördes möten och
api-footballs egen prognos). Matcher prioriteras i ordningen *har odds → prioriterad liga →
tidigast avspark* tills budgeten (`--budget`, standard 2 500 av 7 500/dygn) är slut. Allt cachas
(tabeller och predictions i 6 h), så en andra hämtning samma dag kostar nästan inget.
Kvar-kvoten läses från svarshuvudet och visas i rapporten.

### Hockeyallsvenskan
hockeyallsvenskan.se har inget öppet API, så matcher och odds tas från Kambis oddsflöde
(`HockeyAllsvenskanProvider`). Form och tabell saknas för den ligan.

### Vad andra spelar på
`MatchEnricher` lägger data på redan hämtade matcher. `SvenskaSpelFolket` hämtar Svenska folkets
streckfördelning och tio tidningars tips från Svenska Spels kuponger och kopplar dem till rätt
match via lagnamn och starttid (`TeamMatcher`). `KambiHockeyOdds` lägger på hockeyodds.

### AI-kommentarer
`AiCommentWriter` skriver motiveringen med Claude (Anthropic Java SDK) när en Anthropic-nyckel
finns i appens inställningar. Dagens bästa spel får AI-text automatiskt, övriga matcher på
begäran. Utan nyckel används den inbyggda mallen.

## API-nyckeln
Nyckeln committas aldrig. Ange den på något av dessa sätt:

```bash
export APIFOOTBALL_KEY=din-nyckel
# eller skapa secrets.properties (ignoreras av git):
echo "apifootball.key=din-nyckel" > secrets.properties
```

I Android-appen matas den in på en inställningssida och sparas krypterat på telefonen.

## Köra

```bash
./gradlew :cli:run --args="--date 2026-11-03 --out dagens.json"
./gradlew :cli:run --args="--sources nhl,shl"        # bara hockey, ingen nyckel behövs
./gradlew :cli:run --args="--budget 1000"            # färre api-football-anrop
./gradlew :core:test                                 # tester mot låtsasserver
```

Resultatet blir en JSON-fil med alla matcher och en rapport per källa (antal matcher, anrop, fel).

## Android-appen

Ligger i `android/` och använder `core` direkt. Varje push till `main` bygger en ny APK via GitHub
Actions och lägger den under Releases som **senaste** (`dagens-tips.apk`).

I appen: lägg in api-football-nyckeln under **Inställningar** (sparas krypterat på telefonen),
tryck på uppdatera. Flikarna visar dagens bästa spel, all fotboll och all hockey med spelförslag,
odds, spelvärde, säkerhet (1–5) och en motivering under varje match.

Bygga lokalt (kräver Android SDK): `./gradlew -p android :app:assembleRelease`

## Analysmotorn

`tipsapp.core.analysis.Analyzer` väger ihop marknadens marginalfria sannolikheter (snitt över
bookmakers), en Poisson-modell från lagens mål för/emot (tabell + senaste 5) och api-footballs
prognos. Varje utfall jämförs med bästa odds; spelet med högst förväntat värde (och minst 30 %
chans) blir förslaget. Utan odds visas det mest sannolika utfallet. `Commentary` skriver
motiveringen på svenska.
