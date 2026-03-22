#!/usr/bin/env bash
# OmniBioAI Ecosystem — Full Stack Startup
set -e

MACHINE=~/Desktop/machine
NETWORK=machine_default

echo "▶ Starting MySQL and Redis..."
docker start omnibioai-mysql omnibioai-redis 2>/dev/null || true

echo "  Waiting for MySQL..."
until docker exec omnibioai-mysql mysqladmin ping -h 127.0.0.1 -uroot -proot --silent 2>/dev/null; do sleep 2; done
echo "  ✓ MySQL + Redis ready"

echo "▶ Starting ToolServer..."
docker start omnibioai-toolserver 2>/dev/null || true

echo "▶ Starting TES..."
sudo fuser -k 8081/tcp 2>/dev/null || true
docker rm -f omnibioai-tes 2>/dev/null || true
docker run -d --name omnibioai-tes --restart unless-stopped --network $NETWORK \
  -p 8081:8081 -e HOST=0.0.0.0 -e PORT=8081 \
  -e TOOLSERVER_BASE_URL=http://toolserver:9090 \
  -e TES_WORKDIR=/workspace/out/tes_runs \
  -v $MACHINE/omnibioai-tes:/workspace omnibioai-tes \
  bash -lc "omnibioai-tes serve --host 0.0.0.0 --port 8081 \
    --tools /workspace/configs/tools.example.yaml \
    --servers /workspace/configs/servers.local.yaml"

echo "▶ Starting Model Registry..."
docker start omnibioai-model-registry 2>/dev/null || true

echo "▶ Starting LIMS-X..."
docker rm -f lims-x 2>/dev/null || true
docker run -d --name lims-x --restart unless-stopped --network $NETWORK \
  -p 7000:7000 \
  -e DJANGO_SETTINGS_MODULE=lab_data_manager.settings \
  -e MYSQL_HOST=mysql -e MYSQL_PORT=3306 \
  -e MYSQL_DATABASE=limsdb -e MYSQL_USER=root -e MYSQL_PASSWORD=root \
  -e DJANGO_DEBUG=True -e DJANGO_SECRET_KEY=dev-secret \
  -e DJANGO_ALLOWED_HOSTS="127.0.0.1,localhost,lims-x,0.0.0.0" \
  -v $MACHINE:/workspace machine-lims-x:latest \
  bash -lc "python manage.py migrate && python manage.py runserver 0.0.0.0:7000"

# generate report
python omnibioai-control-center/scripts/generate_report.py     --root ~/Desktop/machine

echo "▶ Starting Workbench..."
sudo fuser -k 8001/tcp 2>/dev/null || true
docker rm -f omnibioai-workbench 2>/dev/null || true
docker run -d --name omnibioai-workbench --restart unless-stopped --network $NETWORK \
  -p 8001:8001 \
  -e DJANGO_SETTINGS_MODULE=omnibioai.settings \
  -e OMNIBIOAI_MYSQL_HOST=mysql -e OMNIBIOAI_MYSQL_PORT=3306 \
  -e OMNIBIOAI_MYSQL_DB=omnibioai -e OMNIBIOAI_MYSQL_USER=root \
  -e OMNIBIOAI_MYSQL_PASSWORD=root -e REDIS_HOST=redis -e REDIS_PORT=6379 \
  -e CELERY_BROKER_URL=redis://redis:6379/1 \
  -e CELERY_RESULT_BACKEND=redis://redis:6379/2 \
  -e TES_BASE_URL=http://omnibioai-tes:8081 \
  -e TOOLSERVER_BASE_URL=http://toolserver:9090 \
  -e MODEL_REGISTRY_BASE_URL=http://model-registry:8095 \
  -e WORKSPACE_ROOT=/workspace \
  -v $MACHINE:/workspace -v $MACHINE/data:/workspace/data \
  -v $MACHINE/out:/workspace/out machine-omnibioai:latest \
  bash -lc "cd /workspace/omnibioai && python manage.py migrate --fake && python manage.py runserver 0.0.0.0:8001"

echo "▶ Starting Celery Worker..."
docker rm -f omnibioai-celery-worker 2>/dev/null || true
docker run -d --name omnibioai-celery-worker --restart unless-stopped --network $NETWORK \
  -e DJANGO_SETTINGS_MODULE=omnibioai.settings \
  -e OMNIBIOAI_MYSQL_HOST=mysql -e OMNIBIOAI_MYSQL_USER=root \
  -e OMNIBIOAI_MYSQL_PASSWORD=root -e OMNIBIOAI_MYSQL_DB=omnibioai \
  -e REDIS_HOST=redis -e REDIS_PORT=6379 \
  -e CELERY_BROKER_URL=redis://redis:6379/1 \
  -e CELERY_RESULT_BACKEND=redis://redis:6379/2 \
  -e WORKSPACE_ROOT=/workspace \
  -v $MACHINE:/workspace -v $MACHINE/out:/workspace/out machine-omnibioai:latest \
  bash -lc "cd /workspace/omnibioai && celery -A omnibioai worker -l info"

echo "▶ Starting Control Center..."
docker rm -f omnibioai-control-center 2>/dev/null || true
docker run -d --name omnibioai-control-center --restart unless-stopped --network $NETWORK \
  -p 7070:7070 \
  -e CONTROL_CENTER_CONFIG=/config/control_center.yaml \
  -e WORKSPACE_ROOT=/workspace -e CONTROL_CENTER_PORT=7070 \
  -v $MACHINE:/workspace \
  -v $MACHINE/omnibioai-control-center/config:/config:ro \
  omnibioai-control-center \
  bash -lc "pip install -q --no-cache-dir pytest pytest-cov && \
    pip install -q --no-cache-dir --no-deps \
      -e /workspace/omnibioai-tes \
      -e /workspace/omnibioai-lims \
      -e /workspace/omnibioai-model-registry \
      -e /workspace/omnibioai-toolserver \
      -e /workspace/omnibioai-tool-runtime && \
    pip install -q --no-cache-dir -r /workspace/omnibioai/requirements.txt --no-deps && \
    cd /workspace/omnibioai-control-center/backend && \
    uvicorn control_center.main:app --host 0.0.0.0 --port 7070"

echo ""
sleep 30
echo "════════════════════════════════════"
docker ps --format "  {{.Names}}\t{{.Status}}" | grep -E "omni|lims|toolserver|mysql|redis"
echo ""
echo "  Control Center  → http://localhost:7070"
echo "  Workbench       → http://localhost:8001"
echo "  LIMS-X          → http://localhost:7000/core/"
echo "  TES             → http://localhost:8081"
echo "  ToolServer      → http://localhost:9090"
echo "  Model Registry  → http://localhost:8095"
echo "════════════════════════════════════"
