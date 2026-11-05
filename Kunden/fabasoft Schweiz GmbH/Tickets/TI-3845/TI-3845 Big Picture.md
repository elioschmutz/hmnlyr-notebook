---
aliases:
  - TI-3845 Big Picture
ticket: "[[TI-3845]]"
erstellt: 2026-11-05
tags:
  - fabasoft
---

# Big Picture: Sitzungs-App-Sync aufteilen

Diese Übersicht beschreibt das Feature «Metadaten- und Dokumentübertragung getrennt, mit Statusanzeige und Einzelwiederholung». Sie ist kein Umsetzungsplan. Beide Seiten sind im Code geprüft, RIS und `../grimlock`.

Ticket: [[TI-3845]]

## Beteiligte Systeme

| System | Rolle |
| --- | --- |
| **RIS** | Quelle für Sitzungen, Traktanden, Geschäfte und Dokumentverweise. Django-Backend mit Nuxt-2-Frontend. |
| **GEVER** | Speichert die Originaldokumente. |
| **Bumblebee** | Wandelt Dokumente in PDFs um und meldet das Ergebnis asynchron per Callback an RIS. |
| **Grimlock** | Die Sitzungs-App für Ratsmitglieder. Eigenes Django-Backend, eigenes Frontend und mosquitto für Live-Updates über MQTT. |

RIS spricht die Admin-API von Grimlock pro Gremium an. URL und Token sind am Gremium hinterlegt. Der Client liegt in `ris/grimlock/client.py`.

## Ablauf heute

```
Sitzungsseite in RIS, Aktion «Sitzung in Sitzungs-App übertragen»
  → POST meetings/{id}/prepare_zip, wiederholt als Polling
      → RIS legt GrimlockExportZip und GrimlockExportFile an
      → RIS bestellt PDFs bei Bumblebee
      → Bumblebee → POST api/bumblebee-demand-callback
      → nur weitere prepare_zip-Aufrufe treiben Fortschritt, Timeout und ZIP-Bau voran
  → POST meetings/{id}/send_zip_to_grimlock
      → meeting.set_public(), is_published wird vor der Grimlock-Antwort gesetzt
      → Grimlock PATCH /committees/{uid}/import_meeting mit dem ZIP
```

Verlässt die Person die Seite, bleibt die Aufbereitung stehen.

### RIS: relevante Stellen

| Was | Wo |
| --- | --- |
| Viewset für ZIP-Vorbereitung, Versand und Download | `ris/api/viewsets/meeting.py`, Klasse `MeetingGrimlockExportZipViewSet` |
| Modelle `GrimlockExportZip` und `GrimlockExportFile` | `ris/models/grimlock.py` |
| ZIP-Aufbau | `ris/grimlock/export_zip_builder.py` |
| Metadaten-Sync `GrimlockMeetingDataSyncServie` | `ris/grimlock/services.py` |
| Command für den Metadaten-Sync | `ris/grimlock/management/commands/synchronize_meeting_data.py` |
| Bumblebee-Callback | `ris/api/views/bumblebee.py` |
| Aktion im Frontend | `frontend/pages/gremium/_committee/sitzungen/_id.vue` |
| Vorbild für Status und Retry bei der Website-Publikation | `ris/api/viewset_mixins.py` und `frontend/components/document/DocumentsTable.vue` |
| Hintergrundjobs | `cronjobs/crontab.txt`, zum Beispiel `run_publication_cron` |

RIS nutzt für Hintergrundarbeit Cronjobs. Celery gibt es nicht.

### RIS: Endpunkte zur Sitzungs-App

| Endpunkt | Zweck heute |
| --- | --- |
| `POST meetings/{id}/prepare_zip` | Baut das ZIP für Grimlock schrittweise auf. Das Frontend ruft ihn per Polling auf. |
| `POST meetings/{id}/prepare_download_zip` | Dasselbe für den ZIP-Download. |
| `POST meetings/{id}/send_zip_to_grimlock` | Sendet das fertige ZIP an Grimlock. |
| `GET meetings/{id}/download_zip` | Liefert das ZIP an den Browser. |
| `POST api/bumblebee-demand-callback` | Nimmt die PDFs von Bumblebee entgegen. |

## Grimlock: relevante Stellen

| Was | Wo |
| --- | --- |
| Admin-API, Klasse `CommitteeViewSet` | `backend/admin/api/viewsets.py` |
| ZIP-Import, Klasse `MeetingImport` | `backend/importer.py` |
| Serializer für beide Importe | `backend/serializers/meeting.py` |
| Import von Traktanden, Anträgen und Beilagen | `backend/serializers/agenda_item.py` |
| Manueller Upload durch verantwortliche Personen | `backend/api_v1/viewsets/committee.py`. RIS nutzt ihn nicht. |

### Grimlock: Endpunkte, die RIS aufruft

