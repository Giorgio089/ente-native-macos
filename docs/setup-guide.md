# Ente Photos nativ auf macOS — Setup-Guide

Getestet auf: Apple Silicon Mac (M1), macOS Tahoe, 8 GB RAM, parallel noch andere
Dienste. Sollte auf jedem Apple-Silicon-Mac mit ausreichend Speicherplatz
funktionieren.

## Warum nativ (statt Docker/OrbStack)

Linux-Container brauchen auf dem Mac immer eine Linux-VM → RAM-Overhead. Bei
knappem RAM (und ggf. parallel laufenden anderen Diensten) ist das oft der
Engpass. Alle drei Ente-Dienste laufen aber **nativ auf macOS/ARM**:

- **PostgreSQL** — nativer Homebrew-Dienst
- **MinIO** — natives ARM-Binary (S3-kompatibler Objektspeicher)
- **museum** — Ente-Server, ein Go-Binary, kompiliert nativ für `darwin/arm64`

→ **Keine VM, kein Docker, kein OrbStack.** Drei `launchd`-Services, die beim Boot
starten und sich selbst neu starten.

> ⚠️ **Einziger Risikopunkt:** `museum` nutzt libsodium über CGO-Bindings, die auf
> manchen Plattformen Build-Zicken machen können. Falls der native Build scheitert
> → siehe [Fallback](#fallback-falls-museum-nativ-nicht-baut). Postgres + MinIO
> laufen in jedem Fall nativ.

---

## 0. Speicher-Layout festlegen

Beispiel-Layout (Pfade nach eigenem Geschmack anpassen):

```
<DATENWURZEL>/ente/
├── postgres/        # PG-Datenverzeichnis
├── minio/           # Objekt-Blobs (die eigentlichen Fotos, verschlüsselt)
├── museum/          # geklontes Ente-Repo + Binary + museum.yaml
└── logs/            # launchd stdout/stderr — siehe Hinweis unten!
```

```bash
mkdir -p <DATENWURZEL>/ente/{postgres,minio,museum,logs}
```

> **Wenn `<DATENWURZEL>` auf einem externen/Wechsel-Volume liegt:** Logs
> unbedingt separat auf der internen Platte halten, nicht auf dem externen
> Volume! Details dazu in [lessons-learned.md](lessons-learned.md).

Falls externe SSD: Disk-Sleep deaktivieren, damit das Volume im Betrieb nicht
unmountet:
```bash
sudo pmset -a disksleep 0
```

---

## 1. Abhängigkeiten (Homebrew)

```bash
brew install go libsodium pkg-config postgresql@16 minio minio-mc
```

- `postgresql@16` — **nicht** als brew-Service starten, wir nutzen ein eigenes
  Datadir + launchd (siehe Abschnitt 2). Falls bereits ein anderer
  postgresql@16-Dienst auf Port 5432 läuft, eigene Instanz auf einem anderen
  Port (z.B. 5433) betreiben, um Konflikte zu vermeiden.

---

## 2. PostgreSQL nativ

Eigenes Datenverzeichnis initialisieren:

```bash
export PGDATA=<DATENWURZEL>/ente/postgres
/opt/homebrew/opt/postgresql@16/bin/initdb -D "$PGDATA" -U postgres

# einmalig manuell starten, um DB + User anzulegen:
/opt/homebrew/opt/postgresql@16/bin/pg_ctl -D "$PGDATA" -l "$PGDATA/pg.log" -o "-p 5433" start

/opt/homebrew/opt/postgresql@16/bin/createdb -U postgres -p 5433 ente_db
/opt/homebrew/opt/postgresql@16/bin/psql -U postgres -p 5433 -c \
  "ALTER USER postgres WITH PASSWORD 'CHANGE_ME_pg';"
```

Später übernimmt `launchd` den Start (Abschnitt 6).

---

## 3. MinIO nativ

```bash
export MINIO_ROOT_USER=ente
export MINIO_ROOT_PASSWORD=CHANGE_ME_minio
minio server <DATENWURZEL>/ente/minio --address ":3200" --console-address ":3201"
```

In einem zweiten Terminal Bucket anlegen:
```bash
mc alias set local http://localhost:3200 ente CHANGE_ME_minio
mc mb local/ente-photos
```

- **API-Endpoint:** `http://localhost:3200`
- **Web-Console:** `http://localhost:3201`

---

## 4. museum bauen (nativ)

```bash
cd <DATENWURZEL>/ente/museum
git clone https://github.com/ente-io/ente .
cd server

export PKG_CONFIG_PATH="$(brew --prefix libsodium)/lib/pkgconfig"
export CGO_ENABLED=1

go mod tidy
go build -o museum cmd/museum/main.go
```

Wenn `./museum` ohne Fehler baut → nativer Build funktioniert. Sonst →
[Fallback](#fallback-falls-museum-nativ-nicht-baut).

### Config

```bash
cp config/example.yaml ./museum.yaml
go run tools/gen-random-keys/main.go   # JWT/Encryption-Keys generieren
```

Siehe [`config-templates/museum.yaml.example`](../config-templates/museum.yaml.example)
für ein vollständiges, kommentiertes Beispiel inkl. der wichtigsten Stolperstein-
Hinweise (S3-Endpoint, admin-User-ID etc.).

Start/Test:
```bash
./museum   # lauscht auf http://localhost:8080
curl http://localhost:8080/ping   # -> pong
```

---

## 5. Client-Konfiguration (Desktop-App / Mobile / Web)

Ente-Clients müssen statt `api.ente.io` auf den eigenen Server zeigen:

- **Desktop-App:** beim Login-Screen mehrfach auf Version/Logo tippen →
  „Developer settings" → Custom Endpoint: `http://<server-ip>:8080`
- **Mobile:** identisch, Custom-Endpoint-Feld im Login-Screen.

> Für Remote-Zugriff ohne Port-Forwarding bietet sich ein Mesh-VPN wie
> [Tailscale](https://tailscale.com) an: Custom-Endpoint = Tailscale-IP/Hostname
> des Servers.

---

## 6. Autostart via launchd

Drei Plist-Templates liegen in [`launchd/`](../launchd/). Kopieren, Platzhalter
(`/PATH/TO/...`, Credentials) füllen, dann nach `~/Library/LaunchAgents/` legen:

```bash
cp launchd/home.ente.postgres.plist.template ~/Library/LaunchAgents/home.ente.postgres.plist
cp launchd/home.ente.minio.plist.template    ~/Library/LaunchAgents/home.ente.minio.plist
cp launchd/home.ente.museum.plist.template   ~/Library/LaunchAgents/home.ente.museum.plist
# Platzhalter in allen 3 Dateien mit echten Pfaden/Credentials ersetzen!

launchctl load -w ~/Library/LaunchAgents/home.ente.postgres.plist
launchctl load -w ~/Library/LaunchAgents/home.ente.minio.plist
launchctl load -w ~/Library/LaunchAgents/home.ente.museum.plist
```

**Startreihenfolge:** Postgres + MinIO müssen vor museum laufen. Der
[`run-museum.sh`](../scripts/run-museum.sh)-Wrapper wartet per `nc` auf beide
Ports, bevor museum startet — verhindert Crash-Loops beim Boot. `KeepAlive`
in den Plists sorgt zusätzlich dafür, dass sich Dienste nach einem Fehlstart
selbst neu starten.

### Ops-Cheatsheet

```bash
# Status
launchctl list | grep home.ente
curl http://localhost:8080/ping

# Einzelnen Dienst neu starten
launchctl kickstart -k gui/$(id -u)/home.ente.museum

# Stoppen (verhindert Auto-Restart, im Gegensatz zu kill)
launchctl unload ~/Library/LaunchAgents/home.ente.museum.plist

# Wieder starten
launchctl load -w ~/Library/LaunchAgents/home.ente.museum.plist

# Logs
tail -f <internal-logs>/museum.out.log
```

---

## 7. Erster Login & Admin-Setup

Ohne konfigurierten SMTP-Server landet der Verifizierungscode im museum-Log statt
per Mail:
```bash
grep -iE "verification code" <internal-logs>/museum.err.log | tail
```

Admin-Rechte / Storage-Quota über das Ente-CLI-Tool (`museum/cli/` im geklonten
Repo):
```bash
cd museum/cli
CGO_ENABLED=1 PKG_CONFIG_PATH="$(brew --prefix libsodium)/lib/pkgconfig" \
  go build -o ente-cli main.go
```

User-ID ermitteln (E-Mail ist verschlüsselt gespeichert):
```sql
SELECT user_id, creation_time FROM users;
```
→ in `museum.yaml` unter `internal.admins` eintragen, museum neu starten, dann:
```bash
ente-cli account add
ente-cli admin update-subscription --user <email> --no-limit True
```

---

## Fallback: falls museum nativ nicht baut

Falls die libsodium-CGO-Bindings streiken: **nicht** alles containerisieren, nur
`museum` in einen Container packen — Postgres + MinIO bleiben nativ:

```bash
docker run -d --name ente-museum --restart unless-stopped \
  -p 8080:8080 \
  -v <PATH>/museum.yaml:/museum.yaml \
  --add-host=host.docker.internal:host-gateway \
  ghcr.io/ente-io/server
```

In `museum.yaml` dann `db.host` und `s3.endpoint` auf `host.docker.internal`
zeigen lassen. Ein leichter Container statt drei — der RAM-Vorteil bleibt
größtenteils erhalten.

---

## Weiterführend

- [lessons-learned.md](lessons-learned.md) — die zwei größten Stolpersteine im
  produktiven Betrieb und wie man sie löst
- Backup-Strategie: `pg_dump` für Postgres (niemals das laufende Datadir
  kopieren), MinIO-Objektverzeichnis separat sichern (z.B. mit restic)
