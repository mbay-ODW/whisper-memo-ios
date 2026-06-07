# Whisper Memo — iOS App

Native iOS-App für Baustellenbegehungen. Einmal tippen, diktieren, loslaufen — der Text wartet auf dem Handy wenn du wieder WLAN hast.

Kommuniziert direkt mit dem selbst gehosteten [Whisper Transkriptionsdienst](https://github.com/mbay-ODW/whisper-service), authentifiziert via Authelia OIDC.

---

## Features

- **Tap-to-Record** — ein Tipp startet die Aufnahme, nächster Tipp stoppt und lädt hoch
- **Offline-Queue** — kein WLAN? Aufnahme wird gespeichert und automatisch hochgeladen sobald Verbindung da ist
- **Authelia OIDC Login** — Authorization Code + PKCE, Refresh-Token wird im Keychain gespeichert (90 Tage gültig)
- **Live-Status** — Polling alle 2 Sekunden solange ein Job läuft
- **Zeitstempel** — aufklappbar pro Segment
- **Share** — Text kopieren, TXT/SRT/JSON exportieren via iOS Share Sheet
- **Modellauswahl** — large-v3, medium, small, base pro Aufnahme wählbar
- **Editierbarer Prompt** — Fachvokabular direkt in der App anpassbar

---

## Xcode Setup

### Voraussetzungen
- Xcode 15+
- iOS 17+ Deployment Target
- Apple Developer Account (auch kostenloses reicht für persönlichen Gebrauch)

### Projekt anlegen

1. **Xcode → File → New → Project → iOS → App**
   - Product Name: `WhisperMemo`
   - Bundle Identifier: `com.deinname.whispermemo` (beliebig, muss einmalig sein)
   - Interface: SwiftUI
   - Language: Swift

2. **Quelldateien hinzufügen**
   Alle `.swift`-Dateien aus diesem Repo in den Xcode-Navigator ziehen (Drag & Drop), dabei "Copy items if needed" ankreuzen. Ordnerstruktur beibehalten:
   ```
   WhisperMemo/
   ├── WhisperMemoApp.swift
   ├── AppSettings.swift
   ├── JobStore.swift
   ├── Auth/
   │   ├── OIDCManager.swift
   │   └── Keychain.swift
   ├── Audio/
   │   └── AudioRecorder.swift
   ├── Network/
   │   ├── APIClient.swift
   │   └── Models.swift
   ├── Queue/
   │   └── UploadQueue.swift
   └── Views/
       ├── LoginView.swift
       ├── RecordView.swift
       ├── JobListView.swift
       ├── TranscriptView.swift
       └── SettingsView.swift
   ```

3. **Info.plist anpassen**
   In den Xcode-Projekteinstellungen unter **Info → URL Types** einen neuen Eintrag hinzufügen:
   - Identifier: `com.whisper-memo.oauth`
   - URL Schemes: `whispermemo`

   Damit funktioniert der OIDC-Callback nach dem Authelia-Login.

4. **Mikrofon-Permission**
   In **Info → Custom iOS Target Properties** hinzufügen:
   - Key: `NSMicrophoneUsageDescription`
   - Value: `Zum Aufnehmen von Sprachmemos auf der Baustelle`

5. **Background Audio** (optional — Aufnahme mit gesperrtem Bildschirm)
   In **Signing & Capabilities → + Capability → Background Modes → Audio, AirPlay, and Picture in Picture** aktivieren.

6. **Signing**
   Unter **Signing & Capabilities** dein Team auswählen. Mit kostenlosem Account läuft die App 7 Tage auf dem eigenen Gerät.

---

## Erster Start

```
App öffnen
  └─ Einstellungen-Tab
       └─ Server-URL eingeben: https://whisper.bay-ram.de
       └─ "Konfiguration laden" tippen
            └─ App holt OIDC-Issuer automatisch vom Server (/api/config)
  └─ "Mit Authelia anmelden"
       └─ Authelia-Login im Browser (einmalig)
       └─ Token wird im Keychain gespeichert
  └─ Aufnahme-Tab → loslegen
```

---

## Architektur

```
┌─────────────────────────────────────────┐
│              iOS App                    │
│                                         │
│  AVAudioRecorder → m4a (Documents/)     │
│         │                               │
│  UploadQueue (NWPathMonitor)            │
│    • online  → sofort POST /api/transcribe
│    • offline → Datei bleibt lokal,      │
│                bei Reconnect auto-retry │
│         │                               │
│  JobStore (2s Polling wenn aktiv)       │
│    GET /api/jobs/<id>                   │
│         │                               │
│  OIDCManager                            │
│    • Login via ASWebAuthenticationSession
│    • PKCE (S256)                        │
│    • Access Token (1h TTL)              │
│    • Refresh Token (90d, Keychain)      │
└──────────────────┬──────────────────────┘
                   │ HTTPS + Bearer Token
                   ▼
         Traefik → Authelia (Token-Validierung)
                   │ Remote-User Header
                   ▼
              Flask + faster-whisper
```

---

## Authelia OIDC Client

Auf dem Server in der Authelia-Konfiguration eintragen (liegt auch in `authelia-oidc-client.yml` im Server-Repo):

```yaml
identity_providers:
  oidc:
    clients:
      - client_id: 'whisper-ios'
        client_name: 'Whisper Memo iOS'
        public: true
        authorization_policy: 'one_factor'
        redirect_uris:
          - 'whispermemo://oauth/callback'
        scopes: [openid, profile, email]
        grant_types: [authorization_code]
        pkce_challenge_method: 'S256'
        token_endpoint_auth_method: 'none'
        access_token_lifespan: '1h'
        refresh_token_lifespan: '90d'
```

`whispermemo://oauth/callback` muss exakt mit dem URL Scheme in Info.plist übereinstimmen.

---

## Dateistruktur

| Datei | Zweck |
|---|---|
| `WhisperMemoApp.swift` | App-Einstieg, Dependency-Injection, Tab-Navigation |
| `AppSettings.swift` | Persistente Einstellungen via UserDefaults |
| `JobStore.swift` | Job-Liste, Polling-Loop |
| `Auth/OIDCManager.swift` | PKCE-Flow, Token-Refresh, Logout |
| `Auth/Keychain.swift` | Sicheres Token-Speichern via SecItem |
| `Audio/AudioRecorder.swift` | AVAudioRecorder-Wrapper, Pegelanzeige |
| `Network/APIClient.swift` | REST-Client, Auth-Header-Injection |
| `Network/Models.swift` | Job, Segment, ServerConfig |
| `Queue/UploadQueue.swift` | Offline-Queue, NWPathMonitor, Auto-Retry |
| `Views/RecordView.swift` | Hauptscreen: Waveform, Record-Button, Modellwahl |
| `Views/JobListView.swift` | Auftragsliste mit Status-Badges und Fortschrittsbalken |
| `Views/TranscriptView.swift` | Ergebnisanzeige: Text, Zeitstempel, Export |
| `Views/SettingsView.swift` | Server-URL, OIDC-Config, Logout |
| `Views/LoginView.swift` | Authelia-Login-Screen |

---

## Verwandte Projekte

- **[whisper-service](https://github.com/mbay-ODW/whisper-service)** — Server: faster-whisper + Flask + Docker
