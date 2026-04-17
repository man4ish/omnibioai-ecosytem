#!/bin/bash
set -e

echo "Starting Ollama server..."
ollama serve &
PID=$!

echo "Waiting for Ollama API..."
until curl -s http://localhost:11434/api/tags >/dev/null; do
  sleep 2
done

echo "Checking models..."

MODELS=(
  "llama3"
  "mistral"
  "deepseek-coder"
  "deepseek-r1"
)

for model in "${MODELS[@]}"; do
  if ollama list | grep -q "$model"; then
    echo "$model already exists, skipping"
  else
    echo "Pulling $model..."
    ollama pull "$model"
  fi
done

echo "Models ready. Server running."

wait $PID