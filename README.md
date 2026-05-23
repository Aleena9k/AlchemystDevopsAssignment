# Alchemyst AI — DevOps Internship Assignment

Distributed inference prototype: a small language model (Gemma 3 270M) running behind
a multi-VM worker mesh, exposed as a JSON HTTP API.

---

## Architecture

```
                         ┌─────────────────────────────────────────────┐
                         │               GCP VPC (alchemyst-vpc)        │
                         │               10.0.0.0/24                    │
                         │                                              │
  Internet               │  ┌──────────────┐                           │
  (curl / browser)       │  │  gateway-vm  │  public IP only VM        │
       │                 │  │  nginx :3111 │  tagged: api-gateway       │
       │  HTTP :3111     │  │  10.0.0.2    │  firewall: 0.0.0.0→:3111  │
       └────────────────►│  └──────┬───────┘                           │
                         │         │ proxy_pass                         │
                         │         ▼                                    │
                         │  ┌──────────────┐   Private subnet          │
                         │  │  engine-vm   │   No public IP            │
                         │  │  iii engine  │   Internal RPC only       │
                         │  │  10.0.0.3    │                           │
                         │  │  ws: :49134  │                           │
                         │  │  http: :3111 │                           │
                         │  └──────┬───────┘                           │
                         │         │  RPC (WebSocket)                  │
                         │    ┌────┴─────┐                             │
                         │    ▼          ▼                             │
                         │  ┌──────────────┐  ┌──────────────┐        │
                         │  │ inference-vm │  │  caller-vm   │        │
                         │  │ math-worker  │  │ caller-worker│        │
                         │  │ Python/Gemma │  │ TypeScript   │        │
                         │  │ 10.0.0.4    │  │ 10.0.0.5    │        │
                         │  └──────────────┘  └──────────────┘        │
                         │                                              │
                         └─────────────────────────────────────────────┘
```

### Request flow

```
curl POST /v1/chat/completions
  → gateway-vm (nginx, public IP)
    → engine-vm (iii engine, :3111)
      → caller-vm (http::run_inference_over_http trigger)
        → engine-vm (RPC dispatch)
          → inference-vm (inference::run_inference, Gemma model)
        ← result
      ← JSON response
    ← JSON response
  ← JSON response
```

### VM roles

| VM | Internal IP | Public IP | Role |
|---|---|---|---|
| `gateway-vm` | 10.0.0.2 | Yes | nginx reverse proxy, only internet-facing VM |
| `engine-vm` | 10.0.0.3 | No | iii RPC engine, coordinates all workers |
| `inference-vm` | 10.0.0.4 | No | Python worker, loads Gemma 3 270M, runs inference |
| `caller-vm` | 10.0.0.5 | No | TypeScript worker, HTTP trigger, fans out to inference |

---

## API

### Endpoint

```
POST /v1/chat/completions
Content-Type: application/json
```

### Request schema

```json
{
  "messages": [
    { "role": "system", "content": "You are a helpful assistant." },
    { "role": "user",   "content": "Your question here" }
  ]
}
```

### Example curl

```bash
curl -X POST http://<GATEWAY_PUBLIC_IP>:3111/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "messages": [
      {"role": "user", "content": "What is 2+2?"}
    ]
  }'
```

### Example response

```json
{
  "result": "2 + 2 = 4",
  "success": "You've connected two workers and they're interoperating seamlessly..."
}
```

---

## Redeploy from scratch

### Prerequisites

- GCP account with billing enabled
- `gcloud` CLI installed and authenticated (`gcloud auth login`)
- This repository cloned locally

### Steps

```bash
# 1. Set your project
export GCP_PROJECT_ID=your-gcp-project-id

# 2. Provision everything (VPC, subnet, firewall rules, 4 VMs)
bash infra/setup.sh

# 3. Wait ~5 minutes for VMs to boot and run startup scripts
#    (startup scripts install dependencies and start services automatically)

# 4. Get the gateway public IP
gcloud compute instances describe gateway-vm \
  --zone=us-central1-a \
  --format="value(networkInterfaces[0].accessConfigs[0].natIP)"

# 5. Test the API
curl -X POST http://<GATEWAY_PUBLIC_IP>:3111/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"messages": [{"role": "user", "content": "What is 2+2?"}]}'
```

