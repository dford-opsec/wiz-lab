#!/bin/bash
gcloud container clusters get-credentials wiz-cluster --zone us-central1-a --project clgcporg10-181

# --- Color Variables ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}======================================================${NC}"
echo -e "${YELLOW}   INITIATING MASTER ATTACK SEQUENCE                  ${NC}"
echo -e "${BLUE}======================================================${NC}"

# Get the directory where this script is located (important for cron)
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Run Script 1
if [ -f "$DIR/attack.sh" ]; then
    echo -e "${YELLOW}[*] Executing attack.sh...${NC}"
    bash "$DIR/attack.sh"
else
    echo -e "${GREEN}[!] attack.sh not found. Skipping.${NC}"
fi

# Run Script 2
if [ -f "$DIR/noisy-attack.sh" ]; then
    echo -e "${YELLOW}[*] Executing noisy-attack.sh...${NC}"
    bash "$DIR/noisy-attack.sh"
else
    echo -e "${GREEN}[!] noisy-attack.sh not found. Skipping.${NC}"
fi

# Run Script 3
if [ -f "$DIR/ssh-attack.sh" ]; then
    echo -e "${YELLOW}[*] Executing ssh-attack.sh...${NC}"
    bash "$DIR/ssh-attack.sh"
else
    echo -e "${GREEN}[!] ssh-attack.sh not found. Skipping.${NC}"
fi

echo -e "${BLUE}======================================================${NC}"
echo -e "${GREEN}   MASTER ATTACK SEQUENCE COMPLETE                    ${NC}"
echo -e "${BLUE}======================================================${NC}"
