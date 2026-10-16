/* TO-DO Bio 2.4.0: pantalla y lector con pines originales; API Biometrico, TLS,
 * cola NVS persistente y envio en tarea independiente. Registro (N) y baja (B)
 * de huellas por monitor serie; el vinculo con la persona se hace en la app.
 * Completa config_local.h descargado desde Biometrico > Dispositivos. */
#include <Arduino.h>
#include <SPI.h>
#include <WiFi.h>
#include <time.h>
#include <Adafruit_GFX.h>
#include <Adafruit_ST7789.h>
#include <Adafruit_Fingerprint.h>
#include <XPT2046_Touchscreen.h>
#include "config_local.h"  // Privado. Descargar desde Biometrico > Dispositivos.
#include "conexion_todo.h"

// -------- Configuracion fisica que ya funciono en el prototipo --------
constexpr int PIN_TFT_CS = 10;
constexpr int PIN_TFT_DC = 9;
constexpr int PIN_TFT_RST = 8;
constexpr int PIN_TFT_MOSI = 11;
constexpr int PIN_TFT_SCLK = 12;
constexpr int PIN_FP_RX = 17;   // ESP32 recibe TX del sensor
constexpr int PIN_FP_TX = 18;   // ESP32 transmite a RX del sensor
constexpr uint32_t FP_BAUD = 115200;
#define DEVICE_ID TODO_DEVICE_ID

// SPI de pantalla por HARDWARE (MOSI 11, SCK 12, MISO 13, CS 10 son los pines SPI por defecto del
// ESP32-S3): mucho mas rapido y sin parpadeo. Si la pantalla quedara en blanco con este montaje,
// poner TFT_SPI_HARDWARE en 0 para volver al SPI por software original.
#define TFT_SPI_HARDWARE 1
#if TFT_SPI_HARDWARE
Adafruit_ST7789 tft(PIN_TFT_CS, PIN_TFT_DC, PIN_TFT_RST);
#else
Adafruit_ST7789 tft(PIN_TFT_CS, PIN_TFT_DC,
                   PIN_TFT_MOSI, PIN_TFT_SCLK, PIN_TFT_RST);
#endif
HardwareSerial sensorUart(1);
Adafruit_Fingerprint huella(&sensorUart);

// -------- Paleta RGB565 y estados --------
constexpr uint16_t BG = 0x0862;        // azul noche
constexpr uint16_t PANEL = 0x1106;
constexpr uint16_t CARD = 0x1929;
constexpr uint16_t WHITE = 0xFFFF;
constexpr uint16_t MUTED = 0xB5B6;
constexpr uint16_t CYAN = 0x5E9F;
constexpr uint16_t BLUE = 0x2C9F;
constexpr uint16_t GREEN = 0x058F;
constexpr uint16_t ORANGE = 0xFD20;
constexpr uint16_t RED = 0xE986;

bool sensorOK = false;
bool capacidadValida = false;
bool contadorValido = false;
uint16_t capacidad = 0;
uint16_t usadas = 0;
char modo = 'E';  // Entrada o Salida; cambiable por monitor serie.
bool esperandoRetiro = false;
bool enRegistro = false;          // true mientras corre el registro de huella
uint16_t borradoPendiente = 0;    // posicion a borrar, a la espera de SI
uint32_t borradoVenceMs = 0;
uint32_t ultimaLecturaMs = 0;
uint32_t ultimaHoraMs = 0;
uint32_t ultimoWifiMs = 0;
uint32_t ultimoReintentoSensorMs = 0;
bool ultimoWifiConectado = false;
String mensaje = "Iniciando sistema";
String detalle = "Esperando conexion con TO-DO";

String textoModo() { return modo == 'E' ? "ENTRADA" : "SALIDA"; }

String horaLocal() {
  time_t ahora = time(nullptr);
  if (ahora < 1609459200) return "--:--";
  struct tm tmLocal;
  localtime_r(&ahora, &tmLocal);
  char buf[9];
  snprintf(buf, sizeof(buf), "%02d:%02d", tmLocal.tm_hour, tmLocal.tm_min);
  return String(buf);
}

String fechaLocal() {
  time_t ahora = time(nullptr);
  if (ahora < 1609459200) return "HORA PENDIENTE";
  struct tm tmLocal;
  localtime_r(&ahora, &tmLocal);
  char buf[18];
  snprintf(buf, sizeof(buf), "%02d/%02d/%04d",
           tmLocal.tm_mday, tmLocal.tm_mon + 1, tmLocal.tm_year + 1900);
  return String(buf);
}

void texto(uint16_t x, uint16_t y, const String &s,
           uint16_t color, uint8_t size) {
  tft.setTextColor(color);
  tft.setTextSize(size);
  tft.setCursor(x, y);
  tft.print(s);
}

void pintarCabecera() {
  tft.fillRoundRect(6, 5, 308, 33, 8, PANEL);
  texto(16, 13, "TO-DO", CYAN, 2);
  texto(89, 14, "Bio", WHITE, 2);
  texto(179, 17, "V1", MUTED, 1);
  bool ok = WiFi.status() == WL_CONNECTED;
  tft.fillRoundRect(232, 11, 73, 21, 7, ok ? GREEN : CARD);
  texto(240, 18, ok ? "WIFI OK" : "SIN WIFI", WHITE, 1);
}

void pintarHora() {
  tft.fillRoundRect(8, 44, 147, 73, 11, CARD);
  texto(18, 54, "HORA / COLOMBIA", MUTED, 1);
  texto(18, 71, horaLocal(), WHITE, 3);
  texto(18, 102, fechaLocal(), MUTED, 1);
}

