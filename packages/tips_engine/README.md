# tips_engine

Datamotor och tipsmodell för fotbollsappen (steg 1). Ren Dart, läggs in i Flutter-appen i steg 2.

## Köra
```
dart pub get
dart test
API_FOOTBALL_KEY=din-nyckel dart run bin/tips.dart 0 sannolikhet   # 0=idag 1=imorgon 2=övermorgon
```
Nyckeln läses från miljön (CLI) eller skickas in i `ApiFootballClient` (i appen via `--dart-define`). Den ligger aldrig i koden.

## Flöde per dag
1. `/fixtures?date=` – alla matcher i alla ligor (1 anrop).
2. `/odds?date=&bookmaker=8` – Bet365-odds för 1X2, Över 2.5 och BLGM (sidindelat, sidorna hämtas parallellt).
3. `/fixtures?league=&season=` – hela säsongen per liga (1 anrop/liga). Ger PPG, form, Ö2.5- och BLGM-frekvens hemma/borta. Har ligan under 40 spelade matcher tas förra säsongen med.
4. `/fixtures?ids=` – matchstatistik för lagens 6 senaste matcher, 20 per anrop, för xG/xGA. Saknar ligan xG noteras det i 7 dagar och modellen kör på mål och PPG.

Cachetider: dagens matcher 20 min, kommande 3 h, odds 2 h, ligahistorik 12 h, färdigspelad statistik 60 dagar. xG-hämtning pausas om färre än 500 anrop återstår idag.

## Modell
- Målförväntan (Poisson med Dixon–Coles): anfall/försvar hemma resp. borta, krympt mot ligasnittet när underlaget är litet. xG/xGA vävs in med upp till 50 % vikt.
- 1X2 = 60 % Poisson + 40 % PPG-modell (hemma-PPG hemma mot borta-PPG borta).
- Över 2.5 och BLGM = 55 % Poisson + 45 % lagens faktiska frekvens.
- Tipsval: bland 1, X, 2, Ö2.5, BLGM med odds 1.70–2.10 vinner bäst spelvärde med avdrag för avstånd till 1.90. Annars närmast 1.90, och tipset markeras som utanför fönstret (appen döljer det som standard). Utan odds används modellodds (1/p).
- Varje tips får betyg: Spelvärde, Rimligt, Svagt eller Inga odds, plus en kommentar på svenska.

Vikterna finns i `ModelWeights` och `TipSelector`.
