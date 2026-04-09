# HERO AI-Modus – Projektkontext

## Worum geht es?

Wir bauen ein AI-Feature für die HERO Handwerker-App (hero-software.de), das die Angebotserstellung radikal vereinfacht. Der Handwerker spricht, fotografiert und misst direkt vor Ort – die KI erstellt daraus automatisch ein strukturiertes Angebot.

Das Feature wird als native iOS App in Swift entwickelt und ist über die HERO GraphQL API an den Account des Nutzers angebunden.

## Das Kernprinzip

Alle Eingaben während der Aufnahme (Sprache, Fotos, Messungen) werden mit Zeitstempeln versehen und kontextuell einander zugeordnet. So weiß die KI nicht nur *was* gemessen wurde, sondern auch *wofür*.

## Feature-Ablauf

1. **Aufnahme starten** – Kameraansicht öffnet sich, Sprachaufnahme beginnt automatisch
2. **Während der Aufnahme** – Handwerker kann jederzeit Fotos machen, AR-Messungen durchführen (Länge / Fläche) oder die Aufnahme pausieren
3. **Aufnahme stoppen** – Timeline (Transkript + Fotos + Messungen mit Zeitstempeln) wird an die KI übergeben
4. **KI-Auswertung** – Identifiziert Leistungen, benötigte Artikel (als Kategorien), Auftragskontext und offene Fragen
5. **Fragebogen** – Klärt alle offenen Punkte vor dem finalen Angebot
6. **Angebot erstellen** – Wird direkt via GraphQL API in HERO angelegt

## Fragebogen-Typen

| # | Typ | Beschreibung |
|---|-----|--------------|
| 1 | Auftragsnachfrage | Immer die erste Frage. Vorausgefüllt wenn erkennbar, immer editierbar. Dropdown via API. |
| 2 | Abrechnungsfragen | Pro Leistung: Stunden (mit Anzahl) oder Leistungstyp (Dropdown via API)? |
| 3 | Artikelnachfrage | Pro identifiziertem Material: konkretes Produkt aus Artikelstamm wählen (Dropdown via API). Artikel werden nie von der KI festgelegt. |
| 4 | Freitext | Für alle sonstigen fehlenden Informationen. |

## Tech Stack

- **Sprache:** Swift (iOS nativ)
- **AR & Kamera:** ARKit, RealityKit, AVFoundation
- **Spracherkennung:** Apple Speech Framework
- **Backend-Anbindung:** HERO GraphQL API (Account-basiert)
- **KI:** LLM für Auswertung und Angebotserstellung

## Geplante Erweiterungen

Derselbe Aufnahme-Flow soll später auch für **Arbeitsberichte** und **Baustellenberichte** genutzt werden – primärer Anwendungsfall langfristig.

## Spätere Überlegungen (noch nicht im Scope)

- **Offline-Support:** Aufnahme soll vollständig offline funktionieren, Verarbeitung wird nachgeholt sobald Verbindung besteht
- **Lernfähigkeit:** System soll aus Korrekturen im Fragebogen lernen und Vorschläge über Zeit verbessern

