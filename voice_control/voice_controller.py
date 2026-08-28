
import os
os.environ["VOSK_LOG_LEVEL"] = "0"

import json
import difflib
import speech_recognition as sr
from vosk import Model, KaldiRecognizer
import socket

# ================== CONFIG ==================
MODEL_PATH = r"C:\CollaborativeRobotics\vosk_models\vosk-model-small-en-us-0.15"
RATE = 16000

commands = ['up', 'down', 'stop', 'start']
poses    = ['yellow', 'blue', 'green']
VOCAB    = commands + poses
# ============================================

# -------- Arduino connection --------
ip = '192.168.4.1'
port = 80

conn = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
conn.connect((ip, port))
print("Connected to Arduino\n")
# -----------------------------------

print(f"Loading model from: {MODEL_PATH}")
model = Model(MODEL_PATH)
print("Model loaded successfully.\n")

r = sr.Recognizer()
mic = sr.Microphone()

print("Ready. Say a command: up, down, stop, start, yellow, blue, green")
print("CTRL+C to quit.\n")

while True:
    # ----- Capture speech -----
    with mic as source:
        print("\nAdjusting for ambient noise...")
        r.adjust_for_ambient_noise(source, duration=0.5)
        print("Speak now:")
        audio = r.listen(source)

    # ----- Convert audio to raw PCM -----
    raw = audio.get_raw_data(convert_rate=RATE, convert_width=2)

    # ----- Vosk recognition -----
    rec = KaldiRecognizer(model, RATE)
    rec.AcceptWaveform(raw)
    result = rec.FinalResult()

    try:
        j = json.loads(result)
        text = j.get("text", "").strip()
    except:
        text = ""

    if not text:
        print("No speech recognized.")
        continue

    print("TEXT:", repr(text))

    # ----- Match command -----
    candidates = difflib.get_close_matches(text, VOCAB, n=1, cutoff=0.4)

    if not candidates:
        print("No valid command found.")
        continue

    cmd = candidates[0]
    print(f"COMMAND RECOGNIZED: {cmd}")

    # ----- Send to Arduino -----
    conn.send(cmd.encode())
    response = conn.recv(1024).decode()
    print("Arduino:", response)
