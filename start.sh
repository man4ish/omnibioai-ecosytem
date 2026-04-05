#!/usr/bin/env bash
# =============================================================================
# OmniBioAI Ecosystem — Full Stack Startup Script
# Usage: bash start.sh
# =============================================================================
set -e

# ── Load environment variables ────────────────────────────────────────────────
ENV_FILE="$(dirname "$0")/.env"
if [[ -f "$ENV_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    echo "  ✓ Loaded environment from .env"
else
    echo "  ⚠ No .env file found — using defaults (create .env to override)"
fi

# ── Configuration (with defaults) ────────────────────────────────────────────
MACHINE="${MACHINE_ROOT:-$HOME/Desktop/machine}"
NETWORK="${DOCKER_NETWORK:-compose_default}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-root}"
MYSQL_DEFAULT_DB="${MYSQL_DEFAULT_DB:-omnibioai}"
MYSQL_USER="${MYSQL_USER:-root}"
REDIS_HOST="${REDIS_HOST:-redis}"
REDIS_PORT="${REDIS_PORT:-6379}"
DJANGO_SECRET_KEY="${DJANGO_SECRET_KEY:-dev-secret-change-in-production}"

echo ""
echo "════════════════════════════════════════════════════════"
echo "  OmniBioAI Ecosystem — Starting all services"
echo "════════════════════════════════════════════════════════"

# ── Helper: free a port without sudo ─────────────────────────────────────────
free_port() {
    local port=$1
    local containers
    containers=$(docker ps --format "{{.Names}}" 2>/dev/null)
    for container in $containers; do
        if docker port "$container" 2>/dev/null | grep -q ":${port}->"; then
            echo "  → Removing container '$container' using port $port"
            docker rm -f "$container" 2>/dev/null || true
        fi
    done
}

# ── Step 0: Ollama ────────────────────────────────────────────────────────────
echo ""
echo "▶ [0/8] Starting Ollama (listening on 0.0.0.0:11434)..."
pkill ollama 2>/dev/null || true
sleep 1
OLLAMA_HOST=0.0.0.0:11434 ollama serve > /tmp/ollama.log 2>&1 &
sleep 3
if ss -tlnp | grep -q "11434"; then
    echo "  ✓ Ollama running on 0.0.0.0:11434"
else
    echo "  ⚠ Ollama may not have started — check /tmp/ollama.log"
fi

# ── Step 1: Core infrastructure ───────────────────────────────────────────────
echo ""
echo "▶ [1/8] Starting MySQL and Redis..."
docker start omnibioai-mysql omnibioai-redis 2>/dev/null || true

echo "  Waiting for MySQL to be ready..."
until docker exec omnibioai-mysql mysqladmin ping \
    -h 127.0.0.1 -u"$MYSQL_USER" -p"$MYSQL_ROOT_PASSWORD" \
    --silent 2>/dev/null; do
    sleep 2
done
echo "  ✓ MySQL ready"
echo "  ✓ Redis ready"

# ── Step 2: ToolServer ────────────────────────────────────────────────────────
echo ""
echo "▶ [2/8] Starting ToolServer (port 9090)..."
docker start omnibioai-toolserver 2>/dev/null || true
echo "  ✓ ToolServer starting"

# ── Step 3: TES ───────────────────────────────────────────────────────────────
echo ""
echo "▶ [3/8] Starting TES (port 8081)..."
free_port 8081
docker rm -f omnibioai-tes 2>/dev/null || true
docker run -d \
    --name omnibioai-tes \
    --restart unless-stopped \
    --network "$NETWORK" \
    -p 8081:8081 \
    -e HOST=0.0.0.0 \
    -e PORT=8081 \
    -e TOOLSERVER_BASE_URL=http://toolserver:9090 \
    -e TES_WORKDIR=/workspace/out/tes_runs \
    -v "$MACHINE/omnibioai-tes":/workspace \
    omnibioai-tes \
    bash -lc "omnibioai-tes serve \
        --host 0.0.0.0 --port 8081 \
        --tools /workspace/configs/tools.example.yaml \
        --servers /workspace/configs/servers.local.yaml"
echo "  ✓ TES starting"

# ── Step 4: Model Registry ────────────────────────────────────────────────────
echo ""
echo "▶ [4/8] Starting Model Registry (port 8095)..."
docker start omnibioai-model-registry 2>/dev/null || true
echo "  ✓ Model Registry starting"

# ── Step 5: LIMS-X ───────────────────────────────────────────────────────────
echo ""
echo "▶ [5/8] Starting LIMS-X (port 7000)..."
docker rm -f lims-x 2>/dev/null || true
docker run -d \
    --name lims-x \
    --restart unless-stopped \
    --network "$NETWORK" \
    -p 7000:7000 \
    -e DJANGO_SETTINGS_MODULE=lab_data_manager.settings \
    -e MYSQL_HOST=mysql \
    -e MYSQL_PORT=3306 \
    -e MYSQL_DATABASE=limsdb \
    -e MYSQL_USER="$MYSQL_USER" \
    -e MYSQL_PASSWORD="$MYSQL_ROOT_PASSWORD" \
    -e DJANGO_DEBUG=True \
    -e DJANGO_SECRET_KEY="$DJANGO_SECRET_KEY" \
    -e DJANGO_ALLOWED_HOSTS="127.0.0.1,localhost,lims-x,0.0.0.0" \
    -v "$MACHINE/omnibioai-lims":/app \
    -v "$MACHINE":/workspace \
    machine-lims-x:latest \
    bash -lc "cd /app && python manage.py migrate && python manage.py runserver 0.0.0.0:7000"
echo "  ✓ LIMS-X starting"

# ── Step 6: OmniBioAI Workbench ───────────────────────────────────────────────
echo ""
echo "▶ [6/8] Starting OmniBioAI Workbench (port 8001)..."
free_port 8001
docker rm -f omnibioai-workbench 2>/dev/null || true
docker run -d \
    --name omnibioai-workbench \
    --restart unless-stopped \
    --network "$NETWORK" \
    -p 8001:8001 \
    -e DJANGO_SETTINGS_MODULE=omnibioai.settings \
    -e DB_HOST=mysql \
    -e DB_PORT=3306 \
    -e DB_NAME="$MYSQL_DEFAULT_DB" \
    -e DB_USER="$MYSQL_USER" \
    -e DB_PASSWORD="$MYSQL_ROOT_PASSWORD" \
    -e REDIS_HOST="$REDIS_HOST" \
    -e REDIS_PORT="$REDIS_PORT" \
    -e CELERY_BROKER_URL="redis://$REDIS_HOST:$REDIS_PORT/1" \
    -e CELERY_RESULT_BACKEND="redis://$REDIS_HOST:$REDIS_PORT/2" \
    -e TES_BASE_URL=http://omnibioai-tes:8081 \
    -e TOOLSERVER_BASE_URL=http://toolserver:9090 \
    -e MODEL_REGISTRY_BASE_URL=http://model-registry:8095 \
    -e OLLAMA_HOST=http://172.17.0.1:11434 \
    -e WORKSPACE_ROOT=/workspace \
    -v "$MACHINE/omnibioai":/app \
    -v "$MACHINE":/workspace \
    -v "$MACHINE/data":/workspace/data \
    -v "$MACHINE/out":/workspace/out \
    machine-omnibioai:latest \
    bash -lc "cd /app && \
        python manage.py migrate --fake && \
        python manage.py runserver 0.0.0.0:8001"
echo "  ✓ Workbench starting"

# ── Step 7: Celery Worker ─────────────────────────────────────────────────────
echo ""
echo "▶ [7/8] Starting Celery Worker..."
docker rm -f omnibioai-celery-worker 2>/dev/null || true
docker run -d \
    --name omnibioai-celery-worker \
    --restart unless-stopped \
    --network "$NETWORK" \
    -e DJANGO_SETTINGS_MODULE=omnibioai.settings \
    -e DB_HOST=mysql \
    -e DB_PORT=3306 \
    -e DB_NAME="$MYSQL_DEFAULT_DB" \
    -e DB_USER="$MYSQL_USER" \
    -e DB_PASSWORD="$MYSQL_ROOT_PASSWORD" \
    -e REDIS_HOST="$REDIS_HOST" \
    -e REDIS_PORT="$REDIS_PORT" \
    -e CELERY_BROKER_URL="redis://$REDIS_HOST:$REDIS_PORT/1" \
    -e CELERY_RESULT_BACKEND="redis://$REDIS_HOST:$REDIS_PORT/2" \
    -e OLLAMA_HOST=http://172.17.0.1:11434 \
    -e WORKSPACE_ROOT=/workspace \
    -v "$MACHINE/omnibioai":/app \
    -v "$MACHINE":/workspace \
    -v "$MACHINE/out":/workspace/out \
    machine-omnibioai:latest \
    bash -lc "cd /app && celery -A omnibioai worker -l info"
echo "  ✓ Celery Worker starting"

# ── Step 8: Control Center ────────────────────────────────────────────────────
echo ""
echo "▶ [8/8] Starting Control Center (port 7070)..."
docker rm -f omnibioai-control-center 2>/dev/null || true
docker run -d \
    --name omnibioai-control-center \
    --restart unless-stopped \
    --network "$NETWORK" \
    -p 7070:7070 \
    -e CONTROL_CENTER_CONFIG=/config/control_center.yaml \
    -e WORKSPACE_ROOT=/workspace \
    -e CONTROL_CENTER_PORT=7070 \
    -e PYTHONPATH=/workspace/omnibioai-control-center/backend/src \
    -v "$MACHINE":/workspace \
    -v "$MACHINE/omnibioai-control-center/config":/config:ro \
    omnibioai-control-center \
    bash -lc "
        pip install -q --no-cache-dir pytest pytest-cov && \
        pip install -q --no-cache-dir --no-deps \
            -e /workspace/omnibioai-tes \
            -e /workspace/omnibioai-lims \
            -e /workspace/omnibioai-model-registry \
            -e /workspace/omnibioai-toolserver \
            -e /workspace/omnibioai-tool-runtime && \
        pip install -q --no-cache-dir \
            -r /workspace/omnibioai/requirements.txt --no-deps && \
        cd /workspace/omnibioai-control-center/backend && \
        uvicorn control_center.main:app --host 0.0.0.0 --port 7070
    "
echo "  ✓ Control Center starting (installing deps, ~30s)"

# ── Generate ecosystem report ─────────────────────────────────────────────────
echo ""
echo "▶ Generating ecosystem report..."
python "$MACHINE/omnibioai-control-center/scripts/generate_report.py" \
    --root "$MACHINE" 2>/dev/null && \
    echo "  ✓ Report generated" || \
    echo "  ⚠ Report generation skipped"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "  Waiting 30s for services to initialize..."
sleep 30

echo ""
echo "════════════════════════════════════════════════════════"
echo "  Service Status:"
echo "────────────────────────────────────────────────────────"
docker ps --format "  {{.Names}}\t{{.Status}}" \
    | grep -E "omni|lims|toolserver|mysql|redis" \
    | sort
echo ""
echo "  URLs:"
echo "────────────────────────────────────────────────────────"
echo "  Control Center  →  http://localhost:7070"
echo "  Workbench       →  http://localhost:8001"
echo "  LIMS-X          →  http://localhost:7000/core/"
echo "  TES             →  http://localhost:8081"
echo "  ToolServer      →  http://localhost:9090"
echo "  Model Registry  →  http://localhost:8095"
echo "  Ollama          →  http://localhost:11434"
echo "════════════════════════════════════════════════════════"