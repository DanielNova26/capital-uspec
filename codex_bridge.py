import time
import subprocess
import requests

MINIVERSE = "http://127.0.0.1:4321"
AGENT_ID = "codex"
AGENT_NAME = "Codex"
CODEX_CMD = r"C:\Users\SERVICIO TECNICO\AppData\Roaming\npm\codex.cmd"

def heartbeat(state: str, task: str = ""):
    try:
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
    except Exception as e:
        print("heartbeat error:", repr(e))

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

def clean_text(text: str) -> str:
    text = text.replace("\r", " ").replace("\n", " ")
    text = text.replace('"', "'")
    text = text.replace("\ufffd", "?")
    return text

while True:
    try:
        heartbeat("idle", "Esperando mensajes")
        messages = read_inbox()

        for msg in messages:
            sender = msg.get("from", "unknown")
            text = clean_text(msg.get("message", ""))
            print("mensaje recibido de", sender, ":", text)

            heartbeat("working", f"Respondiendo a {sender}")

            prompt = (
                "Eres Codex dentro de Miniverse. "
                "Responde breve, tecnica y accionable. "
                "Si te piden implementacion, menciona archivos, pasos y comandos. "
                "No uses relleno. "
                f"Mensaje de {sender}: {text}"
            )

            command = subprocess.list2cmdline([
                CODEX_CMD,
                "exec",
                "--skip-git-repo-check",
                prompt,
            ])

            result = subprocess.run(
                command,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                cwd=r"C:\IA\miniverse-lab\my-miniverse",
                shell=True,
            )

            reply = (result.stdout or result.stderr or "").strip()
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
