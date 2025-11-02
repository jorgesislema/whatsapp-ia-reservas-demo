#!/bin/bash

# ============================================================================
# 11.6 - Backend (FastAPI) Deployment to Google Cloud Run
# ============================================================================
#
# Purpose:
#   - Build and deploy FastAPI backend to Cloud Run
#   - Configure environment variables and secrets
#   - Setup VPC Connector for Cloud SQL access
#   - Configure service account with least-privilege
#
# Usage:
#   source gcp-variables.sh
#   bash gcp-11.6-backend.sh
#
# Prerequisites:
#   - gcp-variables.sh sourced (variables exported)
#   - Service account created (gcp-11.2-iam.sh)
#   - Cloud SQL instance created (gcp-11.3-cloudsql.sh)
#   - VPC Connector created (gcp-11.4-vpc.sh)
#   - Secrets created (gcp-11.5-secrets.sh)
#   - Docker installed locally (if building manually)
#   - gcloud CLI configured
#
# ============================================================================

set -euo pipefail

echo "=========================================="
echo "11.6: Backend FastAPI - Cloud Run Deploy"
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

# ============================================================================
# 2. Set Backend-Specific Variables
# ============================================================================

BACKEND_SERVICE_NAME="wa-backend"
BACKEND_IMAGE_NAME="wa-backend:latest"
BACKEND_ARTIFACT_REGISTRY="${REGION}-docker.pkg.dev/${PROJECT_ID}/wa-app"
BACKEND_FULL_IMAGE="${BACKEND_ARTIFACT_REGISTRY}/${BACKEND_IMAGE_NAME}"

# Cloud Run configuration
BACKEND_CPU="1"
BACKEND_MEMORY="512Mi"
BACKEND_MAX_INSTANCES="3"
BACKEND_TIMEOUT="600s"

echo "Variables:"
echo "  SERVICE:           $BACKEND_SERVICE_NAME"
echo "  IMAGE:             $BACKEND_FULL_IMAGE"
echo "  CPU:               $BACKEND_CPU"
echo "  MEMORY:            $BACKEND_MEMORY"
echo "  MAX_INSTANCES:     $BACKEND_MAX_INSTANCES"
echo "  REGION:            $REGION"
echo "  VPC_CONNECTOR:     $VPC_CONNECTOR_NAME"
echo

# ============================================================================
# 3. Create Artifact Registry Repository
# ============================================================================

echo "2️⃣  Creating Artifact Registry repository..."

if gcloud artifacts repositories describe wa-app \
  --location "$REGION" \
  --project "$PROJECT_ID" &>/dev/null; then
  echo "   ✓ Repository already exists"
else
  gcloud artifacts repositories create wa-app \
    --repository-format=docker \
    --location="$REGION" \
    --project="$PROJECT_ID" \
    --description="WhatsApp IA Reservas Docker Images"
  echo "   ✓ Repository created"
fi
echo

# ============================================================================
# 4. Configure Docker Credentials
# ============================================================================

echo "3️⃣  Configuring Docker credentials..."

gcloud auth configure-docker "${REGION}-docker.pkg.dev" \
  --quiet \
  --project="$PROJECT_ID"

echo "   ✓ Docker credentials configured"
echo

# ============================================================================
# 5. Build and Push Docker Image
# ============================================================================

echo "4️⃣  Building and pushing Docker image to Artifact Registry..."
echo "   (This may take 2-3 minutes...)"
echo

# Determine root directory (assumes script is in repo root)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Build using gcloud (uses Cloud Build for faster builds)
gcloud builds submit "$REPO_ROOT" \
  --region="$REGION" \
  --tag="$BACKEND_FULL_IMAGE" \
  --project="$PROJECT_ID" \
  --timeout=1200s \
  --substitutions="_IMAGE_NAME=$BACKEND_FULL_IMAGE"

echo
echo "   ✓ Image pushed: $BACKEND_FULL_IMAGE"
echo

# ============================================================================
# 6. Get Cloud SQL Connection Info
# ============================================================================

echo "5️⃣  Retrieving Cloud SQL connection info..."

# Get Cloud SQL connection name
CLOUDSQL_CONNECTION_NAME=$(gcloud sql instances describe "$DB_INSTANCE" \
  --project="$PROJECT_ID" \
  --format='value(connectionName)')

if [[ -z "$CLOUDSQL_CONNECTION_NAME" ]]; then
  echo "❌ ERROR: Could not retrieve Cloud SQL connection name"
  exit 1
fi

echo "   Cloud SQL Connection: $CLOUDSQL_CONNECTION_NAME"
echo

# ============================================================================
# 7. Get Database Password from Secret
# ============================================================================

echo "6️⃣  Retrieving database password from Secret Manager..."

DB_PASSWORD=$(gcloud secrets versions access latest \
  --secret="$SEC_DB_PASS" \
  --project="$PROJECT_ID")

if [[ -z "$DB_PASSWORD" ]]; then
  echo "❌ ERROR: Could not retrieve database password from Secret Manager"
  exit 1
