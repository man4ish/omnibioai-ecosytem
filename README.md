# OmniBioAI Ecosystem

## Reproducible Scientific Execution & AI-Powered Bioinformatics

OmniBioAI is a **modular, AI-powered bioinformatics workbench** designed to accelerate genomic research across:

- Local machines
- On-prem servers
- HPC environments (Slurm, Apptainer)
- Cloud infrastructure (AWS Batch, Azure Batch, Kubernetes)

With **no mandatory cloud dependencies**.

> This repository is the **workspace root** of the OmniBioAI ecosystem — it assembles independently versioned components into a single runnable, production-grade stack.

---

## Architecture

OmniBioAI follows a **four-plane architecture**:

| Plane | Role | Key Components |
|-------|------|----------------|
| **Control** | Orchestration, governance, APIs | Workbench, TES, ToolServer, Model Registry, LIMS |
| **Compute** | Ephemeral execution | Workflow runners, tool runtime containers, HPC adapters |
| **Data** | Artifacts, outputs, versioning | OmniObjects, model artifacts, workflow outputs |
| **AI** | Reasoning, retrieval, agents | RAG services, LLM integration, agent orchestration |

TES (Tool Execution Service) is the strict boundary between the control and compute planes.

---

## Workspace Layout

```text
Desktop/machine/
│
├── omnibioai/                     # Workbench — Django platform, plugins, agents
├── omnibioai-tes/                 # Tool Execution Service — HPC/cloud/local execution
├── omnibioai-toolserver/          # FastAPI ToolServer — validated async tool APIs
├── omnibioai-tool-runtime/        # Minimal cloud-agnostic container execution runtime
├── omnibioai-model-registry/      # Production model registry — versioning, provenance
├── omnibioai-lims/                # Lightweight Django LIMS — samples, metadata
├── omnibioai-rag/                 # RAG assistant — Hugging Face + Ollama LLMs
├── omnibioai_sdk/                 # Python SDK — API, object registry, notebooks
├── omnibioai-workflow-bundles/    # Engine-agnostic workflows — WDL, Nextflow, Snakemake, CWL
├── omnibioai-dev-docker/          # GPU dev environment — CUDA, JupyterLab, Ollama
├── omnibioai-control-center/      # Health dashboard, ecosystem report, orchestration
│
├── deploy/
│   ├── compose/                   # Canonical Docker Compose files
│   ├── control-center/            # Control Center runtime (moved to omnibioai-control-center)
│   ├── scripts/                   # Bootstrap utilities
│   ├── bundle/                    # Offline image bundles
│   ├── hpc/                       # Apptainer / Singularity assets
│   └── k8s/                       # Kubernetes (post-beta)
│
├── db-init/                       # Database initialisation scripts
├── data/                          # Runtime data volumes
├── local_registry/                # Local model artifact storage
├── tmpdata/                       # Temporary execution workspace
├── out/                           # Report and analysis outputs
│   └── reports/
│       └── omnibioai_ecosystem_report.html   # Generated ecosystem report
│
├── utils/                         # Shared utilities
├── images/                        # Container image assets
└── README.md
```

---

## Services

| Service | Port | Role |
|---------|------|------|
| OmniBioAI Workbench | 8000 | UI, plugins, agents, AI tools |
| Tool Execution Service (TES) | 8081 | Workflow and tool orchestration |
| ToolServer | 9090 | Validated async tool APIs |
| Model Registry | 8095 | Versioned ML model artifacts |
| LIMS | 7000 | Sample and metadata management |
| Control Center | 7070 | Health dashboard, ecosystem report |
| MySQL | 3306 | Relational databases |
| Redis | 6379 | Celery task queue and caching |

All ports are configurable via `.env`.

---

## Quick Start

### Prerequisites

- Docker Engine or Docker Desktop
- Docker Compose v2+
- Python 3.11+ (for report generation)

### Start the Full Stack

```bash
cp deploy/compose/.env.example deploy/compose/.env

docker compose \
  --project-directory . \
  --env-file deploy/compose/.env \
  -f deploy/compose/docker-compose.yml \
  up -d
```

### Verify Core Services

```bash
curl http://127.0.0.1:8000          # Workbench
curl http://127.0.0.1:8081/health   # TES
curl http://127.0.0.1:9090/health   # ToolServer
curl http://127.0.0.1:8095/health   # Model Registry
curl http://127.0.0.1:7070/health   # Control Center
curl http://127.0.0.1:7070/summary  # Ecosystem health summary (JSON)
```

### Start the Control Center

```bash
docker compose \
  --project-directory . \
  -f omnibioai-control-center/compose/docker-compose.control-center.yml \
  up -d
```

