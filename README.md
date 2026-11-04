# Fotbollstips

Android-app som listar dagens, morgondagens och övermorgondagens matcher i alla ligor med ett tips (1X2, Över 2.5 eller Båda lagen gör mål) med odds mellan 1.70 och 2.10. Data från api-football.com.

- `packages/tips_engine` – datamotor och tipsmodell (ren Dart, se dess README).
- `lib/` – Flutter-appen: matchkort, dagflikar, sortering på tid, odds, form och sannolikhet, sök och filter.
- API-nyckeln skrivs in i appen första gången och sparas bara på telefonen. Den finns inte i koden eller APK:n.
- Varje push till grenen `fotbollstips` bygger en APK via GitHub Actions och publicerar den som release.
- Förhandsgranska gränssnittet med påhittad data: `flutter run -d chrome --dart-define=DEMO=true`.
