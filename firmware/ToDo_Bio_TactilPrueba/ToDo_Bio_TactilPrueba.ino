/* TO-DO Bio - PRUEBA DEL TACTIL (solo pantalla + tactil, sin WiFi ni huella).
 * Comprueba el controlador XPT2046 y calibra las 4 esquinas.
 *
 * Pantalla (igual que ToDo_Bio.ino): CS10 DC9 RST8 MOSI11 SCK12, ST7789 240x320, rotacion 1.
 * Tactil (nuevo): T_CLK->GPIO4, T_DIN->GPIO5, T_DO->GPIO6, T_CS->GPIO7, T_IRQ->GPIO15.
 * Biblioteca extra: "XPT2046_Touchscreen" (Paul Stoffregen).
 * Monitor serie a 115200. Al terminar imprime las constantes de calibracion. */
#include <Arduino.h>
#include <SPI.h>
#include <Adafruit_GFX.h>
#include <Adafruit_ST7789.h>
#include <XPT2046_Touchscreen.h>

constexpr int PIN_TFT_CS = 10, PIN_TFT_DC = 9, PIN_TFT_RST = 8, PIN_TFT_MOSI = 11, PIN_TFT_SCLK = 12;
constexpr int PIN_T_CLK = 4, PIN_T_DIN = 5, PIN_T_DO = 6, PIN_T_CS = 7, PIN_T_IRQ = 15;

Adafruit_ST7789 tft(PIN_TFT_CS, PIN_TFT_DC, PIN_TFT_MOSI, PIN_TFT_SCLK, PIN_TFT_RST);
SPIClass touchSPI(HSPI);
XPT2046_Touchscreen ts(PIN_T_CS, PIN_T_IRQ);

constexpr uint16_t BG = 0x0862, CARD = 0x1929, WHITE = 0xFFFF, CYAN = 0x5E9F, GREEN = 0x058F,
                   ORANGE = 0xFD20, RED = 0xE986, MUTED = 0xB5B6;

// Cruces de calibracion (pantalla 320x240): arriba-izq, arriba-der, abajo-izq, abajo-der.
const int16_t OBJ_X[4] = {20, 300, 20, 300};
const int16_t OBJ_Y[4] = {20, 20, 220, 220};
int rawX[4], rawY[4];
bool calibrado = false, intercambiar = false;
float xMin, xMax, yMin, yMax;  // lecturas crudas que corresponden a las cruces

void mensaje(const String &a, const String &b = "", uint16_t color = WHITE) {
  tft.fillRect(40, 80, 240, 80, BG);
  tft.setTextSize(2); tft.setTextColor(color); tft.setCursor(48, 90); tft.print(a);
  tft.setTextSize(1); tft.setTextColor(MUTED); tft.setCursor(48, 125); tft.print(b);
}

void cruz(int16_t x, int16_t y, uint16_t c) {
  tft.drawFastHLine(x - 12, y, 25, c); tft.drawFastVLine(x, y - 12, 25, c); tft.drawCircle(x, y, 7, c);
}