void pintarCapacidad() {
  tft.fillRoundRect(163, 44, 149, 73, 11, CARD);
  texto(174, 54, "HUELLAS DEL SENSOR", MUTED, 1);
  if (!sensorOK || !capacidadValida || !contadorValido) {
    texto(174, 72, "N/D", ORANGE, 2);
    texto(174, 98, sensorOK ? "CONSULTA FALLIDA" : "SIN SENSOR", MUTED, 1);
    return;
  }

  String cifra = String(usadas) + "/" + String(capacidad);
  texto(174, 70, cifra, WHITE, 2);
  uint16_t libres = capacidad >= usadas ? capacidad - usadas : 0;
  texto(174, 91, "LIBRES: " + String(libres), CYAN, 1);
  tft.fillRoundRect(174, 104, 125, 6, 3, PANEL);
  uint16_t ancho = capacidad ? (uint32_t(usadas) * 125U) / capacidad : 0;
  if (ancho > 125) ancho = 125;
  if (ancho > 0) tft.fillRect(174, 104, ancho, 6, GREEN);
}

void pintarBotones() {
  tft.fillRoundRect(8, 126, 147, 50, 11, modo == 'E' ? BLUE : CARD);
  tft.fillRoundRect(163, 126, 149, 50, 11, modo == 'S' ? GREEN : CARD);
  texto(31, 145, "ENTRADA", WHITE, 2);
  texto(198, 145, "SALIDA", WHITE, 2);
}

void pintarEstado() {
  tft.fillRoundRect(8, 185, 224, 43, 9, PANEL);
  texto(17, 193, mensaje.substring(0, 34), WHITE, 1);
  texto(17, 210, detalle.substring(0, 34), MUTED, 1);
  tft.fillRoundRect(238, 185, 74, 43, 9, BLUE);
  texto(250, 196, "REGISTRAR", WHITE, 1);
  texto(256, 210, "HUELLA", WHITE, 1);
}

// Texto que se parte por palabras y usa el tamano mas grande que quepa en el recuadro.
int partirLineas(const String &t, int maxChars, String *lin, int maxL) {
  int n = 0; String actual = "";
  int i = 0; const int L = t.length();
  if (maxChars < 1) maxChars = 1;
  while (i < L && n < maxL) {
    int j = t.indexOf(' ', i); if (j < 0) j = L;
    String pal = t.substring(i, j); i = j + 1;
    while ((int)pal.length() > maxChars) {  // palabra mas larga que una linea
      if (actual.length()) { lin[n++] = actual; actual = ""; if (n >= maxL) return n; }
      lin[n++] = pal.substring(0, maxChars); pal = pal.substring(maxChars);
      if (n >= maxL) return n;
    }
    if (!actual.length()) actual = pal;
    else if ((int)(actual.length() + 1 + pal.length()) <= maxChars) actual += " " + pal;
    else { lin[n++] = actual; actual = pal; }
  }
  if (actual.length() && n < maxL) lin[n++] = actual;
  return n;
}
void textoAjustado(int x, int y, int w, int h, const String &t, uint16_t color,
                   uint8_t maxSize, uint8_t minSize = 1, bool centrar = false) {
  String lin[14];
  uint8_t size = maxSize;
  int n = partirLineas(t, w / (6 * size), lin, 14);
  while (size > minSize && n * 9 * size > h) { size--; n = partirLineas(t, w / (6 * size), lin, 14); }
  const int lh = 9 * size;
  int y0 = y + (centrar ? max(0, (h - n * lh) / 2) : 0);
  tft.setTextWrap(false); tft.setTextSize(size); tft.setTextColor(color);
  for (int i = 0; i < n; i++) {
    if (i * lh + 8 * size > h) break;
    int cx = centrar ? x + max(0, (w - (int)lin[i].length() * 6 * size) / 2) : x;
    tft.setCursor(cx, y0 + i * lh); tft.print(lin[i]);
  }
}

// Saludo de bienvenida / despedida con el nombre que devuelve el servidor. La fuente de la
// pantalla no tiene tildes ni enie: se transcriben a ASCII.
uint32_t saludoHastaMs = 0;
String sinTildes(const String &s) {
  String out;
  for (size_t i = 0; i < s.length(); i++) {
    uint8_t c = s[i];
    if (c < 0x80) { out += (char)c; continue; }
    if (c == 0xC3 && i + 1 < s.length()) {
      uint8_t d = s[++i];
      switch (d) {
        case 0xA1: case 0x81: out += (d == 0xA1 ? 'a' : 'A'); break;
        case 0xA9: case 0x89: out += (d == 0xA9 ? 'e' : 'E'); break;
        case 0xAD: case 0x8D: out += (d == 0xAD ? 'i' : 'I'); break;
        case 0xB3: case 0x93: out += (d == 0xB3 ? 'o' : 'O'); break;
        case 0xBA: case 0x9A: case 0xBC: case 0x9C: out += ((d == 0xBA || d == 0xBC) ? 'u' : 'U'); break;
        case 0xB1: case 0x91: out += (d == 0xB1 ? 'n' : 'N'); break;
      }
    }
  }
  return out;
}
void saludar(const String &texto) {
  int coma = texto.lastIndexOf(", ");
  String titulo = coma >= 0 ? texto.substring(0, coma + 1) : texto;
  String nombre = coma >= 0 ? sinTildes(texto.substring(coma + 2)) : "";
  const bool entrada = titulo.startsWith("Bienvenido");
  tft.fillScreen(BG);
  tft.fillRoundRect(8, 20, 304, 200, 16, CARD);
  tft.fillRoundRect(8, 20, 304, 8, 4, entrada ? GREEN : CYAN);
  textoAjustado(18, 40, 284, 56, titulo, entrada ? GREEN : CYAN, 3, 1, true);
  textoAjustado(18, 104, 284, 104, nombre, WHITE, 4, 1, true);
  saludoHastaMs = millis() + 4500;
}

