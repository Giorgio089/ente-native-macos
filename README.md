# ente-native-macos

Anleitung + Betriebs-Tooling, um **[Ente Photos](https://github.com/ente-io/ente)**
(Self-hosted Photo-Backup) **nativ auf macOS** zu betreiben — **ohne Docker, ohne
Linux-VM, ohne OrbStack**.

## Warum

Auf ressourcenbeschränkten Mac-Homeservern (z.B. ein altes MacBook Air mit 8 GB RAM,
das parallel noch andere Dienste wie Jellyfin stemmen muss) kostet jeder Docker-
Container über die eingebettete Linux-VM spürbaren RAM-Overhead. Ente besteht aber
aus genau drei Komponenten, die sich alle **nativ für `darwin/arm64` kompilieren und
betreiben** lassen:

- **PostgreSQL** — nativer Homebrew-Dienst
- **MinIO** — natives ARM-Binary (S3-kompatibler Objektspeicher)
- **museum** — der eigentliche Ente-Server, ein Go-Binary

→ Drei schlanke `launchd`-Agents statt einer VM. Das spart im produktiven Betrieb
spürbar RAM gegenüber einem Docker-Compose-Setup.

## Was dieses Repo enthält

Dies ist **kein Fork von Ente** — der Ente-Server-Code selbst bleibt unverändert und
lebt im offiziellen [ente-io/ente](https://github.com/ente-io/ente) Repository
(AGPL-3.0). Hier findest du stattdessen die **Betriebsumgebung drumherum**:

```
docs/
  setup-guide.md       ausführliche Schritt-für-Schritt-Anleitung
  lessons-learned.md   Stolpersteine & Fixes aus dem produktiven Betrieb
launchd/
  home.ente.postgres.plist.template
  home.ente.minio.plist.template
  home.ente.museum.plist.template
scripts/
  run-museum.sh         launchd-Wrapper: wartet auf Postgres+MinIO, startet museum
config-templates/
  museum.yaml.example
  credentials.env.example
```

## Quickstart

1. `docs/setup-guide.md` lesen und durchgehen (Homebrew-Deps, PG/MinIO/museum bauen)
2. Templates aus `config-templates/` kopieren, Platzhalter mit eigenen Werten/Secrets
   füllen (niemals committen!)
3. Plists aus `launchd/` nach `~/Library/LaunchAgents/` kopieren, Platzhalter ersetzen
4. `scripts/run-museum.sh` als Wrapper für den museum-Dienst nutzen
5. `launchctl load -w ~/Library/LaunchAgents/home.ente.*.plist`

Details, insbesondere die zwei größten Stolpersteine (TCC/Full-Disk-Access für
launchd-Agents bei externen Volumes, und warum der S3-Endpoint in `museum.yaml`
**client-erreichbar** sein muss, nicht nur server-lokal) stehen in
`docs/lessons-learned.md`.

## Lizenz

Die Inhalte dieses Repos (Doku, Scripts, Plist-Templates) stehen unter der
[MIT-Lizenz](LICENSE) — mach damit, was du willst. Der Ente-Server selbst
(`ente-io/ente`) ist separat unter AGPL-3.0 lizenziert; das Original-Repo einfach
klonen, siehe `docs/setup-guide.md`.

## Kein offizielles Ente-Projekt

Dieses Repo steht in keiner Verbindung zu Ente Labs. Für Fragen zu Ente selbst siehe
die [offizielle Doku](https://ente.io) und das
[Original-Repository](https://github.com/ente-io/ente).
