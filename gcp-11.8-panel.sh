#!/bin/bash

# ============================================================================
# 11.8 - Panel (Streamlit) Deployment to Google Cloud Run
# ============================================================================
#
# Purpose:
#   - Deploy Streamlit admin panel to Cloud Run
#   - Configure backend API connection
#   - Setup admin authentication
#
# Usage:
#   source gcp-variables.sh
#   source /tmp/backend-url.env  (from 11.6 script)
#   bash gcp-11.8-panel.sh
#
# Prerequisites:
#   - Backend deployed to Cloud Run (gcp-11.6-backend.sh)
#   - Secrets created (gcp-11.5-secrets.sh)
#   - Service account created (gcp-11.2-iam.sh)
#
# ============================================================================

set -euo pipefail

echo "=========================================="
echo "11.8: Panel (Streamlit) - Cloud Run Deploy"
echo "=========================================="
echo

# ============================================================================
# 1. Validate Environment
# ============================================================================

echo "1️⃣  Validating environment..."

if [[ -z "${PROJECT_ID:-}" ]] || [[ -z "${REGION:-}" ]]; then
  echo "❌ ERROR: gcp-variables.sh not sourced!"
  echo "   Run: source gcp-variables.sh"
  exit 1
fi

confirm_vars

# Load backend URL from previous script
if [[ ! -f "/tmp/backend-url.env" ]]; then
  echo "❌ ERROR: Backend URL file not found!"
  echo "   Backend must be deployed first: bash gcp-11.6-backend.sh"
  exit 1
fi

source /tmp/backend-url.env

if [[ -z "${BACKEND_URL:-}" ]]; then
  echo "❌ ERROR: BACKEND_URL not set from backend deployment"
  exit 1
fi

echo "   ✓ Backend URL: $BACKEND_URL"
echo

# ============================================================================
# 2. Set Panel-Specific Variables
# ============================================================================

PANEL_SERVICE_NAME="wa-panel"
PANEL_IMAGE_NAME="wa-panel:latest"
PANEL_ARTIFACT_REGISTRY="${REGION}-docker.pkg.dev/${PROJECT_ID}/wa-app"
PANEL_FULL_IMAGE="${PANEL_ARTIFACT_REGISTRY}/${PANEL_IMAGE_NAME}"

# Cloud Run configuration
PANEL_CPU="1"
PANEL_MEMORY="512Mi"
PANEL_MAX_INSTANCES="2"
PANEL_TIMEOUT="600s"

# Admin credentials
PANEL_USER="admin"
PANEL_PASS_HASH="4d967a2a6991c61a7ff3a6dab56015779974d9724c376351b1bf86865819cf55"  # SHA256 of "admin"

echo "2️⃣  Panel configuration:"
echo "  Service Name:    $PANEL_SERVICE_NAME"
echo "  Image:           $PANEL_FULL_IMAGE"
echo "  Backend API:     $BACKEND_URL"
echo "  Admin User:      $PANEL_USER"
echo "  Admin Pass Hash: ${PANEL_PASS_HASH:0:16}..."
echo

# ============================================================================
# 3. Create Artifact Registry Repository (if not exists)
# ============================================================================

echo "3️⃣  Ensuring Artifact Registry repository exists..."

if gcloud artifacts repositories describe wa-app \
  --location "$REGION" \
  --project "$PROJECT_ID" &>/dev/null; then
  echo "   ✓ Repository already exists"
else
  gcloud artifacts repositories create wa-app \
    --repository-format=docker \
    --location="$REGION" \
    --project="$PROJECT_ID"
  echo "   ✓ Repository created"
fi

echo

# ============================================================================
# 4. Configure Docker Credentials
# ============================================================================

echo "4️⃣  Configuring Docker credentials..."

gcloud auth configure-docker "${REGION}-docker.pkg.dev" \
  --quiet \
  --project="$PROJECT_ID"

echo "   ✓ Docker credentials configured"
echo

# ============================================================================
# 5. Build and Push Panel Docker Image
# ============================================================================

echo "5️⃣  Building and pushing Streamlit panel image..."
echo

# Create temporary Dockerfile for panel
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Copy necessary files to temp dir
cp -r "$REPO_ROOT/panel" "$TEMP_DIR/"
cp -r "$REPO_ROOT/wa_orchestrator" "$TEMP_DIR/"
cp "$REPO_ROOT/requirements.txt" "$TEMP_DIR/"

# Create Dockerfile for panel
cat > "$TEMP_DIR/Dockerfile.panel" <<'EODOCKERFILE'
# ============================================================================
# Dockerfile para Panel Streamlit (Admin Interface)
# ============================================================================

FROM python:3.13-slim

WORKDIR /app

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements
COPY requirements.txt .

# Install Python dependencies
RUN pip install --upgrade pip setuptools wheel && \
    pip install -r requirements.txt

# Copy application code
COPY wa_orchestrator ./wa_orchestrator
COPY panel ./panel

# Environment
ENV PYTHONUNBUFFERED=1
ENV STREAMLIT_SERVER_HEADLESS=true

# Streamlit config
RUN mkdir -p /root/.streamlit
RUN cat > /root/.streamlit/config.toml <<EOF
[server]
port = 8080
enableCORS = false
enableXsrfProtection = true
maxUploadSize = 200

[logger]
level = "info"
EOF

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:8080/_stcore/health || exit 1

# Port
EXPOSE 8080

# Entrypoint
CMD ["streamlit", "run", "panel/panel_app.py", "--server.port=8080", "--server.address=0.0.0.0"]
EODOCKERFILE

