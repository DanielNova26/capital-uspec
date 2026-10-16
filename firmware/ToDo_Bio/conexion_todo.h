#pragma once
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <Preferences.h>
#include <ArduinoJson.h>
#include <esp_sntp.h>
#include "tls_roots.h"

// 32 eventos persistentes; nunca sobreescribir un evento para liberar espacio.
constexpr int BIO_COLA_MAX = 32;
Preferences bioNvs;
SemaphoreHandle_t bioMutex = nullptr;
bool bioStorageOK = false;
volatile bool bioHoraSincronizada = false;
int bioCapacidad = -1, bioUsadas = -1;
String bioEstadoRed = "Sin conexion con TO-DO";
String bioNombreRespuesta = "";  // Nombre devuelto por el servidor al confirmar una marcacion.
uint32_t bioRevision = 0;
TaskHandle_t bioTarea = nullptr;  // se despierta al encolar una marcacion
String bioComandoId = "";
uint16_t bioComandoSlot = 0;
bool bioComandoHecho = false;

// La tarea de red entrega la orden; solo loop() puede usar la UART del sensor.
void bioRecibirComando(JsonDocument& response) {
  if (String((const char*)(response["comando"]["tipo"] | "")) != "eliminarHuella") return;
  String id = response["comando"]["id"] | "";
  int slot = response["comando"]["slot"] | 0;
  if (!id.length() || id.length() > 160 || slot < 1 || slot > 65535) return;
  xSemaphoreTake(bioMutex, portMAX_DELAY);
  if (!bioComandoId.length()) {
    bioComandoId = id; bioComandoSlot = slot;
    // Un ACK perdido o reinicio nunca vuelve a borrar una posición ya reutilizada.
    bioComandoHecho = bioNvs.getString("borrado-ok", "") == id;
  }
  xSemaphoreGive(bioMutex);
}