// Reloj animado mientras se confirma la marcacion en TO-DO.
bool marcando = false;
uint32_t marcandoMs = 0, ultimoRelojMs = 0;
uint8_t frameReloj = 0;
void relojBase() {
  tft.fillScreen(BG);
  tft.fillRoundRect(8, 20, 304, 200, 16, CARD);
  textoAjustado(18, 32, 284, 30, "Registrando marcacion", WHITE, 2, 1, true);
  textoAjustado(18, 178, 284, 30, (modo == 'E' ? "ENTRADA" : "SALIDA") + String(" - un momento"), MUTED, 2, 1, true);
}
void relojFrame(uint8_t f) {
  const int cx = 160, cy = 120, r = 44;
  tft.fillCircle(cx, cy, r + 3, CARD);
  tft.drawCircle(cx, cy, r, CYAN); tft.drawCircle(cx, cy, r - 1, CYAN);
  for (int k = 0; k < 12; k++) {
    float a = k * 0.5236f;
    tft.drawLine(cx + sinf(a) * (r - 7), cy - cosf(a) * (r - 7), cx + sinf(a) * (r - 3), cy - cosf(a) * (r - 3), WHITE);
  }
  float ag = f * 0.5236f, ac = ag / 12.0f;  // aguja larga gira; la corta avanza despacio
  for (int d = -1; d <= 1; d++) {
    tft.drawLine(cx + d, cy, cx + sinf(ag) * (r - 9) + d, cy - cosf(ag) * (r - 9), GREEN);
  }
  tft.drawLine(cx, cy, cx + sinf(ac) * (r - 20), cy - cosf(ac) * (r - 20), WHITE);
  tft.fillCircle(cx, cy, 3, WHITE);
}

void interfazCompleta() {
  tft.fillScreen(BG);
  pintarCabecera();
  pintarHora();
  pintarCapacidad();
  pintarBotones();
  pintarEstado();
  texto(14, 232, "Toca ENTRADA / SALIDA o REGISTRAR HUELLA", MUTED, 1);
}

void actualizarEstado(const String &principal, const String &secundaria) {
  mensaje = principal;
  detalle = secundaria;
  pintarEstado();
  Serial.print("ESTADO: "); Serial.print(principal);
  Serial.print(" | "); Serial.println(secundaria);
}

void consultarCapacidad() {
  capacidadValida = false;
  contadorValido = false;
  if (!sensorOK) {
    pintarCapacidad();
    return;
  }
  if (huella.getParameters() == FINGERPRINT_OK) {
    capacidad = huella.capacity;
    capacidadValida = capacidad > 0;
  }
  if (huella.getTemplateCount() == FINGERPRINT_OK) {
    usadas = huella.templateCount;
    contadorValido = true;
  }
  pintarCapacidad();
  Serial.println("--- CAPACIDAD POR DISPOSITIVO ---");
  Serial.print("Dispositivo: "); Serial.println(DEVICE_ID);
  if (capacidadValida) {
    Serial.printf("Capacidad del sensor: %u\n", capacidad);
  } else {
    Serial.println("Capacidad del sensor: NO DISPONIBLE");
  }
  if (contadorValido) {
    Serial.printf("Plantillas registradas: %u\n", usadas);
  } else {
    Serial.println("Plantillas registradas: NO DISPONIBLE");
  }
  if (capacidadValida && contadorValido) {
    Serial.printf("Cupos libres: %u\n", capacidad >= usadas ? capacidad - usadas : 0);
  }
}

void detectarSensor() {
  if (huella.verifyPassword()) {
    sensorOK = true;
    Serial.println("SFM-V1.7: sensor detectado por UART 115200");
    consultarCapacidad();
    actualizarEstado("Listo para leer huella", "Modo " + textoModo() + " / TO-DO");
  } else {
    sensorOK = false;
    capacidadValida = false;
    contadorValido = false;
    pintarCapacidad();
    actualizarEstado("Sensor no responde", "Revisar alimentacion / UART");
  }
}

// La confirmacion de captura local solo aparece despues de persistir en NVS.
void emitirEventoLocal(uint16_t slot, uint16_t puntaje) {
  if (!bioConfigurado()) { actualizarEstado("Falta configurar TO-DO", "Descarga config_local.h desde TH"); return; }
  if (!bioHoraSincronizada) { actualizarEstado("Hora pendiente de sincronizar", "Conecta WiFi antes de marcar"); return; }
  if (!bioEncolar(slot, textoModo())) { actualizarEstado("NO se guardo la marcacion", "Cola llena o error de memoria. Revisar Q"); return; }
  Serial.printf("Huella %u, puntaje %u (no porcentaje)\n", slot, puntaje);
  marcando = true; marcandoMs = millis(); frameReloj = 0;
  relojBase();
}
void leerHuella() {
  if (!sensorOK || enRegistro || millis() - ultimaLecturaMs < 180) return;
  ultimaLecturaMs = millis();
  uint8_t r = huella.getImage();
  if (r == FINGERPRINT_NOFINGER) {
    esperandoRetiro = false;
    return;
  }
  if (esperandoRetiro) return;
  if (r != FINGERPRINT_OK) return;
  esperandoRetiro = true; // Una sola lectura por cada apoyo del dedo.

  r = huella.image2Tz(1);
  if (r != FINGERPRINT_OK) {
    actualizarEstado("Lectura no valida", "Retira y vuelve a colocar");
    return;
  }
  r = huella.fingerFastSearch();
  if (r == FINGERPRINT_OK) {
    emitirEventoLocal(huella.fingerID, huella.confidence);
  } else if (r == FINGERPRINT_NOTFOUND) {
    actualizarEstado("Huella no registrada", "Intenta nuevamente");
  } else {
    actualizarEstado("Error al buscar huella", "Codigo: " + String(r));
  }
}

// -------- Registro y baja de huellas (solo por monitor serie) --------
// La plantilla vive unicamente dentro del sensor. Una huella nueva NO marca
// asistencia hasta vincular ese numero en Biometrico > Huellas y personas.
bool slotOcupado(uint16_t id) { return huella.loadModel(id) == FINGERPRINT_OK; }

uint16_t primerSlotLibre() {
  for (uint16_t id = 1; id <= capacidad; id++) {
    if (!slotOcupado(id)) return id;
  }
  return 0;
}