### Tear down

```bash
bash infra/teardown.sh
```

---

## Debugging

```bash
# SSH into any VM via the gateway (only gateway has public IP)
gcloud compute ssh gateway-vm --zone=us-central1-a

# Check service status on any VM
sudo systemctl status iii-engine
sudo systemctl status inference-worker
sudo systemctl status caller-worker

# View live logs
sudo journalctl -u inference-worker -f
sudo journalctl -u caller-worker -f
sudo journalctl -u iii-engine -f
```

---

## Local development (verified working)

The full pipeline was tested locally on Google Cloud Shell:

```bash
# Terminal 1 — Start iii engine
cd quickstart && iii

# Terminal 2 — Start inference worker (Python + Gemma model)
python3 workers/inference-worker/inference_worker.py

# Terminal 3 — Start caller worker (TypeScript HTTP trigger)
cd workers/caller-worker && npm install && npm run dev

# Terminal 4 — Test
curl -X POST http://localhost:3111/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"messages": [{"role": "user", "content": "What is 2+2?"}]}'
```

The engine logs confirm the RPC chain fires correctly:
```
[INFO] iii-node inference::get_response called in TypeScript
[INFO] inference::run_inference dispatched to Python worker
[INFO] Response returned to caller
```

---

## Production hardening

### What I'd harden before going to production:

**Network security**
- Restrict SSH firewall rule to a specific IP range instead of `0.0.0.0/0`
- Add a Cloud NAT gateway so private VMs can pull updates without public IPs
- Enable VPC Flow Logs for audit trail
- Use Cloud Armor WAF in front of the gateway for DDoS protection

**Authentication & secrets**
- Add API key authentication on the gateway (nginx `auth_request` or a small middleware)
- Store secrets (HuggingFace tokens, API keys) in GCP Secret Manager, not env vars
- Use a service account with minimal IAM permissions for each VM

**Reliability**
- Put the gateway behind a GCP Load Balancer with health checks
- Run multiple inference-vm instances behind the engine for redundancy
- Add Cloud Monitoring alerts for VM CPU, memory, and service restarts

**TLS**
- Terminate TLS at the gateway using Let's Encrypt / Certbot
- All internal traffic stays HTTP (already on private subnet)

---

## What I'd do differently at 100x model size

If the model were 100x larger (~27B parameters instead of 270M):

**Compute**
- Switch from `e2-medium` (CPU) to `n1-standard-8` with NVIDIA T4 GPU (`--accelerator type=nvidia-tesla-t4`)
- Use `torch` with CUDA instead of CPU-only build
- Consider model quantization (GPTQ/AWQ) to reduce VRAM requirements

**Storage**
- Store model weights on a persistent GCP disk shared across inference VMs, not downloaded on each boot
- Or use GCS bucket + model caching layer (e.g. Hugging Face cache pointed at GCS FUSE mount)

**Scaling**
- Use a GCP Managed Instance Group for inference VMs with autoscaling based on request queue depth
- Add a Redis queue between the caller-worker and inference-worker so requests don't time out during scale-up
- Run multiple inference workers behind the engine to parallelize requests

**Cost**
- Use Spot/Preemptible VMs for inference tier (70% cheaper) with graceful retry on preemption
- Schedule scale-down during off-hours

---

## Repository structure

```
.
├── README.md                         ← this file
├── infra/
│   ├── setup.sh                      ← provisions all GCP resources
│   └── teardown.sh                   ← destroys all GCP resources
├── deploy/
│   ├── engine-startup.sh             ← iii engine systemd setup
│   ├── inference-startup.sh          ← Python inference worker setup
│   ├── caller-startup.sh             ← TypeScript caller worker setup
│   └── gateway-startup.sh            ← nginx reverse proxy setup
└── quickstart/                       ← original project (unchanged)
    ├── config.yaml
    └── workers/
        ├── inference-worker/
        │   ├── inference_worker.py
        │   └── requirements.txt
        └── caller-worker/
            └── src/worker.ts
```