fi

echo "   ✓ Password retrieved (masked)"
echo

# ============================================================================
# 8. Build Cloud SQL Connection String
# ============================================================================

# For Cloud Run with VPC Connector to Cloud SQL:
# postgresql+pg8000://user:password@/database?unix_sock=/cloudsql/<connection-name>/.s.PGSQL.5432

DATABASE_URL="postgresql+pg8000://${DB_USER}:${DB_PASSWORD}@/${DB_NAME}?unix_sock=/cloudsql/${CLOUDSQL_CONNECTION_NAME}/.s.PGSQL.5432"

# For debugging (without actual password)
DISPLAY_DATABASE_URL="postgresql+pg8000://${DB_USER}:***@/${DB_NAME}?unix_sock=/cloudsql/${CLOUDSQL_CONNECTION_NAME}/.s.PGSQL.5432"

echo "7️⃣  Database connection string prepared:"
echo "   $DISPLAY_DATABASE_URL"
echo

# ============================================================================
# 9. Deploy Backend to Cloud Run
# ============================================================================

echo "8️⃣  Deploying to Cloud Run..."

gcloud run deploy "$BACKEND_SERVICE_NAME" \
  --image="$BACKEND_FULL_IMAGE" \
  --region="$REGION" \
  --project="$PROJECT_ID" \
  --platform=managed \
  --cpu="$BACKEND_CPU" \
  --memory="$BACKEND_MEMORY" \
  --max-instances="$BACKEND_MAX_INSTANCES" \
  --timeout="$BACKEND_TIMEOUT" \
  --service-account="${BACKEND_SA}" \
  --vpc-connector="${VPC_CONNECTOR_NAME}" \
  --vpc-connector-egress-settings="all" \
  --allow-unauthenticated \
  --no-gen2 \
  --set-env-vars="DATABASE_URL=${DATABASE_URL},\
LOG_LEVEL=INFO,\
ENVIRONMENT=production,\
GCP_PROJECT_ID=${PROJECT_ID}" \
  --set-secrets="WA_APP_SECRET=sec-wa-app-secret:latest,\
WA_TOKEN=sec-wa-token:latest,\
WA_VERIFY_TOKEN=sec-wa-verify-token:latest,\
ADMIN_TOKEN=sec-admin-token:latest" \
  --quiet

echo "   ✓ Deployment complete"
echo

# ============================================================================
# 10. Get Backend Service URL
# ============================================================================

echo "9️⃣  Retrieving backend service URL..."

BACKEND_URL=$(gcloud run services describe "$BACKEND_SERVICE_NAME" \
  --region="$REGION" \
  --project="$PROJECT_ID" \
  --format='value(status.url)')

echo "   Backend URL: $BACKEND_URL"
echo

# ============================================================================
# 11. Verify Deployment
# ============================================================================

echo "🔟  Verifying deployment..."
echo

# Wait a bit for service to stabilize
sleep 5

# Test health endpoint
HEALTH_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "${BACKEND_URL}/healthz" || true)

if [[ "$HEALTH_RESPONSE" == "200" ]]; then
  echo "   ✓ Health check passed (HTTP 200)"
else
  echo "   ⚠️  Health check returned HTTP $HEALTH_RESPONSE (service may still be starting)"
fi

echo

# ============================================================================
# 12. Output Summary
# ============================================================================

echo "=========================================="
echo "✅ Backend Deployment Complete!"
echo "=========================================="
echo
echo "Backend Service Details:"
echo "  Service Name:    $BACKEND_SERVICE_NAME"
echo "  URL:             $BACKEND_URL"
echo "  Region:          $REGION"
echo "  Service Account: $BACKEND_SA"
echo "  VPC Connector:   $VPC_CONNECTOR_NAME"
echo "  Database:        $DB_NAME @ $CLOUDSQL_CONNECTION_NAME"
echo
echo "Next Steps:"
echo "  1. Save the Backend URL for panel deployment: $BACKEND_URL"
echo "  2. Test API with: curl $BACKEND_URL/docs"
echo "  3. Next: Run gcp-11.7-init.sh to initialize database"
echo "  4. Then: Run gcp-11.8-panel.sh to deploy panel"
echo "  5. Finally: Run gcp-11.9-webhook.sh to configure Meta webhook"
echo
echo "Logs:"
echo "  gcloud run logs read $BACKEND_SERVICE_NAME --region=$REGION --project=$PROJECT_ID"
echo
echo "=========================================="

# ============================================================================
# 13. Export Backend URL for next scripts
# ============================================================================

cat > /tmp/backend-url.env <<EOF
BACKEND_URL=$BACKEND_URL
BACKEND_SERVICE_NAME=$BACKEND_SERVICE_NAME
CLOUDSQL_CONNECTION_NAME=$CLOUDSQL_CONNECTION_NAME
EOF

echo "Exported to /tmp/backend-url.env for next scripts"
echo