void pasoRegistro(const String &titulo, const String &indicacion, uint16_t color) {
  tft.fillScreen(BG);
  tft.fillRoundRect(6, 5, 308, 33, 8, PANEL);
  texto(16, 13, "REGISTRO DE HUELLA", CYAN, 2);
  tft.fillRoundRect(8, 46, 304, 150, 12, CARD);
  textoAjustado(18, 56, 284, 60, titulo, color, 3, 1, true);
  textoAjustado(18, 124, 284, 64, indicacion, WHITE, 3, 1, true);
  textoAjustado(8, 204, 304, 30, "Apoya el dedo plano y firme sobre el lector, sin moverlo", MUTED, 1, 1, true);
}

// Espera dedo presente (true) o retirado (false).
bool esperarDedo(bool presente, uint32_t timeoutMs) {
  uint32_t ini = millis();
  while (millis() - ini < timeoutMs) {
    uint8_t r = huella.getImage();
    if (presente && r == FINGERPRINT_OK) return true;
    if (!presente && r == FINGERPRINT_NOFINGER) return true;
    delay(40);
  }
  return false;
}

void terminarRegistro(const String &principal, const String &secundaria) {
  enRegistro = false;
  esperandoRetiro = true;  // evita marcar con el dedo que sigue apoyado
  interfazCompleta();
  consultarCapacidad();
  actualizarEstado(principal, secundaria);
}

void registrarHuella(uint16_t id) {
  if (!sensorOK) { actualizarEstado("Sensor no responde", "No se puede registrar"); return; }
  if (huella.getParameters() == FINGERPRINT_OK) {
    capacidad = huella.capacity;
    capacidadValida = capacidad > 0;
  }
  if (!capacidadValida) { actualizarEstado("Capacidad desconocida", "Registro cancelado"); return; }
  if (id == 0) {
    id = primerSlotLibre();
    if (id == 0) { actualizarEstado("Sensor lleno", "Libera una posicion con B<n>"); return; }
  } else if (id > capacidad) {
    actualizarEstado("Posicion invalida", "Maximo " + String(capacidad));
    return;
  } else if (slotOcupado(id)) {
    actualizarEstado("Posicion " + String(id) + " ocupada", "Elige otra o borrala con B" + String(id));
    return;
  }

  enRegistro = true;
  Serial.printf("--- REGISTRO DE HUELLA EN POSICION %u ---\n", id);
  String pos = "Posicion " + String(id);
  pasoRegistro("1/3 Apoya el dedo", pos, WHITE);
  if (!esperarDedo(true, 25000)) return terminarRegistro("Registro fallido", "Tiempo agotado");
  if (huella.image2Tz(1) != FINGERPRINT_OK) return terminarRegistro("Registro fallido", "Lectura no valida");

  pasoRegistro("2/3 Retira el dedo", pos, ORANGE);
  if (!esperarDedo(false, 10000)) return terminarRegistro("Registro fallido", "No retiraste el dedo");

  pasoRegistro("3/3 Apoya el mismo dedo", pos, WHITE);
  if (!esperarDedo(true, 25000)) return terminarRegistro("Registro fallido", "Tiempo agotado");
  if (huella.image2Tz(2) != FINGERPRINT_OK) return terminarRegistro("Registro fallido", "Lectura no valida");

  uint8_t r = huella.createModel();
  if (r == FINGERPRINT_ENROLLMISMATCH) return terminarRegistro("Registro fallido", "Las lecturas no coinciden");
  if (r != FINGERPRINT_OK) return terminarRegistro("Registro fallido", "Error de modelo " + String(r));
  r = huella.storeModel(id);
  if (r != FINGERPRINT_OK) return terminarRegistro("Registro fallido", "Error al guardar " + String(r));

  Serial.printf("Huella guardada en la posicion %u. Vinculala en Biometrico > Huellas y personas.\n", id);
  terminarRegistro("Huella guardada: " + String(id), "Vincular en TO-DO para marcar");
}

void borrarHuella(uint16_t id) {
  if (!sensorOK || !slotOcupado(id)) {
    actualizarEstado("Posicion " + String(id) + " vacia", "Nada que borrar");
    return;
  }
  if (huella.deleteModel(id) == FINGERPRINT_OK) {
    Serial.printf("Posicion %u borrada. Retira su vinculo en Biometrico > Huellas y personas.\n", id);
    consultarCapacidad();
    actualizarEstado("Posicion " + String(id) + " borrada", "Retirar el vinculo en TO-DO");
  } else {
    actualizarEstado("Error al borrar", "Posicion " + String(id));
  }
}

// -------- Tactil XPT2046 y registro de huellas en pantalla --------
// El administrador se identifica con cedula y PIN personal, escribe la cedula de la
// persona, confirma su nombre, la persona acepta el aviso y se capturan tres toques.
// El servidor decide quien es el administrador y a quien se vincula la huella.
constexpr int PIN_T_CLK = 4, PIN_T_DIN = 5, PIN_T_DO = 6, PIN_T_CS = 7, PIN_T_IRQ = 15;
SPIClass touchSPI(HSPI);
XPT2046_Touchscreen ts(PIN_T_CS, PIN_T_IRQ);
Preferences tactilNvs;
bool tactilCalibrado = false, tactilIntercambiar = false;
float tactilXMin = 0, tactilXMax = 1, tactilYMin = 0, tactilYMax = 1;
constexpr int16_t CAL_X[4] = {20, 300, 20, 300};
constexpr int16_t CAL_Y[4] = {20, 20, 220, 220};

void cruzCalibracion(int16_t x, int16_t y, uint16_t c) {
  tft.drawFastHLine(x - 12, y, 25, c); tft.drawFastVLine(x, y - 12, 25, c); tft.drawCircle(x, y, 7, c);
}

// Espera un toque, promedia mientras esta apoyado y espera a que se suelte (valores crudos).
bool leerToqueCrudo(int &sx, int &sy, uint32_t timeoutMs) {
  uint32_t ini = millis();
  while (!ts.touched()) { if (millis() - ini > timeoutMs) return false; delay(5); }
  long ax = 0, ay = 0; int n = 0; uint32_t t0 = millis();
  while (ts.touched() && millis() - t0 < 1500) {
    TS_Point p = ts.getPoint();
    if (p.z > 200) { ax += p.x; ay += p.y; n++; }
    delay(8);
  }
  while (ts.touched()) delay(5);
  if (n < 3) return false;
  sx = ax / n; sy = ay / n; return true;
}

