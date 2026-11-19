# Wortwolke live – Anleitung (v1.4)

Dieser Ordner enthält alles für die Runde "Was ist dein Highlight 2026?".

| Datei | Wofür |
|---|---|
| `Invent-Dataport_Teilnehmende_v1.4.html` | Seite für Teilnehmende: Frage, Eingabefeld, Senden |
| `Invent-Dataport_Moderator_v1.4.html` | Seite für dich: Live-Wortwolke, Wortliste, Steuerung |
| `server.ps1` | Kleiner Server. Er nimmt die Wörter an und liefert beide Seiten aus. |
| `build.ps1` und Quelldateien | Baut die beiden HTML-Dateien neu |

## Start in drei Schritten
1. Lege die beiden HTML-Dateien und `server.ps1` in denselben Ordner.
2. Starte den Server (Windows PowerShell):
   ```
   powershell -ExecutionPolicy Bypass -File server.ps1 -Network
   ```
   `-Network` macht den Server für andere Geräte erreichbar. Dafür PowerShell **als Administrator** starten. Ohne `-Network` läuft er nur auf deinem Rechner (gut zum Testen).
3. Der Server zeigt die **PIN** und zwei Links an:
   - Teilnehmende öffnen `http://<Adresse>:8765/` (Link oder QR-Code auf die Folie legen).
   - Du öffnest `http://<Adresse>:8765/moderator` und gibst die PIN ein.

Eine eigene PIN oder einen anderen Port setzt du mit `-Pin 4711 -Port 9000`.

## Was du als Moderator kannst
Neue Wörter fliegen live in die Wolke, jeweils mit einem Sternchen. Du kannst Wörter entfernen (×), selbst Wörter hinzufügen, die Eingabe schließen oder öffnen, neu starten, den Demo-Modus nutzen, Vollbild und große Schrift schalten und die Wolke drucken. Tasten: `P` große Schrift, `F` Vollbild, `L` Liste ein/aus, `D` Demo, `T` Farbschema.

## Grenzen und Schutz
- Alle Wörter liegen **nur im Arbeitsspeicher** des Servers. Nach Strg+C oder "Neu starten" sind sie weg. Es wird nichts auf die Festplatte geschrieben und nichts protokolliert außer der Anzahl.
- Jedes Gerät darf höchstens 5 Highlights senden, und höchstens 10 pro Minute. Es gibt maximal 150 verschiedene Wörter, je 40 Zeichen.
- Die PIN schützt Lesen, Entfernen, Neustart und Schließen. Teilnehmende können nur Wörter senden.
- Eingaben werden bereinigt (`<`, `>` und Steuerzeichen fallen weg) und nur als Text angezeigt.
- **Der Betrieb nutzt `http`, nicht `https`.** Das ist für ein geschlossenes WLAN im Raum in Ordnung, nicht für das offene Internet.
- Firmen- und Gäste-WLANs verbieten oft die Verbindung zwischen Geräten. Wenn Handys den Link nicht öffnen können, braucht ihr ein Netz ohne diese Sperre oder einen Server, den die IT bereitstellt.

## Für die IT: eigener Server
Statt `server.ps1` kann jeder Server die Schnittstelle bedienen. Die Seiten sprechen nur diese Aufrufe:

| Aufruf | Zweck |
|---|---|
| `GET /` und `GET /moderator` | liefern die zwei HTML-Dateien |
| `GET /api/status` | `{"open":true}` |
| `POST /api/words` (Body `{"w":"Wort"}` als Text) | Wort hinzufügen. Antwort `200`, `410` wenn geschlossen, `429` bei zu vielen Sendungen |
| `GET /api/words?pin=…&rev=N` | `{"rev":N,"open":true,"words":[{"w":"Wort","n":3}]}`. Ist `rev` unverändert, kommt `{"same":true}` ohne Liste. `401` bei falscher PIN. |
| `POST /api/remove?pin=…&k=wort` | Wort entfernen (`k` = Wort in Kleinbuchstaben) |
| `POST /api/reset?pin=…` | alles löschen |
| `POST /api/open?pin=…&v=1` oder `v=0` | Eingabe öffnen oder schließen |

Liegen die HTML-Dateien nicht auf dem Server selbst, baue sie mit fester Adresse neu:
```
powershell -ExecutionPolicy Bypass -File build.ps1 -ServerUrl https://wortwolke.example.com
```
Der Server muss dann Cross-Origin-Zugriff erlauben (`Access-Control-Allow-Origin`). Die Seiten haben eine Sicherheitsregel (Content-Security-Policy), die nur diese Adresse und die eigene Herkunft zulässt.

## Vor dem Einsatz
- Datenschutz: Teilnehmende senden hier Text an einen Server. Kläre den Hinweistext und den Betrieb mit dem Data Privacy Officer.
- Einmal mit zwei Geräten im echten Netz testen, nicht nur auf dem eigenen Rechner.
