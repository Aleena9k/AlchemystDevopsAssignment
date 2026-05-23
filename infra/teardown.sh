#!/usr/bin/env bash
# =============================================================================
# Alchemyst AI DevOps Assignment — Teardown
# Deletes all resources created by setup.sh
# Usage: bash infra/teardown.sh
# =============================================================================

set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-your-gcp-project-id}"
ZONE="us-central1-a"
REGION="us-central1"
NETWORK="alchemyst-vpc"
SUBNET="alchemyst-subnet"

gcloud config set project "$PROJECT_ID"

echo "==> Deleting VMs..."
gcloud compute instances delete gateway-vm engine-vm inference-vm caller-vm \
  --zone="$ZONE" --quiet

echo "==> Deleting firewall rules..."
gcloud compute firewall-rules delete allow-internal allow-ssh allow-api-gateway --quiet

echo "==> Deleting subnet..."
gcloud compute networks subnets delete "$SUBNET" --region="$REGION" --quiet

echo "==> Deleting VPC..."
gcloud compute networks delete "$NETWORK" --quiet

echo "==> All resources deleted."
