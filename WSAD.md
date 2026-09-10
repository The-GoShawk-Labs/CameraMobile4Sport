Jesteś Senior Flutter Architect, Mobile Video Engineer i UX Engineer.

Rozbuduj istniejący projekt:

VOLLEYLIVE ANALYTICS

o lekki, produkcyjny MVP inspirowany sposobem działania aplikacji SportCam.

REFERENCJA FUNKCJONALNA:

SportCam posiada:

* streaming sportu z telefonu,
* scoreboard nakładany na video,
* zdalne sterowanie wynikiem z drugiego urządzenia,
* zapis video lokalnie,
* YouTube,
* Facebook,
* RTMP,
* scoreboard customization,
* logo i tekst overlay,
* zoom.

Nie kopiuj interfejsu ani kodu SportCam.

Wykorzystaj jedynie wzorzec funkcjonalny:
CAMERA DEVICE
+
REMOTE SCORING DEVICE.

==================================================
GŁÓWNY CEL MVP
==============

Zbuduj prosty system dwóch smartfonów:

PHONE A
CAMERA

PHONE B
SCORER + STREAMER

PHONE A odpowiada za:

* kamerę,
* ustawienia obrazu,
* połączenie z PHONE B,
* lokalne nagrywanie video,
* wysyłanie obrazu do PHONE B.

PHONE B odpowiada za:

* scoreboard,
* sterowanie wynikiem,
* konfigurację meczu,
* odbieranie video z PHONE A,
* nakładanie scoreboardu,
* PIP / overlay w przyszłości,
* streaming live,
* lokalne nagrywanie,
* ustawienia połączenia,
* wybór platformy streamingowej.

==================================================
ZASADA UX
=========

Podczas meczu:

PHONE A:

"USTAW I ZOSTAW"

PHONE B:

"STERUJ MECZEM"

Operator kamery nie powinien dotykać telefonu podczas gry.

Scorer powinien mieć bardzo duże przyciski:

+1 TEAM A
+1 TEAM B

oraz:

UNDO

ROTATION

TIMEOUT

SET

START LIVE

STOP LIVE

==================================================
TRYBY PRACY
===========

Aplikacja po uruchomieniu pokazuje:

NEW MATCH

następnie:

CAMERA
SCORER

PHONE A wybiera:

CAMERA

PHONE B wybiera:

SCORER + STREAMER

W przyszłości można dodać:

ANALYST

ale NIE implementuj pełnego trybu Analyst w tym MVP.

Przygotuj tylko architekturę pozwalającą go później dodać.

==================================================
PHONE A
CAMERA
======

Główny ekran:

+--------------------------------+
| CAMERA PREVIEW                 |
|                                |
|                                |
|                                |
|                                |
+--------------------------------+
| CONNECTION: CONNECTED           |
| 1080p | 30 FPS | WiFi          |
+--------------------------------+
| REC          CAMERA SETTINGS   |
+--------------------------------+

Funkcje:

CAMERA PREVIEW

START RECORDING

STOP RECORDING

CAMERA SWITCH

ZOOM

FOCUS

EXPOSURE

RESOLUTION

FPS

STABILIZATION

MIC

==================================================
PHONE A
LOCAL RECORDING
===============

PHONE A musi móc nagrywać lokalnie nawet wtedy, gdy:

* PHONE B jest niedostępny,
* Internet jest niedostępny,
* streaming jest niedostępny.

To jest ważny tryb bezpieczeństwa.

Przepływ:

CAMERA
↓
LOCAL RECORDING

oraz równolegle:

CAMERA
↓
NETWORK
↓
PHONE B

Jeżeli połączenie z PHONE B zostanie zerwane:

LOCAL RECORDING CONTINUES.

Nie wolno zatrzymać nagrywania tylko dlatego, że zerwano połączenie między telefonami.

==================================================
PHONE B
SCORER + STREAMER
=================

Główny ekran:

+----------------------------------------+
| TEAM A       12 : 10       TEAM B     |
|                                        |
+----------------------------------------+
|                                        |
|          VIDEO FROM PHONE A            |
|                                        |
|                                        |
+----------------------------------------+
|                                        |
| TEAM A       TEAM B                    |
|   -  +          -  +                   |
|                                        |
| UNDO     SET     TIMEOUT               |
+----------------------------------------+
| REC | LIVE | CONNECTION | SETTINGS     |
+----------------------------------------+

Najważniejszy element:

VIDEO FROM PHONE A

Scoreboard jest overlayem.

==================================================
SCOREBOARD
==========

Dla volleyball:

TEAM A
TEAM B

POINTS

SETS

SERVE INDICATOR

TIMEOUT

SET NUMBER

Dodatkowo:

team name
team color
logo

Przyciski:

A +
B +

UNDO

SET SCORE

RESET

TIMEOUT

Nie wymagaj precyzyjnego kliknięcia.

Przyciski scoringu mają być duże.

==================================================
VOLLEYBALL LOGIC
================

Implementuj podstawowe zasady:

* punkty,
* sety,
* zmiana seta,
* serwis,
* timeout,
* undo.

Przygotuj model rotacji, ale nie buduj jeszcze zaawansowanego systemu analitycznego.

Architektura musi umożliwiać później:

player rotation
player positions
events
serve tracking.

==================================================
POŁĄCZENIE PHONE A ↔ PHONE B
============================

To jest kluczowy element.

PHONE A:

VIDEO SOURCE

PHONE B:

VIDEO RECEIVER

Połączenie powinno być:

LOW LATENCY
LOCAL FIRST
STABLE
SECURE.

Preferowany mechanizm:

WebRTC

dla przesyłania video pomiędzy urządzeniami.

Nie przesyłaj klatek jako pojedynczych obrazów przez HTTP.

Nie buduj własnego protokołu video.

Docelowy przepływ:

PHONE A
Camera
↓
Video Encoder
↓
WebRTC
↓
Local Network
↓
PHONE B
Video Receiver
↓
Scoreboard Overlay
↓
Streaming / Recording

==================================================
PAIRING
=======

Nie wymagaj ręcznego wpisywania adresu IP.

PHONE B:

CREATE MATCH

generuje:

PAIRING CODE
+
QR CODE

PHONE A:

JOIN MATCH

skanuje QR.

Połączenie:

PHONE A
CONNECTED

PHONE B
CAMERA CONNECTED

==================================================
NETWORK
=======

Preferuj:

LOCAL WiFi

lub:

PHONE B hotspot / local network.

Aplikacja powinna wykryć:

WiFi
Mobile Data
No Network

i pokazać użytkownikowi prosty komunikat.

Nie wymagaj Internetu do:

PHONE A ↔ PHONE B

Internet jest wymagany dopiero dla:

YouTube
Meta/Facebook
RTMP

==================================================
CONNECTION STATES
=================

PHONE A:

DISCONNECTED
CONNECTING
CONNECTED
RECONNECTING
FAILED

PHONE B:

CAMERA OFFLINE
CAMERA CONNECTING
CAMERA CONNECTED
VIDEO STREAMING
VIDEO LOST
RECONNECTING

Jeżeli video zostanie utracone:

PHONE B pokazuje:

CAMERA CONNECTION LOST

oraz:

RECONNECT

PHONE A nadal może nagrywać lokalnie.

==================================================
VIDEO QUALITY
=============

PHONE A pozwala wybrać:

720p
1080p

oraz:

30 FPS
60 FPS

Domyślnie:

1080p / 30 FPS

Jeżeli urządzenie lub sieć nie pozwala na 1080p:

automatycznie przełącz na niższą jakość.

Dodaj:

AUTO QUALITY

w późniejszym etapie.

==================================================
PHONE B
STREAMING
=========

PHONE B może działać w trzech trybach:

1. LIVE STREAM
2. LOCAL RECORDING
3. LIVE + LOCAL RECORDING

==================================================
LIVE STREAM
===========

Przygotuj abstrakcję:

StreamingService

Obsługiwane cele:

YouTube
Meta/Facebook
Generic RTMP

Nie implementuj integracji platformowej jako części UI.

Użyj:

StreamingDestination

z polami:

type
name
endpoint
credentialReference
enabled

Typy:

YOUTUBE
META
RTMP

==================================================
SECURITY
========

Nigdy nie przechowuj:

stream keys
API keys
tokens
passwords

w kodzie.

Nie przechowuj ich w:

SharedPreferences.

Użyj:

Secure Storage.

Dane streamingowe powinny być reprezentowane jako:

credentialReference

a nie jawny klucz.

==================================================
YOUTUBE
=======

PHONE B powinien umożliwić:

Select YouTube
+
configure stream
+
START LIVE

Streaming key / credentials muszą być przechowywane bezpiecznie.

Nie hardcoduj danych.

==================================================
META
====

Przygotuj adapter:

MetaStreamingProvider

ale nie zakładaj konkretnego API bez sprawdzenia aktualnych wymagań platformy.

Jeżeli bezpośrednia integracja nie jest możliwa:

obsłuż Generic RTMP.

==================================================
LOCAL RECORDING PHONE B
=======================

PHONE B może zapisywać lokalnie:

VIDEO
+
SCOREBOARD

Czyli:

PHONE A video
+
PHONE B scoreboard
↓
FINAL RECORDING

Jeżeli compositing video nie jest jeszcze możliwy w MVP:

zapisz video oraz synchronized scoreboard metadata.

Nie udawaj, że overlay został fizycznie wypalony do video.

==================================================
SCOREBOARD OVERLAY
==================

Warstwy:

VIDEO
↓
SCOREBOARD
↓
TEAM LOGOS
↓
TEXT
↓
PIP
↓
GRAPHICS

W MVP implementuj:

VIDEO
+
SCOREBOARD.

PIP i dodatkowe grafiki przygotuj jako rozszerzalną architekturę.

==================================================
MATCH SESSION
=============

Utwórz:

MatchSession

zawierający:

id
createdAt
sport
teamA
teamB
score
sets
currentSet
server
cameraDevice
scorerDevice
connectionState
streamingState
recordingState

==================================================
SYNCHRONIZACJA WYNIKU
=====================

Scoreboard jest źródłem prawdy:

PHONE B

PHONE A NIE zmienia wyniku.

PHONE B wysyła:

ScoreEvent

do lokalnej warstwy synchronizacji.

Przygotuj:

MatchSyncService

który później może obsługiwać:

PHONE A
PHONE B
ANALYST DEVICE
BACKEND

==================================================
EVENT MODEL
===========

Każda zmiana wyniku:

ScoreEvent

zawiera:

id
timestamp
team
oldScore
newScore
setNumber
sourceDevice

Dzięki temu:

UNDO

może odtworzyć poprzedni stan.

==================================================
OFFLINE FIRST
=============

Aplikacja musi działać lokalnie.

Scoring:

100% offline.

Recording:

100% offline.

Camera ↔ Scorer:

lokalna sieć.

Internet:

tylko streaming zewnętrzny.

Jeżeli Internet zniknie:

STOP STREAM

ale:

CONTINUE RECORDING

oraz:

CONTINUE SCORING.

==================================================
ANALYST FUTURE
==============

NIE implementuj jeszcze CV.

Ale przygotuj:

AnalysisMode

MANUAL
ASSISTED
AUTO

oraz:

ObjectLocalizationService

HomographyService

ComputerVisionEngine

jako przyszłe interfejsy.

W Phase Lite:

implementacja:

Mock / Stub.

==================================================
PÓŹNIEJSZA ŚCIEŻKA
==================

Lite:

CAMERA
+
SCORER
+
STREAMING

↓

Phase 2:

HOMOGRAPHY

↓

Phase 3:

MANUAL PLAYER/BALL

↓

Phase 4:

ASSISTED

↓

Phase 5:

AUTO

==================================================
UX
==

Wzoruj UX funkcjonalnie na prostocie SportCam, ale zaprojektuj własny interfejs zgodny z VolleyLive Analytics.

Najważniejsza zasada:

CAMERA PHONE:

SET AND FORGET

SCORER PHONE:

CONTROL THE MATCH

Nie przeładowuj ekranu.