| Endpunkt | Inhalt | Verhalten |
| --- | --- | --- |
| `PATCH /api/{version}/admin/committees/{uid}/import_meeting` | ZIP mit Metadaten und PDFs | Legt die Sitzung an oder aktualisiert sie. Geht davon aus, dass das ZIP vollständig ist. |
| `PATCH /api/{version}/admin/committees/{uid}/import_meeting_data` | JSON mit Metadaten, ohne Dateien | Aktualisiert nur. Fehlt die Sitzung, antwortet er mit Fehler 400. |
| `POST /api/{version}/admin/committee_synchronization` | Gremien und Mitglieder | Für dieses Feature nicht betroffen. |
| `POST /api/{version}/admin/business_type_synchronisation` | Geschäftstypen | Für dieses Feature nicht betroffen. |

### Grimlock: Was der ZIP-Import löscht

| Was im ZIP fehlt | Was Grimlock tut |
| --- | --- |
| Ein Sitzungsdokument | Es wird gelöscht. |
| Alle Sitzungsdokumente | Alle werden gelöscht. |
| Das Protokoll | Es wird gelöscht. |
| Ein Traktandum | Es wird als gelöscht markiert, mit seinen Tagesordnungseinträgen. |
| Ein Antrag | Er wird gelöscht. |
| Beilagen eines Traktandums | Die Liste wird durch die gelieferte ersetzt. |

Lässt RIS ein fehlgeschlagenes Dokument einfach weg, löscht Grimlock also dessen alte Version. Der Metadaten-Import markiert fehlende Traktanden ebenfalls als gelöscht. Das passt, weil RIS dort immer alle Traktanden sendet.

## Gewünschter Ablauf

```
Aktion in RIS
  → RIS startet einen nachvollziehbaren Sync-Lauf
  → Metadaten sofort an Grimlock, ohne auf Bumblebee zu warten
      → Grimlock legt Sitzung und Struktur an oder aktualisiert sie
  → RIS bestellt PDFs bei Bumblebee, ein Hintergrundjob führt den Lauf weiter
  → sobald alle Versuche fertig sind: verfügbare PDFs separat an Grimlock
      → fehlgeschlagene Dokumente fehlen, ohne dass Grimlock alte Versionen löscht
  → RIS zeigt Metadatenstatus und Status pro Dokument dauerhaft in der Sitzung
  → «Erneut übertragen» bereitet nur das gewählte Dokument auf und sendet nur dieses
```

## Was sich ändern muss

| System | Stelle | Änderung |
| --- | --- | --- |
| Grimlock | `import_meeting_data` | Muss neue Sitzungen samt Traktanden-Struktur anlegen können. |
| Grimlock | `import_meeting` oder ein neuer Endpunkt | Dokumente ergänzen, ohne fehlende zu löschen. |
| Grimlock | neu | Ein einzelnes Dokument annehmen: Sitzungsdokument, Protokoll, Antrag oder Beilage. |
| RIS | Metadaten-Sync | Muss den fachlichen Umfang des ZIPs abdecken, zum Beispiel Tagesordnungseinträge mit `is_marked_for_grimlock`. |
| RIS | `prepare_zip` und `send_zip_to_grimlock` | Die Aktion startet einen Sync-Lauf. Das Polling für das ZIP entfällt. |
| RIS | neues Modell | Sync-Lauf mit Status für die Metadaten und für jedes Dokument. |
| RIS | Bumblebee-Callback und Cronjob | Treiben den Lauf voran, ohne Frontend. Sie behandeln auch den Timeout. |
| RIS | neue Endpunkte | Sync-Status abfragen und ein Dokument erneut senden. |
| RIS | Frontend der Sitzung | Statusanzeige und Aktion «Erneut übertragen». |
| RIS | `download_zip` | Bleibt unverändert als Download für Menschen. |

## Stolpersteine

- **`is_published` belegt keinen Erfolg.** RIS setzt das Feld vor der Antwort von Grimlock. Das Feature braucht einen eigenen Status.
- **`publication_state` gehört der Website.** Das Feld beschreibt die öffentliche Publikation. Status und Retry lassen sich als Muster übernehmen, das Feld selbst nicht.
- **Echte Löschungen bleiben nötig.** Grimlock muss ein in RIS entferntes Dokument von einem fehlgeschlagenen unterscheiden können. RIS muss Löschungen deshalb explizit mitteilen.
- **Der Timeout hängt heute am Polling.** Die zehn Minuten für Bumblebee greifen nur, wenn die ZIP-Vorbereitung erneut aufgerufen wird. Künftig muss ein Hintergrundjob das übernehmen.

## Einordnung

Das Feature betrifft zwei Repositories. Es braucht Migrationen, ändert API-Verträge und bringt neues UI. Nach dem Gate in AGENTS.md sind das mindestens die Signale Vertrag, Breite, sichtbares Verhalten und Grösse. Das ist klar ein `bmad`-Vorhaben.

## Offene Fragen

- Der Auftrag verweist auf «A1». Woher kommt das, und was steht dort?
- Wer setzt die Grimlock-Seite um, und wann wird sie ausgeliefert?
- Gilt das Feature nur für das interne RIS oder auch für die Sitzungsvorbereitung (SPV)?
- Wie verhalten sich ältere Grimlock-Versionen, die die neuen Endpunkte noch nicht kennen?
