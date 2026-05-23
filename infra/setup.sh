#!/usr/bin/env bash
# =============================================================================
# Alchemyst AI DevOps Assignment — Infrastructure Setup
# Provisions VPC, subnet, firewall rules, and 4 VMs on GCP
# Usage: bash infra/setup.sh
# =============================================================================

set -euo pipefail

# ---------- Configuration ----------------------------------------------------
PROJECT_ID="${GCP_PROJECT_ID:-your-gcp-project-id}"   # override via env var
REGION="us-central1"
ZONE="us-central1-a"
NETWORK="alchemyst-vpc"
SUBNET="alchemyst-subnet"
SUBNET_RANGE="10.0.0.0/24"

# VM names
GATEWAY_VM="gateway-vm"
ENGINE_VM="engine-vm"
INFERENCE_VM="inference-vm"
CALLER_VM="caller-vm"

MACHINE_TYPE="e2-medium"        # 2 vCPU, 4 GB RAM — fits within free tier
DISK_SIZE="20GB"                # enough for torch + Gemma model
IMAGE_FAMILY="debian-12"
IMAGE_PROJECT="debian-cloud"

echo "==> Using project: $PROJECT_ID"
gcloud config set project "$PROJECT_ID"

# ---------- 1. Enable APIs ---------------------------------------------------
echo "==> Enabling Compute Engine API..."
gcloud services enable compute.googleapis.com

# ---------- 2. VPC Network ---------------------------------------------------
echo "==> Creating VPC network..."
gcloud compute networks create "$NETWORK" \
  --subnet-mode=custom \
  --bgp-routing-mode=regional

# ---------- 3. Private Subnet ------------------------------------------------
echo "==> Creating private subnet..."
gcloud compute networks subnets create "$SUBNET" \
  --network="$NETWORK" \
  --region="$REGION" \
  --range="$SUBNET_RANGE" \
  --enable-private-ip-google-access

# ---------- 4. Firewall Rules ------------------------------------------------
echo "==> Creating firewall rules..."

# Allow all internal traffic between VMs in the subnet (RPC)
gcloud compute firewall-rules create allow-internal \
  --network="$NETWORK" \
  --direction=INGRESS \
  --priority=1000 \
  --action=ALLOW \
  --rules=tcp,udp,icmp \
  --source-ranges="$SUBNET_RANGE"

# Allow SSH from anywhere (for setup; restrict to your IP in production)
gcloud compute firewall-rules create allow-ssh \
  --network="$NETWORK" \
  --direction=INGRESS \
  --priority=1000 \
  --action=ALLOW \
  --rules=tcp:22 \
  --source-ranges="0.0.0.0/0"

# Allow HTTP API traffic only to the gateway VM (port 3111)
gcloud compute firewall-rules create allow-api-gateway \
  --network="$NETWORK" \
  --direction=INGRESS \
  --priority=1000 \
  --action=ALLOW \
  --rules=tcp:3111 \
  --source-ranges="0.0.0.0/0" \
  --target-tags="api-gateway"

# ---------- 5. VMs -----------------------------------------------------------
echo "==> Creating gateway VM (public IP)..."
gcloud compute instances create "$GATEWAY_VM" \
  --zone="$ZONE" \
  --machine-type="$MACHINE_TYPE" \
  --subnet="$SUBNET" \
  --boot-disk-size="$DISK_SIZE" \
  --image-family="$IMAGE_FAMILY" \
  --image-project="$IMAGE_PROJECT" \
  --tags="api-gateway" \
  --metadata-from-file=startup-script=deploy/gateway-startup.sh

echo "==> Creating engine VM (no public IP)..."
gcloud compute instances create "$ENGINE_VM" \
  --zone="$ZONE" \
  --machine-type="$MACHINE_TYPE" \
  --subnet="$SUBNET" \
  --no-address \
  --boot-disk-size="$DISK_SIZE" \
  --image-family="$IMAGE_FAMILY" \
  --image-project="$IMAGE_PROJECT" \
  --metadata-from-file=startup-script=deploy/engine-startup.sh

echo "==> Creating inference VM (no public IP)..."
gcloud compute instances create "$INFERENCE_VM" \
  --zone="$ZONE" \
  --machine-type="$MACHINE_TYPE" \
  --subnet="$SUBNET" \
  --no-address \
  --boot-disk-size="$DISK_SIZE" \
  --image-family="$IMAGE_FAMILY" \
  --image-project="$IMAGE_PROJECT" \
  --metadata-from-file=startup-script=deploy/inference-startup.sh

echo "==> Creating caller VM (no public IP)..."
gcloud compute instances create "$CALLER_VM" \
  --zone="$ZONE" \
  --machine-type="$MACHINE_TYPE" \
  --subnet="$SUBNET" \
  --no-address \
  --boot-disk-size="$DISK_SIZE" \
  --image-family="$IMAGE_FAMILY" \
  --image-project="$IMAGE_PROJECT" \
  --metadata-from-file=startup-script=deploy/caller-startup.sh

# ---------- 6. Print IPs -----------------------------------------------------
echo ""
echo "==> Infrastructure ready! VM internal IPs:"
gcloud compute instances list \
  --filter="zone:$ZONE" \
  --format="table(name,networkInterfaces[0].networkIP,networkInterfaces[0].accessConfigs[0].natIP)"

GATEWAY_IP=$(gcloud compute instances describe "$GATEWAY_VM" \
  --zone="$ZONE" \
  --format="value(networkInterfaces[0].accessConfigs[0].natIP)")

echo ""
echo "==> Public API endpoint:"
echo "    http://${GATEWAY_IP}:3111/v1/chat/completions"
echo ""
echo "==> Test with:"
echo "    curl -X POST http://${GATEWAY_IP}:3111/v1/chat/completions \\"
echo "      -H 'Content-Type: application/json' \\"
echo "      -d '{\"messages\": [{\"role\": \"user\", \"content\": \"What is 2+2?\"}]}'"
