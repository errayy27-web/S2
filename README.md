# SS OIL Client — S2

Standalone Flutter Android **read-only Kasa** client. It does not access the main SQL Server and does not modify Supabase records.

## Scope

- Supabase email/password login
- Date picker and manual refresh
- Günlük Satış, Satış Grupları, Yakıt Stokları, Güncel Yakıt Fiyatları
- Kasa archive: `ssoil_snapshots.kind=kasa:YYYY-MM-DD`, fallback to `kind=kasa` only if its embedded `date` matches.
- Fuel prices: `ssoil_fuel_daily_prices` by date.
- No invented monetary values; missing values display `Veri yok`.

## Build

Set Codemagic secret/environment variable `SUPABASE_ANON_KEY` to the project's **public anon/publishable key**, not `service_role`. Codemagic uses `codemagic.yaml` to generate the Android scaffold and build the release APK. Do not commit passwords or service-role keys. Flutter SDK is not available in the authoring environment; APK build has not been verified.

## Current limitation

Fuel stock values have no confirmed per-date field in the Kasa snapshot, so the card displays an explanatory message instead of guessing. Access depends on existing Supabase RLS permissions for `ssoil_snapshots` and `ssoil_fuel_daily_prices`. Login currently persists an access token but does not refresh expired tokens; re-login is required after expiry.