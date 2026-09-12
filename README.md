# Telo AI

> An experimental personal AI built around transparency, simplicity, and a flow you can actually understand.

Telo AI is a personal AI assistant that connects a mobile app to a self-hosted Qwen3 model running remotely through Kaggle.

It isn't designed to be the most efficient, fastest, or smartest AI out there.

Instead, Telo AI is an experiment in building an AI system where the entire flow is visible and understandable — from the phone, to the API, to the model, and back.

## ✨ Why Telo AI?

Modern AI applications often hide most of what happens behind the scenes.

Telo takes a different approach.

The project is intentionally built as a transparent pipeline:

```text
📱 Android App
      ↓
🌐 Cloudflare Tunnel
      ↓
⚡ FastAPI
      ↓
🧠 Ollama
      ↓
🤖 Qwen3 30B-A3B
      ↓
⚡ Response Stream
      ↓
📱 Telo AI
