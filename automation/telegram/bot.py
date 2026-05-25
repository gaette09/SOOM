import os
import re
import subprocess
import time
import requests
from dotenv import load_dotenv

load_dotenv()

TOKEN = os.getenv("TELEGRAM_BOT_TOKEN")
CHAT_ID = 234543359
PROJECT_ROOT = "/Volumes/Platinum1TB/SOOM"
API_URL = f"https://api.telegram.org/bot{TOKEN}"

last_update_id = 0


def send_message(text):
    if len(text) > 3500:
        text = text[:3500] + "\n\n...메시지가 길어서 일부만 표시했습니다."
    requests.post(f"{API_URL}/sendMessage", data={
        "chat_id": CHAT_ID,
        "text": text
    })


def run_command(command):
    result = subprocess.run(
        command,
        shell=True,
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=True
    )
    return result.stdout.strip() or result.stderr.strip()


def run_args(args):
    result = subprocess.run(
        args,
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=True
    )
    return result.stdout.strip() or result.stderr.strip()


def make_task_name(text):
    cleaned = re.sub(r"[^a-zA-Z0-9가-힣\s-]", "", text)
    words = cleaned.strip().split()
    if not words:
        return "telegram-task"
    short = "-".join(words[:4])
    return short.lower()


def run_soom_task(goal, dry_run=False):
    task_name = make_task_name(goal)

    send_message(f"SOOM task 생성 중...\n{task_name}")

    create_output = run_args([
        "./scripts/soom-task.sh",
        task_name,
        goal
    ])

    send_message(f"Task 생성 완료 ✅\n\n{create_output}")

    if dry_run:
        send_message("Codex dry-run 실행 중...")
        run_output = run_command("./scripts/run-latest-task.sh --dry")
    else:
        send_message("Codex 실행 중... 시간이 걸릴 수 있습니다.")
        run_output = run_command("./scripts/run-latest-task.sh")

    latest_result = run_command("find tasks/results -name '*.md' | sort | tail -1")
    result_content = run_command(f"cat {latest_result}") if latest_result else "결과 파일을 찾지 못했습니다."

    send_message(
        "SOOM 작업 완료 ✅\n\n"
        f"Result file:\n{latest_result}\n\n"
        f"{result_content}"
    )


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
            text = message.get("text", "").strip()

            if chat.get("id") != CHAT_ID:
                continue

            if text == "/status":
                output = run_command("git status --short --branch")
                send_message(f"[SOOM Git Status]\n{output}")

            elif text == "/help":
                send_message(
                    "SOOM 명령어\n"
                    "/status - Git 상태 확인\n"
                    "/help - 명령어 보기\n"
                    "/soom 작업내용 - SOOM task 생성 후 Codex 실행\n"
                    "/soomdry 작업내용 - SOOM task 생성 후 dry-run 실행"
                )

            elif text.startswith("/soomdry "):
                goal = text.replace("/soomdry ", "", 1).strip()
                if goal:
                    run_soom_task(goal, dry_run=True)
                else:
                    send_message("사용법: /soomdry 작업내용")

            elif text.startswith("/soom "):
                goal = text.replace("/soom ", "", 1).strip()
                if goal:
                    run_soom_task(goal, dry_run=False)
                else:
                    send_message("사용법: /soom 작업내용")

            else:
                send_message("알 수 없는 명령어입니다. /help 를 입력해줘.")

    except Exception as e:
        send_message(f"Bot error: {e}")

    time.sleep(2)