void tactilCalibrar() {
  int rx[4], ry[4];
  for (int i = 0; i < 4; i++) {
    tft.fillScreen(BG);
    cruzCalibracion(CAL_X[i], CAL_Y[i], CYAN);
    texto(70, 100, "Calibrar tactil", WHITE, 2);
    texto(100, 130, "Toca la cruz " + String(i + 1) + " de 4", MUTED, 1);
    int x = 0, y = 0;
    while (!leerToqueCrudo(x, y, 60000)) delay(100);
    rx[i] = x; ry[i] = y;
    cruzCalibracion(CAL_X[i], CAL_Y[i], GREEN); delay(250);
  }
  tactilIntercambiar = abs(ry[1] - ry[0]) > abs(rx[1] - rx[0]);
  auto h = [&](int i) { return tactilIntercambiar ? ry[i] : rx[i]; };
  auto v = [&](int i) { return tactilIntercambiar ? rx[i] : ry[i]; };
  tactilXMin = (h(0) + h(2)) / 2.0f; tactilXMax = (h(1) + h(3)) / 2.0f;
  tactilYMin = (v(0) + v(1)) / 2.0f; tactilYMax = (v(2) + v(3)) / 2.0f;
  tactilCalibrado = fabsf(tactilXMax - tactilXMin) > 200 && fabsf(tactilYMax - tactilYMin) > 200;
  if (tactilCalibrado) {
    tactilNvs.putBool("ok", true); tactilNvs.putBool("sw", tactilIntercambiar);
    tactilNvs.putFloat("x0", tactilXMin); tactilNvs.putFloat("x1", tactilXMax);
    tactilNvs.putFloat("y0", tactilYMin); tactilNvs.putFloat("y1", tactilYMax);
  }
  Serial.println(tactilCalibrado ? "Tactil calibrado y guardado." : "Calibracion invalida: repite con T.");
}

void tactilIniciar() {
  touchSPI.begin(PIN_T_CLK, PIN_T_DO, PIN_T_DIN, PIN_T_CS);
  ts.begin(touchSPI);
  tactilNvs.begin("todo-tactil", false);
  if (tactilNvs.getBool("ok", false)) {
    tactilIntercambiar = tactilNvs.getBool("sw", false);
    tactilXMin = tactilNvs.getFloat("x0", 0); tactilXMax = tactilNvs.getFloat("x1", 1);
    tactilYMin = tactilNvs.getFloat("y0", 0); tactilYMax = tactilNvs.getFloat("y1", 1);
    tactilCalibrado = true;
  } else {
    tactilCalibrar();
  }
}

// Un toque ya convertido a coordenadas de pantalla; espera a que se suelte.
bool tocarUna(int &sx, int &sy) {
  if (!tactilCalibrado || !ts.touched()) return false;
  long ax = 0, ay = 0; int n = 0; uint32_t t0 = millis();
  while (ts.touched() && millis() - t0 < 120) {
    TS_Point p = ts.getPoint();
    if (p.z > 200) { ax += p.x; ay += p.y; n++; }
    delay(4);
  }
  while (ts.touched() && millis() - t0 < 1500) delay(3);
  if (n < 2) return false;
  float rx = ax / (float)n, ry = ay / (float)n;
  float hh = tactilIntercambiar ? ry : rx, vv = tactilIntercambiar ? rx : ry;
  float x = 20 + (hh - tactilXMin) * 280.0f / (tactilXMax - tactilXMin);
  float y = 20 + (vv - tactilYMin) * 200.0f / (tactilYMax - tactilYMin);
  sx = constrain((int)x, 0, 319); sy = constrain((int)y, 0, 239);
  return true;
}

bool enRect(int x, int y, int rx, int ry, int rw, int rh) { return x >= rx && x < rx + rw && y >= ry && y < ry + rh; }

// Teclado numerico en pantalla. Devuelve "" si se cancela o vence el tiempo.
String pedirNumero(const String &titulo, const String &ayuda, uint8_t maxLen, bool oculto) {
  String valor;
  const char *teclas[12] = {"1", "2", "3", "4", "5", "6", "7", "8", "9", "<", "0", "OK"};
  // Se dibuja todo una sola vez; al teclear solo se repinta el campo (sin parpadeo).
  auto campo = [&]() {
    tft.fillRoundRect(8, 40, 304, 38, 8, CARD);
    texto(14, 44, ayuda, MUTED, 1);
    String visto = "";
    if (oculto) { for (size_t i = 0; i < valor.length(); i++) visto += '*'; }
    else visto = valor;
    texto(14, 58, visto + "_", WHITE, 2);
  };
  auto dibujar = [&]() {
    tft.fillScreen(BG);
    tft.fillRoundRect(6, 5, 308, 30, 8, PANEL);
    texto(14, 12, titulo, CYAN, 2);
    tft.fillRoundRect(232, 8, 78, 24, 6, RED);
    texto(244, 16, "Cancelar", WHITE, 1);
    campo();
    for (int i = 0; i < 12; i++) {
      int x = 8 + (i % 3) * 104, y = 84 + (i / 3) * 37;
      tft.fillRoundRect(x, y, 96, 32, 8, i == 11 ? GREEN : (i == 9 ? ORANGE : CARD));
      texto(x + 48 - (strlen(teclas[i]) * 6), y + 8, teclas[i], WHITE, 2);
    }
  };
  dibujar();
  uint32_t ultimo = millis();
  while (millis() - ultimo < 90000) {
    int sx, sy;
    if (!tocarUna(sx, sy)) { delay(10); continue; }
    ultimo = millis();
    if (enRect(sx, sy, 232, 8, 78, 24)) return "";
    for (int i = 0; i < 12; i++) {
      int x = 8 + (i % 3) * 104, y = 84 + (i / 3) * 37;
      if (!enRect(sx, sy, x, y, 96, 32)) continue;
      if (i == 9) { if (valor.length()) valor.remove(valor.length() - 1); }
      else if (i == 11) { if (valor.length()) return valor; }
      else if (valor.length() < maxLen) valor += teclas[i];
      campo();
      break;
    }
  }
  return "";
}