Nie pokazuj funkcji analitycznych podczas zwykłej transmisji.

==================================================
QUICK START
===========

Docelowy proces:

PHONE B

1. New Match
2. Volleyball
3. Team A
4. Team B
5. Create Match
6. Show QR

PHONE A

1. Camera
2. Scan QR
3. Connected
4. Position camera
5. Start Camera

PHONE B

1. Camera Connected
2. Preview
3. Start Recording / Live

Mecz:

SCORER
→
A+
lub
B+

Koniec:

STOP LIVE
+
SAVE MATCH

==================================================
SETTINGS
PHONE A
=======

Camera:

Resolution
FPS
Camera
Zoom
Focus
Exposure
Stabilization
Microphone

Connection:

WiFi
Device ID
Connection status
Reconnect

Recording:

Storage location
Resolution
FPS
Audio

==================================================
SETTINGS
PHONE B
=======

Scoreboard:

Team names
Colors
Logo
Score style
Set configuration

Camera connection:

Connected device
Signal
Video FPS
Latency
Reconnect

Streaming:

YouTube
Meta
RTMP

Recording:

Local recording
Quality
Storage

==================================================
PERMISSIONS
===========

PHONE A:

CAMERA
MICROPHONE
LOCAL NETWORK
STORAGE / MEDIA

tylko jeżeli wymagane przez platformę.

PHONE B:

LOCAL NETWORK
MEDIA / STORAGE

CAMERA tylko jeżeli funkcja rzeczywiście jej wymaga.

Nie dodawaj permissions na zapas.

==================================================
PHASE LITE
==========

Wykonaj tylko:

1. Two-device architecture
2. Match creation
3. QR pairing
4. Camera screen
5. Scorer screen
6. Volleyball scoreboard
7. Local connection
8. Video transport abstraction
9. Local recording abstraction
10. Streaming abstraction
11. YouTube provider architecture
12. Meta provider architecture
13. Generic RTMP provider
14. Secure credentials
15. Offline scoring
16. Connection states
17. Basic tests

==================================================
NIE IMPLEMENTUJ
===============

Na tym etapie NIE implementuj:

YOLO
MediaPipe
OpenCV tracking
Automatic ball detection
Automatic player detection
Homography UI
Advanced PIP
Multi-camera
Cloud backend
PostgreSQL
MinIO
MLflow
CVAT

Przygotuj tylko extension points.

==================================================
TESTY
=====

Minimum:

Score tests
Set tests
Rotation tests
Undo tests
Pairing tests
Connection state tests
Recording state tests
Streaming state tests
Credential storage tests

Integration:

PHONE A pairing
PHONE A disconnect
PHONE A reconnect
PHONE B scoring
Internet loss
Local recording continuation

==================================================
SECURITY
========

Wykonaj:

secret scan
permission review
dependency review
network security review

Nie commituj:

stream keys
API keys
tokens
credentials.

==================================================
PERFORMANCE
===========

Najważniejsze:

video latency
stabilność połączenia
battery consumption
thermal throttling
dropped frames
memory usage.

Nie analizuj video przez Flutter UI.

Pipeline:

PHONE A

Camera
↓
Native encoder
↓
WebRTC
↓
Network

PHONE B

WebRTC receiver
↓
Video renderer
↓
Flutter overlay
↓
Streaming / Recording

==================================================
DEFINITION OF DONE
==================

MVP jest DONE, gdy:

PHONE A może:

* uruchomić kamerę,
* pokazać preview,
* ustawić jakość,
* połączyć się z PHONE B,
* nagrywać lokalnie,
* kontynuować nagrywanie po utracie Internetu.

PHONE B może:

* utworzyć mecz,
* wygenerować QR,
* połączyć PHONE A,
* odebrać video,
* sterować wynikiem,
* wykonać UNDO,
* zmieniać set,
* wyświetlić scoreboard,
* rozpocząć lokalne nagrywanie,
* rozpocząć streaming,
* obsłużyć stan reconnecting.

System musi obsługiwać:

PHONE A offline
+
PHONE B offline
+
PHONE A ↔ PHONE B przez lokalną sieć.

