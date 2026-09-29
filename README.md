# Geile Tastatur

Eine systemweite iOS-QWERTZ-Tastatur mit Apple-artigem Layout, Zwischenablage-Verlauf, angehefteten Textbausteinen, optionaler Zahlenreihe, OpenAI-Spracheingabe und optionalen KI-Schreibvorschlägen.

## Highlights

- Echte iOS Custom Keyboard Extension
- Deutsches QWERTZ mit Ü / Ö / Ä
- Apple-artiges adaptives Hell-/Dunkel-Design
- Liquid Glass in der Hauptapp auf iOS 26+
- Optionale permanente Zahlenreihe
- Zwischenablage-Verlauf mit bis zu 100 Einträgen und Pins
- OpenAI `gpt-transcribe` für Diktat
- Optionale intelligente Diktat-Bereinigung, z. B. Selbstkorrekturen wie „nein, ich meinte …“
- Optionale KI-Schreibvorschläge über die Responses API
- API-Key wird nie im Repository hinterlegt
- GitHub Actions erzeugt eine unsignierte IPA zum anschließenden Signieren/Sideloaden

## Wichtige iOS-Grenze bei Spracheingabe

Apple erlaubt einer Drittanbieter-Keyboard-Extension keinen direkten Mikrofonzugriff. Deshalb enthält die App eine optionale **Voice Bridge**:

1. Hauptapp öffnen und Voice Bridge einschalten.
2. In einer anderen App die Geile Tastatur verwenden.
3. Mikrofon oben rechts antippen.
4. Noch einmal tippen, um zu stoppen.
5. Die Hauptapp transkribiert im Hintergrund über OpenAI und übergibt den fertigen Text über die App Group zurück an die Tastatur.

Solange die Voice Bridge aktiv ist, bleibt die Mikrofon-Audiosession technisch geöffnet und iOS zeigt den orangefarbenen Mikrofonindikator. Die Bridge sollte ausgeschaltet werden, wenn sie nicht benötigt wird.

## OpenAI

Es wird **kein API-Key mitgeliefert**. In der Hauptapp kann ein eigener OpenAI API-Key hinterlegt werden.

Standardmodelle:

- Transkription: `gpt-transcribe`
- Textbereinigung / Vorschläge: `gpt-6-luna`

## Tastatur aktivieren

Nach Installation:

**Einstellungen → Allgemein → Tastatur → Tastaturen → Tastatur hinzufügen → Geile Tastatur**

Für OpenAI, App-Group-Synchronisierung und die erweiterten Funktionen muss **Vollen Zugriff erlauben** aktiviert werden.

## Build

Das Projekt wird mit XcodeGen erzeugt.

Lokal:

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project GeileTastatur.xcodeproj -scheme GeileTastatur -sdk iphoneos -configuration Release
```

Die GitHub Action baut ohne Apple-Signatur und verpackt das Ergebnis als `GeileTastatur-unsigned.ipa`. Für eine direkte Installation auf normalen iPhones muss diese IPA anschließend mit einem gültigen Apple-Entwicklerprofil signiert bzw. von einem Sideloading-Tool neu signiert werden.
