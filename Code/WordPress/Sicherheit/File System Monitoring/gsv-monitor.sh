#!/bin/bash
set -u

RECIPIENT="elio.schmutz@humanlayer.de"
SCAN_DIR="$HOME/public_html"
STATE_DIR="$HOME/.gsv-monitor"
KNOWN="$STATE_DIR/known.txt"
SENDMAIL="/usr/sbin/sendmail"

mkdir -p "$STATE_DIR"
touch "$KNOWN"
date '+%F %T' > "$STATE_DIR/last_run"

find_files() {
  find "$SCAN_DIR" -type f -regextype posix-extended \
    -regex '.*/google[0-9a-f]{16}\.html' 2>/dev/null | sort
}

if [ "${1:-}" = "--init" ]; then
  find_files > "$KNOWN"
  echo "Baseline gespeichert ($(wc -l < "$KNOWN") Dateien):"
  cat "$KNOWN"
  exit 0
fi

CURRENT=$(find_files)
NEW=$(comm -13 "$KNOWN" <(echo "$CURRENT" | sed '/^$/d'))
if [ -z "$NEW" ]; then
  echo "$CURRENT" | sed '/^$/d' > "$KNOWN"
  exit 0
fi

HOST=$(hostname)
{
  echo "To: $RECIPIENT"
  echo "Subject: [ALARM] Neue Google-Verifizierungsdatei auf $HOST"
  echo "Content-Type: text/plain; charset=UTF-8"
  echo
  echo "Auf $HOST wurden neue Google-Verifizierungsdateien gefunden:"
  echo
  while IFS= read -r f; do
    echo "Datei:   $f"
    echo "Erstellt: $(stat -c '%y' "$f" 2>/dev/null)"
    echo "Inhalt:  $(head -c 200 "$f" 2>/dev/null)"
    echo "Weitere Dateien im selben Ordner:"
    ls -la --time-style=long-iso "$(dirname "$f")" 2>/dev/null | sed 's/^/  /'
    echo
  done <<< "$NEW"
  echo "Moeglicherweise hat der Angreifer wieder Schreibzugriff auf den Server."
  echo "Siehe README-sicherheitsvorfall-2026-10.md, Abschnitt 6."
  echo
  echo "Ist die Datei legitim, Baseline aktualisieren mit: $0 --init"
} | "$SENDMAIL" -t && echo "$CURRENT" | sed '/^$/d' > "$KNOWN"