// Dos botones; true si se toca el primero (Confirmar / Autorizo).
bool confirmarPantalla(const String &titulo, const String &cuerpo, uint8_t tamano, const String &si, const String &no) {
  tft.fillScreen(BG);
  tft.fillRoundRect(6, 5, 308, 30, 8, PANEL);
  texto(14, 12, titulo, CYAN, 2);
  tft.fillRoundRect(6, 40, 308, 124, 10, CARD);
  textoAjustado(14, 46, 292, 112, cuerpo, WHITE, tamano, 1, true);
  tft.fillRoundRect(6, 170, 150, 64, 10, GREEN);
  tft.fillRoundRect(164, 170, 150, 64, 10, RED);
  textoAjustado(10, 174, 142, 56, si, WHITE, 3, 1, true);
  textoAjustado(168, 174, 142, 56, no, WHITE, 3, 1, true);
  uint32_t ini = millis();
  while (millis() - ini < 90000) {
    int sx, sy;
    if (!tocarUna(sx, sy)) { delay(10); continue; }
    if (enRect(sx, sy, 6, 170, 150, 64)) return true;
    if (enRect(sx, sy, 164, 170, 150, 64)) return false;
  }
  return false;
}

void pantallaAviso(const String &titulo, const String &detalleAviso, uint16_t color) {
  tft.fillScreen(BG);
  tft.fillRoundRect(8, 24, 304, 192, 14, CARD);
  textoAjustado(18, 36, 284, 50, titulo, color, 3, 1, true);
  textoAjustado(18, 96, 284, 112, detalleAviso, WHITE, 3, 1, true);
}

// Llamada sincronica al servidor para el registro. true si respondio 200.
bool llamarRegistro(JsonDocument &pedido, JsonDocument &respuesta, String &error) {
  if (WiFi.status() != WL_CONNECTED) { error = "Sin WiFi"; return false; }
  pedido["deviceId"] = TODO_DEVICE_ID;
  String cuerpo; serializeJson(pedido, cuerpo);
  int codigo = bioLlamar(cuerpo, respuesta);
  if (codigo == 200) return true;
  error = codigo < 0 ? String("Sin conexion con TO-DO")
                     : sinTildes(String((const char *)(respuesta["error"] | "Error del servidor")));
  return false;
}

void salirRegistro(const String &principal, const String &detalleSalida) { terminarRegistro(principal, detalleSalida); }

void fallarRegistro(const String &motivo) {
  pantallaAviso("No se registro", motivo, RED);
  delay(3500);
  salirRegistro("Registro no completado", motivo.substring(0, 34));
}

// Captura un dedo en el buffer indicado; si la lectura sale mala pide apoyar de nuevo.
bool capturarDedo(uint8_t buffer, const String &titulo, const String &nombre) {
  for (int intento = 0; intento < 4; intento++) {
    pasoRegistro(titulo, nombre, WHITE);
    if (!esperarDedo(true, 25000)) return false;
    uint8_t r = huella.image2Tz(buffer);
    Serial.printf("Captura buffer %u intento %d -> %u\n", buffer, intento + 1, r);
    if (r == FINGERPRINT_OK) return true;
    pasoRegistro("Lectura no valida", "Retira y apoya de nuevo", ORANGE);
    esperarDedo(false, 10000);
  }
  return false;
}