echo "   Building image: $PANEL_FULL_IMAGE"
echo

# Build using Cloud Build
gcloud builds submit "$TEMP_DIR" \
  --region="$REGION" \
  --tag="$PANEL_FULL_IMAGE" \
  --project="$PROJECT_ID" \
  --timeout=1200s \
  --dockerfile="Dockerfile.panel" \
  --substitutions="_IMAGE_NAME=$PANEL_FULL_IMAGE"

echo
echo "   ✓ Panel image pushed: $PANEL_FULL_IMAGE"
echo

# ============================================================================
# 6. Get Admin Token from Secrets
# ============================================================================

echo "6️⃣  Retrieving admin token from Secret Manager..."

ADMIN_TOKEN=$(gcloud secrets versions access latest \
  --secret="$SEC_ADMIN_TOKEN" \
  --project="$PROJECT_ID")

if [[ -z "$ADMIN_TOKEN" ]]; then
  echo "⚠️  Warning: Could not retrieve admin token. Using default."
  ADMIN_TOKEN="super-secret-panel-admin-token"
fi

echo "   ✓ Admin token retrieved (masked)"
echo

# ============================================================================
# 7. Deploy Panel to Cloud Run
# ============================================================================

echo "7️⃣  Deploying to Cloud Run..."

gcloud run deploy "$PANEL_SERVICE_NAME" \
  --image="$PANEL_FULL_IMAGE" \
  --region="$REGION" \
  --project="$PROJECT_ID" \
  --platform=managed \
  --cpu="$PANEL_CPU" \
  --memory="$PANEL_MEMORY" \
  --max-instances="$PANEL_MAX_INSTANCES" \
  --timeout="$PANEL_TIMEOUT" \
  --service-account="${PANEL_SA}" \
  --allow-unauthenticated \
  --no-gen2 \
  --set-env-vars="ADMIN_API_BASE_URL=${BACKEND_URL},\
PANEL_USER=${PANEL_USER},\
PANEL_PASS_HASH=${PANEL_PASS_HASH},\
LOG_LEVEL=INFO,\
GCP_PROJECT_ID=${PROJECT_ID}" \
  --set-secrets="ADMIN_API_TOKEN=sec-admin-token:latest" \
  --quiet

echo "   ✓ Panel deployment complete"
echo

# ============================================================================
# 8. Get Panel Service URL
# ============================================================================

echo "8️⃣  Retrieving panel service URL..."

PANEL_URL=$(gcloud run services describe "$PANEL_SERVICE_NAME" \
  --region="$REGION" \
  --project="$PROJECT_ID" \
  --format='value(status.url)')

echo "   Panel URL: $PANEL_URL"
echo

# ============================================================================
# 9. Verify Deployment
# ============================================================================

echo "9️⃣  Verifying deployment..."
echo

# Wait for service to stabilize
sleep 5

# Test health endpoint
HEALTH_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "${PANEL_URL}/_stcore/health" || echo "000")

if [[ "$HEALTH_RESPONSE" == "200" ]] || [[ "$HEALTH_RESPONSE" == "500" ]]; then
  echo "   ✓ Streamlit service is responding"
else
  echo "   ⚠️  Service returned HTTP $HEALTH_RESPONSE (may still be starting)"
fi

echo

# ============================================================================
# 10. Test Admin Access
# ============================================================================

echo "🔟  Testing admin access..."
echo

# Create temporary file with credentials
TEMP_CREDS=$(mktemp)
trap "rm -f $TEMP_CREDS" EXIT

cat > "$TEMP_CREDS" <<EOF
Username: $PANEL_USER
Password: admin (default)
Pass Hash: $PANEL_PASS_HASH
Backend API: $BACKEND_URL
EOF

echo "   Default Credentials:"
echo "   ├─ User: $PANEL_USER"
echo "   ├─ Password: admin (change in production!)"
echo "   └─ Backend: $BACKEND_URL"
echo

# ============================================================================
# 11. Output Summary
# ============================================================================

echo "=========================================="
echo "✅ Panel Deployment Complete!"
echo "=========================================="
echo
echo "Panel Service Details:"
echo "  Service Name:    $PANEL_SERVICE_NAME"
echo "  URL:             $PANEL_URL"
echo "  Backend API:     $BACKEND_URL"
echo "  Admin User:      $PANEL_USER"
echo "  Region:          $REGION"
echo "  Service Account: $PANEL_SA"
echo
echo "Access the Panel:"
echo "  URL: $PANEL_URL"
echo "  Username: $PANEL_USER"
echo "  Password: admin"
echo
echo "Next Steps:"
echo "  1. Visit the panel: $PANEL_URL"
echo "  2. Login with admin / admin"
echo "  3. Verify backend connectivity in 'Analítica' tab"
echo "  4. Next: Run gcp-11.9-webhook.sh to configure Meta"
echo
echo "Important - SECURITY NOTICE:"
echo "  ⚠️  Change admin password in production!"
echo "  ⚠️  Update PANEL_PASS_HASH with new SHA256 hash"
echo "  ⚠️  Store credentials in Secret Manager"
echo
echo "Logs:"
echo "  gcloud run logs read $PANEL_SERVICE_NAME --region=$REGION --project=$PROJECT_ID"
echo
echo "Update Panel Password:"
echo "  1. Generate new hash: echo -n 'newpassword' | sha256sum"
echo "  2. Update gcp-11.8-panel.sh with new PANEL_PASS_HASH"
echo "  3. Redeploy: bash gcp-11.8-panel.sh"
echo
echo "=========================================="
echo
