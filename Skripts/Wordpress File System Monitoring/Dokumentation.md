## Zweck

Das Skript prüft, ob im Webverzeichnis (`~/public_html`) neue Google-Verifizierungsdateien aufgetaucht sind. Solche Dateien heissen z.B. `google1a2b3c4d5e6f7a8b.html`. Findet es eine, schickt es eine Alarm-Mail.

Hintergrund ist ein früherer Sicherheitsvorfall: Taucht eine neue Datei dieser Art auf, hat ein Angreifer womöglich wieder Schreibzugriff auf den Server (siehe `README-sicherheitsvorfall-2026-10.md`, Abschnitt 6).

## Ablauf

1. Es sucht alle Dateien im Muster `google` + 16 Hex-Zeichen + `.html` unter `~/public_html`.
2. Es vergleicht das Ergebnis mit einer gespeicherten Liste bekannter Dateien (`~/.gsv-monitor/known.txt`).
3. **Keine neuen Dateien:** Es schreibt die Liste neu und beendet sich ohne Meldung.
4. **Neue Dateien gefunden:** Es schickt per `sendmail` eine Mail an `elio.schmutz@humanlayer.de`. Für jede neue Datei stehen darin:
   - Pfad und Änderungsdatum
   - die ersten 200 Zeichen des Inhalts
   - der Inhalt des Ordners, in dem die Datei liegt
5. Die Liste bekannter Dateien wird erst aktualisiert, wenn die Mail verschickt wurde. Scheitert der Versand, kommt der Alarm beim nächsten Lauf also nochmals.

Bei jedem Lauf schreibt das Skript ausserdem Datum und Uhrzeit in `~/.gsv-monitor/last_run`. Daran sieht man, ob es überhaupt regelmässig läuft.

## Verwendung

```bash
./gsv-monitor.sh --init   # Aktuellen Stand als Ausgangsliste speichern
./gsv-monitor.sh          # Normale Prüfung
```

`--init` braucht es einmalig beim Einrichten und danach immer dann, wenn eine neu gefundene Datei legitim ist.

Die normale Prüfung ist für einen regelmässigen Cronjob gedacht, z.B. alle 15 Minuten:

```cron
*/15 * * * * /pfad/zu/gsv-monitor.sh
```

## Voraussetzungen

- Linux: Das Skript verwendet GNU-Varianten von `find`, `stat` und `ls` und funktioniert deshalb nicht unter macOS.
- Ein funktionierendes `/usr/sbin/sendmail`

[[gsv-monitor.sh]]