void flujoRegistro() {
  if (!bioConfigurado() || WiFi.status() != WL_CONNECTED) {
    pantallaAviso("Sin conexion", "Necesita WiFi y la configuracion de TO-DO.", ORANGE); delay(2500);
    interfazCompleta(); return;
  }
  if (!sensorOK || !capacidadValida) {
    pantallaAviso("Sensor no responde", "Revisa el lector de huella.", ORANGE); delay(2500);
    interfazCompleta(); return;
  }
  enRegistro = true;

  // 1) Identificacion del administrador.
  String cedAdmin = pedirNumero("Administrador", "Escribe tu cedula", 15, false);
  if (!cedAdmin.length()) return salirRegistro("Registro cancelado", "");
  String pin = pedirNumero("Administrador", "Escribe tu PIN de 6 numeros", 6, true);
  if (pin.length() != 6) return salirRegistro("Registro cancelado", "");
  pantallaAviso("Verificando...", "Un momento.", CYAN);
  String error; JsonDocument pedido, respuesta;
  pedido["accion"] = "autenticarAdmin"; pedido["cedula"] = cedAdmin; pedido["pin"] = pin;
  pin = "";
  if (!llamarRegistro(pedido, respuesta, error)) return fallarRegistro(error);
  String sesion = String((const char *)(respuesta["sesion"] | ""));

  // 2) Persona a registrar.
  String cedula = pedirNumero("Nueva huella", "Cedula de la persona", 15, false);
  if (!cedula.length()) return salirRegistro("Registro cancelado", "");
  pantallaAviso("Buscando...", "Un momento.", CYAN);
  JsonDocument p2, r2;
  p2["accion"] = "buscarPersona"; p2["cedula"] = cedula; p2["sesion"] = sesion;
  if (!llamarRegistro(p2, r2, error)) return fallarRegistro(error);
  String nombre = sinTildes(String((const char *)(r2["nombre"] | "")));
  nombre.toUpperCase();
  if (!confirmarPantalla("Asociar huella a", nombre, 4, "Confirmar", "Cancelar"))
    return salirRegistro("Registro cancelado", "");

  // 3) Aviso y autorizacion de la persona.
  if (!confirmarPantalla("Autorizacion",
        "Tu huella se usara solo para el control de asistencia. Es voluntaria: puedes pedir otra forma de marcar.",
        3, "Autorizo", "No autorizo")) {
    pantallaAviso("Sin autorizacion", "No se guardo ninguna huella.", ORANGE); delay(2500);
    return salirRegistro("Registro cancelado", "La persona no autorizo");
  }

  // 4) Tres toques: dos para crear la plantilla y uno para verificarla (con reintentos).
  if (huella.getParameters() == FINGERPRINT_OK) { capacidad = huella.capacity; capacidadValida = capacidad > 0; }
  uint16_t id = primerSlotLibre();
  if (!id) return fallarRegistro("El sensor esta lleno.");
  uint8_t r = FINGERPRINT_ENROLLMISMATCH;
  for (int vuelta = 0; vuelta < 3 && r != FINGERPRINT_OK; vuelta++) {
    if (!capturarDedo(1, "1/3 Apoya el dedo", nombre)) return fallarRegistro("Tiempo agotado.");
    pasoRegistro("Retira el dedo", nombre, ORANGE);
    if (!esperarDedo(false, 10000)) return fallarRegistro("No retiraste el dedo.");
    if (!capturarDedo(2, "2/3 Apoya el mismo dedo", nombre)) return fallarRegistro("Tiempo agotado.");
    r = huella.createModel();
    Serial.printf("createModel -> %u\n", r);
    if (r != FINGERPRINT_OK) {
      pasoRegistro("No coinciden", "Retira y repite con el mismo dedo", ORANGE);
      esperarDedo(false, 10000);
    }
  }
  if (r != FINGERPRINT_OK) return fallarRegistro("Las lecturas no coinciden. Repite.");
  if (huella.storeModel(id) != FINGERPRINT_OK) return fallarRegistro("Error al guardar en el sensor.");
  pasoRegistro("Retira el dedo", nombre, ORANGE);
  esperarDedo(false, 10000);
  bool verificada = false;
  uint8_t rt = 0xFF, rs = 0xFF;
  for (int intento = 0; intento < 3 && !verificada; intento++) {
    pasoRegistro("3/3 Verifica: apoya", nombre, WHITE);
    if (!esperarDedo(true, 25000)) break;
    rt = huella.image2Tz(1);
    if (rt == FINGERPRINT_OK) {
      rs = huella.fingerFastSearch();
      verificada = rs == FINGERPRINT_OK && huella.fingerID == id;
    }
    Serial.printf("Verificacion %d: tz=%u busqueda=%u id=%u esperado=%u puntaje=%u\n",
                  intento + 1, rt, rs, huella.fingerID, id, huella.confidence);
    if (!verificada) {
      pasoRegistro("No coincide", "Retira y apoya de nuevo", ORANGE);
      esperarDedo(false, 10000);
    }
  }
  if (!verificada) {
    huella.deleteModel(id);
    return fallarRegistro("No se pudo verificar (tz " + String(rt) + ", busqueda " + String(rs) + ").");
  }

  // 5) Vinculo en TO-DO. Si el servidor no lo acepta, no queda una huella huerfana en el sensor.
  pantallaAviso("Guardando...", "Vinculando con TO-DO.", CYAN);
  JsonDocument p3, r3;
  p3["accion"] = "registrarHuella"; p3["cedula"] = cedula; p3["sesion"] = sesion;
  p3["slot"] = id; p3["autorizo"] = true; p3["aviso"] = "v1";
  if (!llamarRegistro(p3, r3, error)) {
    huella.deleteModel(id);
    return fallarRegistro(error);
  }
  pantallaAviso("Huella registrada", nombre, GREEN);
  delay(3000);
  salirRegistro("Huella registrada", nombre.substring(0, 34));
}

void toqueInicio(int x, int y) {
  if (enRect(x, y, 238, 185, 74, 43)) { flujoRegistro(); return; }
  if (enRect(x, y, 8, 126, 304, 50)) {
    modo = x < 159 ? 'E' : 'S';
    pintarBotones();
    actualizarEstado("Modo " + textoModo(), "Acerca tu dedo al sensor");
  }
}

void iniciarWifi() {
  if (strlen(TODO_WIFI_SSID) == 0) {
    Serial.println("WiFi sin configurar. Editar config_local.h");
    return;
  }
  WiFi.mode(WIFI_STA);
  WiFi.setAutoReconnect(true);
  WiFi.begin(TODO_WIFI_SSID, TODO_WIFI_PASS);
  Serial.println("Intentando conectar a WiFi...");
}

void imprimirAyuda() {
  Serial.println("Comandos: E=modo ENTRADA | S=modo SALIDA | C=capacidad");
  Serial.println("          I=estado | W=WiFi | H=ayuda");
  Serial.println("La lectura de huella es AUTOMATICA al colocar el dedo.");
  Serial.println("N=registrar huella en la primera posicion libre | N<n>=en la posicion n");
  Serial.println("B<n>=borrar posicion n (confirmar con SI en 15 s). Escribir + Enter.");
  Serial.println("Una huella nueva solo marca tras vincularla en Biometrico.");
  Serial.println("Tactil activo: ENTRADA / SALIDA y REGISTRAR HUELLA. T = recalibrar tactil.");
  Serial.println("Q=exportar cola pendiente/rechazada | R=reintentar rechazos");
}

void procesarLetra(char c);

void procesarComando(String cmd) {
  cmd.trim();
  cmd.toUpperCase();
  if (cmd.length() == 0) return;
  if (cmd == "SI" && borradoPendiente && millis() < borradoVenceMs) {
    uint16_t id = borradoPendiente;
    borradoPendiente = 0;
    borrarHuella(id);
    return;
  }
  borradoPendiente = 0;
  long arg = cmd.substring(1).toInt();
  if (cmd[0] == 'N') {
    registrarHuella(arg > 0 ? (uint16_t)arg : 0);
  } else if (cmd[0] == 'B' && arg > 0) {
    borradoPendiente = arg;
    borradoVenceMs = millis() + 15000;
    Serial.printf("Para borrar la posicion %ld escribe SI en 15 s.\n", arg);
    actualizarEstado("Borrar posicion " + String(arg) + "?", "Escribe SI en el monitor serie");
  } else if (cmd.length() == 1) {
    procesarLetra(cmd[0]);
  } else {
    Serial.println("Comando desconocido. H para ayuda.");
  }
}

