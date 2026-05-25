import os
import subprocess
import time
import requests
from dotenv import load_dotenv

load_dotenv()

TOKEN = os.getenv("TELEGRAM_BOT_TOKEN")
CHAT_ID = 234543359
API_URL = f"https://api.telegram.org/bot{TOKEN}"

last_update_id = 0


def send_message(text):
    requests.post(f"{API_URL}/sendMessage", data={
        "chat_id": CHAT_ID,
        "text": text
    })


def run_command(command):
    result = subprocess.run(
        command,
        shell=True,
        cwd="/Volumes/Platinum1TB/SOOM",
        capture_output=True,
        text=True
    )
    return result.stdout.strip() or result.stderr.strip()


send_message("SOOM 자동화 봇 실행 중 ✅")


while True:
    try:
        response = requests.get(f"{API_URL}/getUpdates", params={
            "offset": last_update_id + 1,
            "timeout": 20
        })

        data = response.json()

        for update in data.get("result", []):
            last_update_id = update["update_id"]

            message = update.get("message", {})
            chat = message.get("chat", {})
            text = message.get("text", "")

            if chat.get("id") != CHAT_ID:
                continue

            if text == "/status":
                output = run_command("git status --short --branch")
                send_message(f"[SOOM Git Status]\n{output}")

            elif text == "/help":
                send_message(
                    "SOOM 명령어\n"
                    "/status - Git 상태 확인\n"
                    "/help - 명령어 보기"
                )

            else:
                send_message("알 수 없는 명령어입니다. /help 를 입력해줘.")

    except Exception as e:
        send_message(f"Bot error: {e}")

    time.sleep(2)