// Espera un toque, promedia mientras esta apoyado y espera a que se suelte.
bool leerToque(int &sx, int &sy, uint32_t timeoutMs) {
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

void calibrar() {
  tft.fillScreen(BG);
  for (int i = 0; i < 4; i++) {
    tft.fillScreen(BG);
    cruz(OBJ_X[i], OBJ_Y[i], CYAN);
    mensaje("Toca la cruz", String(i + 1) + " de 4", WHITE);
    int x, y;
    while (!leerToque(x, y, 60000)) { mensaje("Sin toque", "Revisa cableado / IRQ", ORANGE); delay(500); }
    rawX[i] = x; rawY[i] = y;
    Serial.printf("Cruz %d -> crudo x=%d y=%d\n", i + 1, x, y);
    cruz(OBJ_X[i], OBJ_Y[i], GREEN); delay(300);
  }
  // Si al moverse a la derecha cambia mas el crudo Y que el X, el tactil esta girado.
  intercambiar = abs(rawY[1] - rawY[0]) > abs(rawX[1] - rawX[0]);
  auto h = [&](int i) { return intercambiar ? rawY[i] : rawX[i]; };
  auto v = [&](int i) { return intercambiar ? rawX[i] : rawY[i]; };
  xMin = (h(0) + h(2)) / 2.0f; xMax = (h(1) + h(3)) / 2.0f;
  yMin = (v(0) + v(1)) / 2.0f; yMax = (v(2) + v(3)) / 2.0f;
  calibrado = true;
  Serial.println("--- CALIBRACION (copiala si todo se ve bien) ---");
  Serial.printf("constexpr bool TACTIL_INTERCAMBIAR = %s;\n", intercambiar ? "true" : "false");
  Serial.printf("constexpr float TACTIL_X_MIN = %.0f, TACTIL_X_MAX = %.0f;  // cruces en x=20 y x=300\n", xMin, xMax);
  Serial.printf("constexpr float TACTIL_Y_MIN = %.0f, TACTIL_Y_MAX = %.0f;  // cruces en y=20 y y=220\n", yMin, yMax);
}

bool puntoPantalla(int rx, int ry, int &sx, int &sy) {
  float h = intercambiar ? ry : rx, v = intercambiar ? rx : ry;
  sx = 20 + (h - xMin) * 280.0f / (xMax - xMin);
  sy = 20 + (v - yMin) * 200.0f / (yMax - yMin);
  return sx >= 0 && sx < 320 && sy >= 0 && sy < 240;
}

void dibujo() {
  tft.fillScreen(BG);
  tft.setTextSize(2); tft.setTextColor(WHITE); tft.setCursor(10, 8); tft.print("Dibuja con el dedo");
  tft.fillRoundRect(220, 4, 96, 28, 8, RED); tft.setTextSize(2); tft.setCursor(238, 11); tft.print("Borrar");
  tft.setTextSize(1); tft.setTextColor(MUTED); tft.setCursor(10, 36); tft.print("Toca 'Borrar' para limpiar. Serie: C = recalibrar");
}

void setup() {
  Serial.begin(115200); delay(500);
  Serial.println("\nTO-DO Bio | Prueba de tactil XPT2046");
  tft.init(240, 320); tft.setRotation(1); tft.invertDisplay(false);
  tft.fillScreen(BG);
  touchSPI.begin(PIN_T_CLK, PIN_T_DO, PIN_T_DIN, PIN_T_CS);  // SCK, MISO, MOSI, SS
  ts.begin(touchSPI);
  mensaje("Prueba tactil", "Toca la pantalla para empezar", CYAN);
  int x, y;
  while (!leerToque(x, y, 20000)) {
    Serial.println("Esperando un toque... (si nunca llega: revisa T_IRQ GPIO15 y T_CS GPIO7)");
    mensaje("Prueba tactil", "Toca la pantalla para empezar", CYAN);
  }
  Serial.printf("Primer toque crudo: x=%d y=%d\n", x, y);
  calibrar();
  dibujo();
}

void loop() {
  if (Serial.available()) {
    char c = Serial.read();
    if (c == 'C' || c == 'c') { calibrar(); dibujo(); }
  }
  if (!ts.touched()) { delay(5); return; }
  TS_Point p = ts.getPoint();
  if (p.z < 200) return;
  int sx, sy;
  if (!puntoPantalla(p.x, p.y, sx, sy)) return;
  if (sx > 220 && sy < 34) { dibujo(); delay(300); return; }
  tft.fillCircle(sx, sy, 3, GREEN);
  static uint32_t ultimo = 0;
  if (millis() - ultimo > 200) {
    ultimo = millis();
    Serial.printf("pantalla (%d,%d)  crudo (%d,%d)  presion %d\n", sx, sy, p.x, p.y, p.z);
  }
}
