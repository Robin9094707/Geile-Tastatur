# Geile Tastatur

Eine systemweite iOS-QWERTZ-Tastatur mit Apple-artigem Layout, Zwischenablage-Verlauf, angehefteten Textbausteinen, optionaler Zahlenreihe, OpenAI-Spracheingabe und optionalen KI-Schreibvorschlägen.

## Highlights

- Echte iOS Custom Keyboard Extension
- Deutsches QWERTZ mit Ü / Ö / Ä
- Apple-artiges adaptives Hell-/Dunkel-Design
- Feine Haptik für normale Tasten, Aktionen, Erfolg, Warnung und Fehler
- Quick-Settings direkt in der Tastatur für Zahlenreihe, KI, Haptik und API-Key
- Liquid Glass in der Hauptapp auf iOS 26+
- Optionale permanente Zahlenreihe
- Zwischenablage-Verlauf mit bis zu 100 Einträgen und Pins
- OpenAI `gpt-transcribe` für Diktat
- Optionale intelligente Diktat-Bereinigung, z. B. Selbstkorrekturen wie „nein, ich meinte …“
- Optionale KI-Schreibvorschläge über die Responses API
- API-Key wird nie im Repository hinterlegt
- GitHub Actions erzeugt eine **ad-hoc vorsignierte und mit codesign validierte Sideload-Ready IPA**

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

Die GitHub Action baut zunächst ohne Provisioning-Profil, signiert danach **zuerst die Keyboard-Extension und anschließend die Haupt-App ad-hoc**, prüft das komplette Bundle mit `codesign --verify --deep --strict` und verpackt es als `GeileTastatur-SideloadReady.ipa`.

Für die Installation auf einem normalen iPhone muss die IPA weiterhin mit deinem Apple-Entwicklerprofil durch AltStore/SideStore/Sideloadly oder ein anderes geeignetes Signing-Werkzeug neu signiert werden. Wichtig: Das Signing-Werkzeug muss **eingebettete App Extensions** mit signieren. Eine iOS-Systemtastatur kann technisch nicht ohne Keyboard-Extension gebaut werden.
