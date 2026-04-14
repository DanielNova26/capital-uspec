import time
import requests
from google import genai

MINIVERSE = "http://127.0.0.1:4321"
AGENT_ID = "gemini"
AGENT_NAME = "Gemini"

client = genai.Client()

def heartbeat(state: str, task: str = ""):
    r = requests.post(
        f"{MINIVERSE}/api/heartbeat",
        json={
            "agent": AGENT_ID,
            "name": AGENT_NAME,
            "state": state,
            "task": task,
        },
        timeout=10,
    )
    print("heartbeat:", state, "-", task, "-", r.status_code)

def read_inbox():
    r = requests.get(
        f"{MINIVERSE}/api/inbox",
        params={"agent": AGENT_ID},
        timeout=10,
    )
    r.raise_for_status()
    data = r.json()
    print("inbox:", data)
    return data.get("messages", [])

def send_message(to: str, message: str):
    r = requests.post(
        f"{MINIVERSE}/api/act",
        json={
            "agent": AGENT_ID,
            "action": {
                "type": "message",
                "to": to,
                "message": message,
            },
        },
        timeout=10,
    )
    print("send:", r.status_code, "to", to)

while True:
    try:
        heartbeat("idle", "Esperando mensajes")
        messages = read_inbox()

        for msg in messages:
            sender = msg.get("from", "unknown")
            text = msg.get("message", "")
            print("mensaje recibido de", sender, ":", text)

            heartbeat("thinking", f"Respondiendo a {sender}")

            response = client.models.generate_content(
                model="gemini-2.5-flash",
                contents=(
                    "Eres Gemini dentro de Miniverse. "
                    "Responde breve, técnica y útil en 5 puntos si aplica. "
                    "No uses relleno. Sé directo.\n\n"
                    f"Mensaje de {sender}: {text}"
                ),
            )

            reply = (response.text or "").strip()
            if not reply:
                reply = "No pude generar respuesta."

            print("respuesta:", reply)
            send_message(sender, reply[:2500])
            heartbeat("idle", "Esperando mensajes")

        time.sleep(8)

    except Exception as e:
        print("ERROR:", repr(e))
        heartbeat("error", str(e)[:100])
        time.sleep(8)
