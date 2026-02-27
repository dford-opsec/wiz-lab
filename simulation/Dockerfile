# Use the official Google Cloud SDK image
FROM google/cloud-sdk:alpine

# Install kubectl
RUN apk add --no-cache kubectl

WORKDIR /app
# Copy all your bash scripts into the container
COPY *.sh ./
RUN chmod +x *.sh

# When the container starts, run the master sequence
CMD ["/bin/bash", "./run_all_attacks.sh"]