---

## Ecosystem Report

The ecosystem report is a single interactive HTML file covering:

- **Architecture** — SVG lane diagram of all services and their connections
- **Projects** — Code line distribution across all repositories
- **Languages** — Language breakdown across the ecosystem
- **Code Coverage** — Per-repo pytest coverage with trend indicators
- **Health Status** — Live service and disk health from the Control Center

### Generate the Report

```bash
# With Control Center running (includes live health data)
python omnibioai-control-center/scripts/generate_report.py \
    --root ~/Desktop/machine

# Without health data (faster, offline)
python omnibioai-control-center/scripts/generate_report.py \
    --root ~/Desktop/machine \
    --skip-health

# Custom Control Center URL
python omnibioai-control-center/scripts/generate_report.py \
    --root ~/Desktop/machine \
    --control-center-url http://localhost:7070
```

### View the Report

- **File:** `out/reports/omnibioai_ecosystem_report.html`
- **Browser:** Open directly in any browser
- **Control Center:** `http://127.0.0.1:7070/report` (served live when Control Center is running)

### Requirements

```bash
pip install cloc pandas
# pytest + pytest-cov for coverage collection (best-effort)
```

---

## Control Center

The Control Center (`omnibioai-control-center/`) is the operational dashboard for the ecosystem:

- **`GET /health`** — Control Center self-check
- **`GET /services`** — Per-service health status
- **`GET /summary`** — Full ecosystem summary (services + disk)
- **`GET /report`** — Serves the pre-generated ecosystem HTML report

Health checks cover HTTP endpoints, TCP ports (MySQL, Redis), and disk usage thresholds. Configuration lives in `omnibioai-control-center/config/control_center.yaml`.

---

## Operational Modes

| Mode | Control Plane | Compute Plane |
|------|--------------|---------------|
| Local dev | Docker Compose | Local Docker |
| On-prem | Docker Compose | Docker / TES |
| HPC | External VM | Apptainer via TES |
| Hybrid | VM | HPC + TES |
| Cloud | Kubernetes | Kubernetes |

---

## Key Design Principles

- **Single workspace root** — all repos are siblings under one directory
- **No absolute paths** — fully portable across machines
- **Strict service boundaries** — control plane ≠ compute plane
- **Restart-safe orchestration** — ordered startup with health checks
- **Container-native** — OCI-compliant images throughout
- **Environment-driven** — all configuration via `.env` and YAML
- **No forced cloud dependencies** — runs fully offline and air-gapped
- **Engine-agnostic workflows** — WDL, Nextflow, Snakemake, CWL all supported

---

## What This Ecosystem Does Not Do

- Does not contain bioinformatics algorithms directly (these live in plugin repos)
- Does not vendor component repositories
- Does not enforce a single workflow engine
- Does not hide execution behind opaque AI calls
- Does not require external SaaS services

---

## Repository Index

| Repository | Visibility | Description |
|-----------|-----------|-------------|
| `omnibioai` | Private | Workbench — plugin-based Django platform |
| `omnibioai-tes` | Private | Tool Execution Service — HPC/cloud/local backends |
| `omnibioai-toolserver` | Private | FastAPI tool execution APIs |
| `omnibioai-tool-runtime` | Private | Cloud-agnostic container execution contract |
| `omnibioai-model-registry` | Public | Production ML model registry |
| `omnibioai-lims` | Private | Laboratory Information Management System |
| `omnibioai-rag` | Private | RAG-powered bioinformatics assistant |
| `omnibioai_sdk` | Private | Python SDK — v1 complete |
| `omnibioai-workflow-bundles` | Private | Versioned engine-agnostic workflow bundles |
| `omnibioai-dev-docker` | Private | GPU AI development environment |
| `omnibioai-control-center` | Public | Health dashboard and ecosystem report |

---

## Current Status — Beta Preparation

| Component | Status |
|-----------|--------|
| Multi-service orchestration | Stable |
| Tool Execution Service | Stable |
| ToolServer | Stable |
| Tool Runtime | Stable |
| Model Registry | Stable |
| LIMS | Stable |
| RAG assistant | Stable |
| Python SDK | v1 complete |
| Workflow bundles | Stable |
| Control Center | Active development |
| Ecosystem report | Active development |
| Kubernetes | Post-beta |

---

## License

See individual repository LICENSE files.
Components are independently licensed.
`omnibioai-model-registry` and `omnibioai-control-center` are Apache 2.0.

---

> OmniBioAI — reproducible bioinformatics at any scale, on any infrastructure.

© 2025 Manish Kumar. All rights reserved.