void procesarLetra(char c) {
  {
    if (c == 'E' || c == 'e' || c == 'S' || c == 's') {
      modo = (c == 'E' || c == 'e') ? 'E' : 'S';
      pintarBotones();
      actualizarEstado("Modo " + textoModo(), "Acerca tu dedo al sensor");
    } else if (c == 'C' || c == 'c') {
      consultarCapacidad();
    } else if (c == 'I' || c == 'i') {
      Serial.print("Dispositivo: "); Serial.println(DEVICE_ID);
      Serial.print("WiFi: "); Serial.println(WiFi.status() == WL_CONNECTED ? "OK" : "OFF");
      Serial.print("Sensor: "); Serial.println(sensorOK ? "OK" : "OFF");
      consultarCapacidad();
    } else if (c == 'W' || c == 'w') {
      WiFi.disconnect();
      iniciarWifi();
    } else if (c == 'Q' || c == 'q') {
      bioColaSerial();
    } else if (c == 'R' || c == 'r') {
      bioColaSerial(true);
    } else if (c == 'T' || c == 't') {
      tactilCalibrar();
      interfazCompleta();
    } else if (c == 'H' || c == 'h') {
      imprimirAyuda();
    }
  }
}

void procesarSerial() {
  static String linea = "";
  while (Serial.available()) {
    char c = Serial.read();
    if (c == '\r' || c == '\n') {
      String cmd = linea;
      linea = "";
      procesarComando(cmd);
    } else if (linea.length() < 16) {
      linea += c;
    }
  }
}

void setup() {
  Serial.begin(115200);
  delay(700);
  Serial.println("\nTO-DO Bio V1 | Firmware conectado 2.4.0");
  bioIniciar();

#if TFT_SPI_HARDWARE
  SPI.begin(PIN_TFT_SCLK, 13, PIN_TFT_MOSI, -1);
#endif
  tft.init(240, 320);
  tft.setRotation(1);
  tft.invertDisplay(false);
  tactilIniciar();
  interfazCompleta();

  sensorUart.begin(FP_BAUD, SERIAL_8N1, PIN_FP_RX, PIN_FP_TX);
  delay(250);
  detectarSensor();
  iniciarWifi();
  imprimirAyuda();
}

void loop() {
  uint32_t ahoraMs = millis();
  // No se mezcla el borrado remoto con captura/registro ni otras órdenes UART.
  static uint32_t intentoBorradoMs = 0;
  bool borradoRemoto = false;
  if (bioMutex) {
    xSemaphoreTake(bioMutex, portMAX_DELAY);
    String comando = bioComandoId;
    uint16_t slot = bioComandoSlot;
    bool hecho = bioComandoHecho;
    xSemaphoreGive(bioMutex);
    borradoRemoto = comando.length() > 0;
    if (borradoRemoto && !hecho && sensorOK && !enRegistro && ahoraMs - intentoBorradoMs >= 3000) {
      intentoBorradoMs = ahoraMs;
      // deleteModel es idempotente: se exige ACK del sensor, nunca se toma un
      // fallo de comunicación de loadModel como prueba de posición vacía.
      if (huella.deleteModel(slot) == FINGERPRINT_OK) {
        xSemaphoreTake(bioMutex, portMAX_DELAY);
        bioComandoHecho = bioNvs.putString("borrado-ok", comando) == comando.length();
        xSemaphoreGive(bioMutex);
        consultarCapacidad();
        bioEstado("Huella borrada; confirmando en TO-DO");
        if (bioTarea) xTaskNotifyGive(bioTarea);
      } else bioEstado("Borrado pendiente: revisar lector");
    }
  }
  static uint32_t vistaRevision = 0;
  if (bioMutex) {
    xSemaphoreTake(bioMutex, portMAX_DELAY);
    bool cambio = vistaRevision != bioRevision; vistaRevision = bioRevision;
    String estado = bioEstadoRed;
    xSemaphoreGive(bioMutex);
    if (cambio && !enRegistro) {
      marcando = false;
      if (estado.startsWith("Bienvenido, ") || estado.startsWith("Que tengas un excelente")) saludar(estado);
      else actualizarEstado(estado, "Modo " + textoModo() + " / toca E o S");
    }
  }
  bioTelemetria(sensorOK && capacidadValida ? capacidad : -1, sensorOK && contadorValido ? usadas : -1);
  if (!borradoRemoto) {
    procesarSerial();
    leerHuella();
  }
  if (marcando) {
    if (ahoraMs - ultimoRelojMs >= 110) { ultimoRelojMs = ahoraMs; relojFrame(frameReloj++); }
    if (ahoraMs - marcandoMs > 15000) {
      marcando = false;
      interfazCompleta();
      actualizarEstado("Guardada local", "Pendiente de confirmar en TO-DO");
    }
  }
  if (!borradoRemoto && !enRegistro && !saludoHastaMs && !marcando) {
    int tx, ty;
    if (tocarUna(tx, ty)) toqueInicio(tx, ty);
  }

  if (saludoHastaMs && !marcando && ahoraMs > saludoHastaMs) {
    saludoHastaMs = 0;
    interfazCompleta();
  }
  if (!saludoHastaMs && !enRegistro && ahoraMs - ultimaHoraMs >= 10000) {
    ultimaHoraMs = ahoraMs;
    pintarHora();
  }
  if (ahoraMs - ultimoWifiMs >= 3000) {
    ultimoWifiMs = ahoraMs;
    bool wifiConectado = WiFi.status() == WL_CONNECTED;
    if (wifiConectado != ultimoWifiConectado) {
      ultimoWifiConectado = wifiConectado;
      pintarCabecera();
      if (wifiConectado) {
        configTime(-5 * 3600, 0, "pool.ntp.org", "time.google.com");
        Serial.print("WiFi OK, IP: "); Serial.println(WiFi.localIP());
      } else {
        Serial.println("WiFi desconectado. Marcaciones pendientes se conservan.");
      }
    }
  }
  if (!sensorOK && ahoraMs - ultimoReintentoSensorMs >= 10000) {
    ultimoReintentoSensorMs = ahoraMs;
    detectarSensor();
  }
  delay(10);
}
