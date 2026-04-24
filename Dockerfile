# Dockerfile
# -----------------------------------------------------------------------------
# Custom Node-RED image for the "penicillin_nodered" project.
# This image:
#   - Starts from the official Node-RED image
#   - Installs the dashboard module
#   - Uses /data as a volume for flows, CSV batches and assets
# -----------------------------------------------------------------------------
FROM nodered/node-red:3.1

# Install Node-RED dashboard (and any other required modules)
# It is installed globally into the Node-RED user directory (/data).
RUN npm install --unsafe-perm --no-update-notifier --no-fund --only=production \
    node-red-dashboard@3.6.6

# Create the batches directory inside the Node-RED data directory.
RUN mkdir -p /data/batches

# Copy initial flows and static assets.
# - flows.json  : contains the default flow (STAMM_V2)
COPY data/flows.json /data/flows.json

# /data is declared as a volume in the base image, so flows.json and batches
# can be overridden or persisted by mounting ./data from the host.

# Expose the default Node-RED port (can be overridden by Docker Compose mapping)
EXPOSE 1880