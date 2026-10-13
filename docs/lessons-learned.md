# Lessons Learned — native Ente-Dienste auf macOS

Zwei Stolpersteine haben im produktiven Betrieb mehrere Stunden Debugging gekostet.
Beide sind online kaum dokumentiert — daher ausführlich hier.

## 1. TCC/Full Disk Access blockiert launchd-Agents auf externen Volumes

**Symptom:** Nach dem Umbiegen der Datenpfade auf eine externe/Wechsel-SSD starten
die launchd-Dienste nicht mehr. `launchctl list` zeigt `EX_CONFIG` (Exit-Code 78),
obwohl dieselben Binaries beim manuellen Start im Terminal einwandfrei laufen.

**Ursache:** macOS verweigert Hintergrundprozessen ohne UI (launchd-Agents) per TCC
den Zugriff auf externe/Wechsel-Volumes — selbst wenn das interaktive Terminal (mit
eigener Full-Disk-Access-Freigabe) problemlos draufschreiben kann.

Zwei Teilprobleme, zwei Fixes:

### a) Kind-Prozesse brauchen explizite Full Disk Access-Freigabe

Systemeinstellungen → Datenschutz & Sicherheit → Voller Festplattenzugriff → „+"
→ Pfad per `Cmd+Shift+G` eintippen, für jeden der folgenden Binaries:

- `/opt/homebrew/opt/postgresql@16/bin/postgres`
- `/opt/homebrew/bin/minio`
- `/bin/bash` (Interpreter des Wrapper-Scripts)
- das kompilierte `museum`-Binary selbst

### b) launchd selbst kann NICHT für Full Disk Access freigegeben werden

`launchd` ist ein Systemprozess — er öffnet `StandardOutPath`/`StandardErrorPath`
bereits **vor** dem Spawnen des Kind-Prozesses. Zeigt dieser Pfad auf ein externes
Volume, schlägt bereits das fehl (`EX_CONFIG`, kein einziger Log-Eintrag vom
Kind-Prozess — das macht die Fehlersuche besonders tückisch, weil es aussieht, als
würde der Kind-Prozess selbst nie starten).

**Fix:** Log-Dateien bleiben immer auf der **internen** Platte. Nur die eigentlichen
Datenverzeichnisse (Postgres-Datadir, MinIO-Storage, museum-Arbeitsverzeichnis)
dürfen auf dem externen Volume liegen.

```
Daten (extern):  /Volumes/<SSD>/ente/{postgres,minio,museum}
Logs (intern):   /Users/<you>/ente-logs/
```

---

## 2. S3-Endpoint muss client-erreichbar sein, nicht nur server-lokal

**Symptom:** Nach erfolgreichem Login schlagen alle Foto-Uploads unsichtbar fehl.
Die App zeigt `200 OK` bei `/files/upload-url`, aber der MinIO-Bucket bleibt leer,
der Client versucht es endlos erneut (Retries ohne sichtbaren Fehler).

**Ursache:** `s3.<bucket-key>.endpoint` in `museum.yaml` stand auf `localhost:3200`.
museum baut daraus wortwörtlich die **presigned Upload-URL** und schickt sie an den
Client. Für einen externen Client (z.B. übers Internet oder ein VPN wie Tailscale)
bedeutet `localhost` sich selbst — nicht den Server!

**Fix:** Endpoint auf eine vom Client aus erreichbare Adresse stellen, z.B. die
Tailscale-IP des Servers:

```yaml
s3:
    <bucket-key>:
        endpoint: <server-tailscale-ip>:3200   # NICHT localhost
```

museum neu starten → Uploads funktionieren sofort. (MinIO selbst bindet bereits
korrekt an alle Interfaces inkl. VPN-IP — das war nicht das Problem.)

**Allgemeine Regel für jedes S3-basierte Self-Hosting-Setup:** Jeder Endpoint, der
in einer presigned URL landet, muss vom **Client** aus erreichbar sein — nicht nur
vom Server, der die URL generiert.

---

## Sonstige kleinere Fallstricke

- **Postgres braucht `LANG`/`LC_ALL`** in der launchd-`EnvironmentVariables`-Sektion,
  sonst `FATAL: postmaster became multithreaded during startup`.
- **Port-Konflikte:** Falls bereits ein brew-`postgresql@16`-Dienst auf 5432 läuft,
  die eigene Ente-Instanz auf einem separaten Port (z.B. 5433) mit eigenem Datadir
  betreiben — nicht den bestehenden Dienst anfassen.
- **E-Mail-Verifizierung ohne SMTP:** Der OTP-Code landet im `museum.err.log`
  (nicht `.out.log` — dort stehen nur die Route-Registrierungen beim Start).
- **`mc ls` statt `find`** für verlässliche Bucket-Inhalte direkt nach einem Upload
  — ein direktes Filesystem-`find` auf dem MinIO-Datenverzeichnis kann kurz danach
  noch veraltete/leere Ergebnisse zeigen.