Streaming zewnętrzny wymaga Internetu.

==================================================
RAPORT KOŃCOWY
==============

Po implementacji przedstaw:

1. Architecture
2. Two-phone communication design
3. Video pipeline
4. Scoreboard architecture
5. Recording architecture
6. Streaming architecture
7. Security findings
8. Permissions
9. Tests
10. Known limitations
11. Next phase

Nie implementuj kolejnych faz.

Zatrzymaj się po ukończeniu VolleyLive Lite.

ZASTĄP DOTYCHCZASOWĄ ARCHITEKTURĘ VIDEO/STREAMING PONIŻSZĄ ARCHITEKTURĄ.

==================================================
VIDEO STREAMING ARCHITECTURE
============================

Zaimplementuj architekturę:

PHONE A = CAMERA

PHONE B = SCORER + STREAMER

PHONE A nie streamuje bezpośrednio do YouTube/Meta.

PHONE A przesyła video do PHONE B przez WebRTC.

PHONE B jest głównym encoderem i punktem wyjścia transmisji zewnętrznej.

==================================================
PHONE A
CAMERA PIPELINE
===============

Camera
↓
Native Camera Capture
↓
Hardware Video Encoder
↓
WebRTC Publisher
↓
Local Network
↓
PHONE B

PHONE A równolegle może wykonywać:

Camera
↓
Local Master Recording

LOCAL MASTER RECORDING MUSI działać niezależnie od połączenia PHONE B.

Jeżeli PHONE B zostanie odłączony:

Camera recording CONTINUES.

==================================================
PHONE B
PROGRAM PIPELINE
================

WebRTC Receiver
↓
Video Renderer
↓
Program Composition
↓
Scoreboard
↓
Graphics
↓
Hardware Encoder
↓
Program Output

Program Output ma dwa niezależne cele:

1. LIVE STREAM
2. LOCAL RECORDING

==================================================
PROGRAM COMPOSITION
===================

MVP:

VIDEO
+
SCOREBOARD

Architektura musi jednak wspierać później:

VIDEO
+
SCOREBOARD
+
LOGO
+
TEXT
+
PIP
+
COURT OVERLAY
+
PLAYER MARKERS
+
BALL
+
GRAPHICS

Nie implementuj jeszcze wszystkich warstw.

Przygotuj compositing pipeline.

==================================================
PHONE B
LIVE STREAM OUTPUT
==================

Użyj:

RTMPS

jako podstawowego protokołu wyjściowego do platform streamingowych.

Preferowana konfiguracja:

H.264
CBR
AAC
30 FPS
1080p

Domyślny bitrate:

około 8 Mbps

z możliwością konfiguracji.

Nie hardcoduj parametrów platformy.

StreamingDestination powinien posiadać:

type
name
serverUrl
streamKeyReference
enabled
videoSettings
audioSettings

Typy:

YOUTUBE
META
GENERIC_RTMPS

==================================================
SECURITY
========

NIGDY nie przechowuj stream key jako zwykłego String w konfiguracji aplikacji.

Użyj:

SecureStorageService

Przechowuj:

credentialReference

zamiast:

streamKey

Nigdy nie loguj:

* stream key,
* access token,
* OAuth token,
* password.

==================================================
YOUTUBE
=======

Obsłuż:

YOUTUBE

poprzez RTMPS ingest.

Nie zakładaj konkretnego endpointu na stałe.

Konfiguracja powinna umożliwiać:

server URL
stream key

YouTube wymaga poprawnej konfiguracji encoder/ingestion.

Docelowo można dodać integrację YouTube Live API do automatycznego tworzenia/konfigurowania transmisji.

MVP może używać ręcznie skonfigurowanego stream key przechowywanego w Secure Storage.

==================================================
META
====

Obsłuż:

META

poprzez odpowiedni mechanizm RTMPS/RTMP dostępny dla konta użytkownika.

Nie zakładaj, że każdy użytkownik ma identyczny dostęp do Meta Live API.

Dlatego:

MetaStreamingProvider

musi być oddzielnym adapterem.

Jeżeli konfiguracja platformy wymaga server URL + stream key:

użyj:

serverUrl
+
credentialReference

==================================================
GENERIC RTMPS
=============

Dodaj:

GenericRtmpsProvider

Użytkownik podaje:

Server URL
Stream Key

Przykład:

rtmps://example.com/live
+
secure stream key

Nie zapisuj klucza w plaintext.

==================================================
LOCAL RECORDING
PHONE B
=======

PHONE B musi mieć możliwość:

LOCAL RECORDING

Program output powinien zawierać:

Video
+
Scoreboard

Jeżeli platform-native compositing nie jest jeszcze dostępny:

NIE udawaj, że scoreboard został wypalony do pliku.

W takim przypadku MVP może zapisać:

1. clean video
2. synchronized scoreboard metadata

i przygotować extension point dla native video compositor.

Preferowane rozwiązanie docelowe:

Program Composition
↓
Hardware Video Encoder
↓
MP4 recording

oraz równolegle:

Program Composition
↓
Hardware Video Encoder
↓
RTMPS

==================================================
ONE ENCODER
===========

Nie uruchamiaj osobnego encodera dla:

YouTube
Meta
Local Recording

Program Composition powinien być źródłem jednego zakodowanego programu.

MVP obsługuje:

ONE DESTINATION AT A TIME.

Czyli:

YouTube
OR
Meta
OR
Generic RTMPS.

==================================================
FUTURE MULTISTREAM
==================

Przygotuj architekturę na przyszłość:

Program Output
↓
Single upstream
↓
Streaming Relay
↓
├── YouTube
├── Meta
├── Twitch
└── Other platforms

NIE implementuj multistreamingu bezpośrednio z telefonu w MVP.

Nie wysyłaj wielu niezależnych RTMPS streams z PHONE B.

==================================================
WEBRTC
PHONE A → PHONE B
=================

Użyj:

flutter_webrtc

lub natywnego WebRTC przez platform abstraction.

WebRTC jest przeznaczone dla:

PHONE A → PHONE B

Nie używaj HTTP image streaming.

Nie wysyłaj pojedynczych JPEG/PNG frames.

Nie implementuj własnego transportu video.

==================================================
WEBRTC PAIRING
==============

PHONE B:

CREATE MATCH

generuje:

Pairing ID
+
QR code

PHONE A:

JOIN MATCH

skanuje QR.

Połączenie powinno ustanowić:

WebRTC Peer Connection.

W MVP urządzenia mogą być w tej samej lokalnej sieci Wi-Fi.

==================================================
NETWORK MODES
=============

Obsłuż:

LOCAL WIFI
PHONE HOTSPOT
INTERNET

MVP:

PHONE A ↔ PHONE B

preferuje:

LOCAL NETWORK.

Internet nie jest wymagany do lokalnego przesyłania video.

Internet jest wymagany dla:

YouTube
Meta
Generic RTMPS

==================================================
CONNECTION RECOVERY
===================

Jeżeli WebRTC zostanie zerwane:

PHONE B:

VIDEO CONNECTION LOST

następnie:

RECONNECTING

PHONE A:

LOCAL RECORDING CONTINUES

Po odzyskaniu połączenia:

VIDEO CONNECTED

Nie zatrzymuj lokalnego master recording na PHONE A.

==================================================
STREAMING STATES
================

CameraConnectionState:

DISCONNECTED
PAIRING
CONNECTING
CONNECTED
RECONNECTING
FAILED

StreamingState:

IDLE
PREPARING
CONNECTING
LIVE
RECONNECTING
STOPPING
STOPPED
FAILED

RecordingState:

IDLE
RECORDING
STOPPING
SAVED
FAILED

==================================================
VIDEO QUALITY
=============

PHONE A:

720p
1080p

30 FPS
60 FPS

PHONE B:

program output:

720p
1080p

30 FPS

Domyślnie:

1080p / 30 FPS

Dostosuj bitrate do jakości połączenia.

Dla YouTube stosuj parametry zgodne z aktualną dokumentacją platformy.

==================================================
STREAM HEALTH
=============

PHONE B pokazuje:

FPS
Bitrate
Dropped Frames
RTT
Network Quality
Encoder Status
Audio Status
WebRTC latency

Nie przeciążaj UI.

Pokaż tylko najważniejsze informacje.

Advanced diagnostics mogą być ukryte.

==================================================
ARCHITECTURE
============

Finalna architektura:

PHONE A

Camera
│
├── Local Master Recording
│
└── WebRTC
│
▼
PHONE B

WebRTC Receiver
│
▼
Program Composition
│
├── Scoreboard
├── Graphics
└── Future Analytics Overlay
│
▼
Hardware Encoder
│
├── Local Program Recording
│
└── RTMPS
│
├── YouTube
├── Meta
└── Generic RTMPS

==================================================
IMPORTANT
=========

Nie implementuj w MVP:

* multi-platform direct streaming,
* cloud relay,
* AI,
* YOLO,
* MediaPipe,
* OpenCV tracking,
* homography,
* automatic player detection,
* automatic ball detection.

Przygotuj tylko extension points.

==================================================
WHY THIS ARCHITECTURE
=====================

Główna zasada:

PHONE A = SOURCE

PHONE B = PRODUCTION

PHONE B jest odpowiedzialny za:

* scoreboard,
* program output,
* recording,
* streaming.

Dzięki temu użytkownik może zmienić platformę streamingową bez zmiany działania PHONE A.

==================================================
IMPLEMENTATION PREFERENCE
=========================

Do WebRTC:

preferuj aktualnie utrzymywane:

flutter_webrtc

lub natywne WebRTC przez platform channel, jeśli wymagania wydajnościowe tego wymagają.

Do RTMP/RTMPS:

możesz wykorzystać aktualnie utrzymywane rozwiązanie Flutter/native.

Sprawdź aktualny stan:

rtmp_streaming

oraz jego natywne zależności.

Nie traktuj biblioteki jako bezwarunkowo zaufanej tylko dlatego, że jest dostępna na pub.dev.

Przed przyjęciem dependency sprawdź:

* maintenance,
* repository,
* license,
* dependencies,
* Android compatibility,
* iOS compatibility,
* open issues,
* security history.

Jeżeli plugin nie spełnia wymagań produkcyjnych:

utwórz:

PlatformStreamingService

i przygotuj natywną implementację Android/iOS.

==================================================
SECURITY REQUIREMENT
====================

RTMPS zamiast zwykłego RTMP wszędzie, gdzie platforma to obsługuje.

YouTube oficjalnie rekomenduje RTMPS dla encoderów.

Stream keys:

Secure Storage only.

Nigdy:

source code
assets
.env committed to Git
SharedPreferences
logs
analytics events

==================================================
TEST SCENARIOS
==============

Test 1:

PHONE A
+
PHONE B
+
local WiFi
+
video

Test 2:

PHONE A recording
+
PHONE B disconnected

Expected:

recording continues.

Test 3:

PHONE B
+
YouTube RTMPS

Expected:

LIVE.

Test 4:

PHONE B
+
Generic RTMPS

Expected:

LIVE.

Test 5:

Internet lost.

Expected:

local recording continues.

Test 6:

WebRTC connection lost.

Expected:

PHONE A recording continues.

PHONE B enters:

RECONNECTING.

Test 7:

YouTube unavailable.

Expected:

local recording continues.

Test 8:

stream key missing.

Expected:

safe configuration error.

Never log credential.

==================================================
DEFINITION OF DONE
==================

MVP jest gotowe, gdy:

PHONE A:

Camera
+
Local Master Recording
+
WebRTC

działa.

PHONE B:

WebRTC Receiver
+
Scoreboard
+
Program Composition
+
Local Program Recording
+
RTMPS Streaming

działa.

Platform abstractions:

YouTube
Meta
Generic RTMPS

są gotowe.

MVP obsługuje jedną platformę jednocześnie.

Architektura jest gotowa do późniejszego:

MANUAL
→
ASSISTED
→
AUTO

oraz:

single stream
→
streaming relay
→
multistream.

Nie przechodź do AI/CV przed zakończeniem i przetestowaniem tego pipeline'u.