void bioTimeSync(struct timeval*) { bioHoraSincronizada = true; }
String bioKey(int i) { return "e" + String(i); }
void bioEstado(const String& text) {
  xSemaphoreTake(bioMutex, portMAX_DELAY);
  bioEstadoRed = text; bioRevision++;
  xSemaphoreGive(bioMutex);
}
bool bioConfigurado() {
  return strlen(TODO_DEVICE_ID) > 0 && strlen(TODO_API_TOKEN) == 68 &&
    String(TODO_API_TOKEN).startsWith("tdb_") &&
    String(TODO_API_URL) == "https://us-central1-integra360-94704.cloudfunctions.net/biometricoDispositivo";
}
bool bioEncolar(uint16_t slot, const String& tipo) {
  if (!bioStorageOK || !bioConfigurado() || !bioHoraSincronizada || time(nullptr) < 1767225600) return false;
  JsonDocument doc;
  doc["accion"] = "marcacion"; doc["deviceId"] = TODO_DEVICE_ID;
  char eventId[40];
  snprintf(eventId, sizeof(eventId), "%08lx%08lx%08lx%08lx",
    (unsigned long)esp_random(), (unsigned long)esp_random(), (unsigned long)esp_random(), (unsigned long)esp_random());
  doc["eventoId"] = eventId; doc["slot"] = slot; doc["tipo"] = tipo;
  struct timeval captured;
  gettimeofday(&captured, nullptr);
  doc["capturadoMs"] = (int64_t)captured.tv_sec * 1000LL + captured.tv_usec / 1000;
  String payload; serializeJson(doc, payload);
  bool saved = false;
  xSemaphoreTake(bioMutex, portMAX_DELAY);
  for (int i = 0; i < BIO_COLA_MAX; i++) {
    const String key = bioKey(i);
    if (!bioNvs.isKey(key.c_str())) {
      saved = bioNvs.putString(key.c_str(), payload) == payload.length();
      break;
    }
  }
  xSemaphoreGive(bioMutex);
  if (saved && bioTarea) xTaskNotifyGive(bioTarea);
  return saved;
}
int bioPost(const String& payload) {
  WiFiClientSecure tls;
  tls.setCACert(TODO_ROOT_CA); // Certificado y hostname verificados. Nunca setInsecure.
  tls.setHandshakeTimeout(10);
  HTTPClient http;
  http.setConnectTimeout(8000); http.setTimeout(10000);
  http.setFollowRedirects(HTTPC_DISABLE_FOLLOW_REDIRECTS);
  if (!http.begin(tls, TODO_API_URL)) return -1;
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Authorization", String("Bearer ") + TODO_API_TOKEN);
  bioNombreRespuesta = "";
  int code = http.POST(payload);
  if (code == 200 || code == 201) {
    JsonDocument response;
    if (deserializeJson(response, http.getString()) || response["ok"] != true) code = -2;
    else {
      bioNombreRespuesta = String((const char*)(response["nombre"] | ""));
      bioRecibirComando(response);
    }
  }
  http.end(); return code;
}
// Llamada sincronica (registro en pantalla): devuelve el codigo HTTP y el JSON de respuesta.
// No toca el estado de la cola ni el nombre de la ultima marcacion.
int bioLlamar(const String& payload, JsonDocument& respuesta) {
  WiFiClientSecure tls;
  tls.setCACert(TODO_ROOT_CA);
  tls.setHandshakeTimeout(10);
  HTTPClient http;
  http.setConnectTimeout(8000); http.setTimeout(10000);
  http.setFollowRedirects(HTTPC_DISABLE_FOLLOW_REDIRECTS);
  if (!http.begin(tls, TODO_API_URL)) return -1;
  http.addHeader("Content-Type", "application/json");
  http.addHeader("Authorization", String("Bearer ") + TODO_API_TOKEN);
  int code = http.POST(payload);
  if (code > 0) deserializeJson(respuesta, http.getString());
  http.end(); return code;
}
void bioRedTask(void*) {
  uint32_t lastHeartbeat = 0;
  uint32_t delayMs = 2000;
  int cursor = 0;
  for (;;) {
    ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(delayMs));  // espera, o sale antes si hay marcacion nueva
    if (!bioStorageOK || !bioConfigurado() || WiFi.status() != WL_CONNECTED || !bioHoraSincronizada) continue;
    xSemaphoreTake(bioMutex, portMAX_DELAY);
    String confirmado = bioComandoHecho ? bioComandoId : "";
    xSemaphoreGive(bioMutex);
    if (confirmado.length()) {
      JsonDocument ack; ack["accion"] = "confirmarBorrado"; ack["deviceId"] = TODO_DEVICE_ID; ack["comandoId"] = confirmado;
      String body; serializeJson(ack, body);
      if (bioPost(body) == 200) {
        xSemaphoreTake(bioMutex, portMAX_DELAY);
        bioComandoId = ""; bioComandoHecho = false;
        xSemaphoreGive(bioMutex);
        bioEstado("Huella eliminada en lector y TO-DO");
      }
    }
    int index = -1; String payload; bool rejected = false;
    xSemaphoreTake(bioMutex, portMAX_DELAY);
    for (int j = 0; j < BIO_COLA_MAX; j++) {
      const int i = (cursor + j) % BIO_COLA_MAX;
      String stored = bioNvs.getString(bioKey(i).c_str(), "");
      if (!stored.length()) continue;
      JsonDocument doc;
      if (deserializeJson(doc, stored) || !doc["rechazo"].isNull()) { rejected = true; continue; }
      index = i; payload = stored; cursor = (i + 1) % BIO_COLA_MAX; break;
    }
    xSemaphoreGive(bioMutex);
    if (index >= 0) {
      int code = bioPost(payload);
      if (code == 200 || code == 201) {
        xSemaphoreTake(bioMutex, portMAX_DELAY);
        bool removed = bioNvs.remove(bioKey(index).c_str());
        xSemaphoreGive(bioMutex);
        JsonDocument sent; deserializeJson(sent, payload);
        const bool entrada = String((const char*)(sent["tipo"] | "")) == "ENTRADA";
        if (!removed) bioEstado("Recibida; reintentando limpieza local");
        else if (bioNombreRespuesta.length()) bioEstado((entrada ? "Bienvenido, " : "Que tengas un excelente dia, ") + bioNombreRespuesta);
        else bioEstado("Marcacion confirmada en TO-DO");
        delayMs = 2000;
      } else if (code == 400 || code == 409 || code == 422) {
        JsonDocument doc; deserializeJson(doc, payload); doc["rechazo"] = code;
        String retained; serializeJson(doc, retained);
        xSemaphoreTake(bioMutex, portMAX_DELAY);
        bioNvs.putString(bioKey(index).c_str(), retained);
        xSemaphoreGive(bioMutex);
        bioEstado("Rechazo " + String(code) + ": revisar Q en serie"); delayMs = 5000;
      } else {
        bioEstado(code == 401 ? "Token revocado o de otro equipo" : "Sin confirmar; cola conservada");
        delayMs = delayMs >= 30000UL ? 60000UL : delayMs * 2UL;
      }
    } else {
      delayMs = 3000;
      if (rejected) bioEstado("Hay rechazos guardados. Serie: Q");
    }
    if (!lastHeartbeat || millis() - lastHeartbeat >= 15000) {
      lastHeartbeat = millis();
      JsonDocument doc; doc["accion"] = "heartbeat"; doc["deviceId"] = TODO_DEVICE_ID; doc["firmware"] = "ToDo-Bio-2.4.0";
      xSemaphoreTake(bioMutex, portMAX_DELAY);
      if (bioCapacidad < 0) doc["capacidad"] = nullptr; else doc["capacidad"] = bioCapacidad;
      if (bioUsadas < 0) doc["usadas"] = nullptr; else doc["usadas"] = bioUsadas;
      xSemaphoreGive(bioMutex);
      String body; serializeJson(doc, body); int code = bioPost(body);
      if (code == 401) bioEstado("Token revocado o de otro equipo");
      else if (code == 200 && index < 0 && !rejected) bioEstado("TO-DO conectado");
    }
  }
}
void bioIniciar() {
  bioMutex = xSemaphoreCreateMutex();
  if (!bioMutex) return;
  bioStorageOK = bioNvs.begin("todo-bio-v2", false);
  sntp_set_time_sync_notification_cb(bioTimeSync);
  if (xTaskCreate(bioRedTask, "bio-red", 16384, nullptr, 1, &bioTarea) != pdPASS) {
    bioStorageOK = false;
    bioEstado("No se pudo iniciar conexion");
  }
}
void bioTelemetria(int capacidad, int usadas) {
  if (!bioMutex) return;
  xSemaphoreTake(bioMutex, portMAX_DELAY);
  bioCapacidad = capacidad; bioUsadas = usadas;
  xSemaphoreGive(bioMutex);
}
void bioColaSerial(bool reintentar = false) {
  if (!bioMutex || !bioStorageOK) { Serial.println("Cola no disponible"); return; }
  xSemaphoreTake(bioMutex, portMAX_DELAY);
  int total = 0;
  for (int i = 0; i < BIO_COLA_MAX; i++) {
    String s = bioNvs.getString(bioKey(i).c_str(), "");
    if (!s.length()) continue;
    total++;
    if (reintentar) {
      JsonDocument doc;
      if (!deserializeJson(doc, s) && !doc["rechazo"].isNull()) {
        doc.remove("rechazo"); s = ""; serializeJson(doc, s); bioNvs.putString(bioKey(i).c_str(), s);
      }
    }
    Serial.println(s); // Sin tokens ni plantillas; exporta eventos pendientes para conciliacion.
  }
  Serial.printf("Cola: %d/%d. No borres NVS sin conciliar estos eventos.\n", total, BIO_COLA_MAX);
  xSemaphoreGive(bioMutex);
}
