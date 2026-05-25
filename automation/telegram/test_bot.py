import os
import requests
from dotenv import load_dotenv

load_dotenv()

TOKEN = os.getenv("TELEGRAM_BOT_TOKEN")

url = f"https://api.telegram.org/bot{TOKEN}/getMe"

response = requests.get(url)

print(response.json())
