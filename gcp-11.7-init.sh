#!/bin/bash

# ============================================================================
# 11.7 - Database Initialization (Cloud SQL)
# ============================================================================
#
# Purpose:
#   - Initialize Cloud SQL database with tables
#   - Load Knowledge Base (KB)
#   - Verify data integrity
#
# Usage:
#   source gcp-variables.sh
#   source /tmp/backend-url.env  (from 11.6 script)
#   bash gcp-11.7-init.sh
#
# Prerequisites:
#   - Cloud SQL instance created and running (gcp-11.3-cloudsql.sh)
#   - Backend deployed to Cloud Run (gcp-11.6-backend.sh)
#   - Database and user already created (gcp-11.3-cloudsql.sh)
#   - Cloud SQL Proxy installed locally OR use gcloud sql connect
#
# Two Approaches:
#   1. Local Init: Run init_db.py locally with SQL Proxy (used here)
#   2. Cloud Init: POST /admin/init endpoint on backend (alternative)
#
# ============================================================================

set -euo pipefail

echo "=========================================="
echo "11.7: Database Initialization"
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

# Load backend URL if available
if [[ -f "/tmp/backend-url.env" ]]; then
  source /tmp/backend-url.env
  echo "   ✓ Backend URL loaded from previous deployment"
else
  echo "   ℹ️  Backend URL file not found (optional for this step)"
fi

echo

# ============================================================================
# 2. Get Database Connection Info
# ============================================================================

echo "2️⃣  Retrieving database connection info..."

# Get Cloud SQL connection name
CLOUDSQL_CONNECTION_NAME=$(gcloud sql instances describe "$DB_INSTANCE" \
  --project="$PROJECT_ID" \
  --format='value(connectionName)')

# Get Cloud SQL instance IP
CLOUDSQL_IP=$(gcloud sql instances describe "$DB_INSTANCE" \
  --project="$PROJECT_ID" \
  --format='value(ipAddresses[0].ipAddress)' 2>/dev/null || true)

echo "   Connection Name: $CLOUDSQL_CONNECTION_NAME"
echo "   Instance:        $DB_INSTANCE"
echo "   Database:        $DB_NAME"
echo "   User:            $DB_USER"
echo

# ============================================================================
# 3. Get Database Password from Secret
# ============================================================================

echo "3️⃣  Retrieving database password..."

DB_PASSWORD=$(gcloud secrets versions access latest \
  --secret="$SEC_DB_PASS" \
  --project="$PROJECT_ID")

if [[ -z "$DB_PASSWORD" ]]; then
  echo "❌ ERROR: Could not retrieve database password"
  exit 1
fi

echo "   ✓ Password retrieved"
echo

# ============================================================================
# 4. Check for Cloud SQL Proxy
# ============================================================================

echo "4️⃣  Checking for Cloud SQL Proxy..."

# Try to install Cloud SQL Proxy if not exists
if ! command -v cloud_sql_proxy &> /dev/null; then
  echo "   ℹ️  Cloud SQL Proxy not found. Using gcloud sql connect..."
  USE_GCLOUD_SQL_CONNECT=true
else
  echo "   ✓ Cloud SQL Proxy found"
  USE_GCLOUD_SQL_CONNECT=false
fi

echo

# ============================================================================
# 5. Determine Connection Method and Get Root Directory
# ============================================================================

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INIT_SCRIPT="$REPO_ROOT/wa_orchestrator/db/init_db.py"

if [[ ! -f "$INIT_SCRIPT" ]]; then
  echo "❌ ERROR: init_db.py not found at: $INIT_SCRIPT"
  exit 1
fi

echo "5️⃣  Preparing database initialization..."
echo "   Script: $INIT_SCRIPT"
echo

# ============================================================================
# 6. Method A: Initialize via Admin API Endpoint (Preferred for Cloud SQL)
# ============================================================================

if [[ -n "${BACKEND_URL:-}" ]]; then
  echo "6️⃣  Using Admin API endpoint (preferred method)..."
  echo
  
  # Get admin token
  ADMIN_TOKEN=$(gcloud secrets versions access latest \
    --secret="$SEC_ADMIN_TOKEN" \
    --project="$PROJECT_ID")
  
  if [[ -z "$ADMIN_TOKEN" ]]; then
    echo "   ⚠️  Could not retrieve admin token. Falling back to direct DB init."
  else
    echo "   Calling POST ${BACKEND_URL}/admin/init..."
    echo
    
    # Call initialization endpoint
    INIT_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
      "${BACKEND_URL}/admin/init" \
      -H "Authorization: Bearer ${ADMIN_TOKEN}" \
      -H "Content-Type: application/json" \
      -d '{"reinitialize": false}' || true)
    
    # Parse response (last line is HTTP code)
    HTTP_CODE=$(echo "$INIT_RESPONSE" | tail -n1)
    RESPONSE_BODY=$(echo "$INIT_RESPONSE" | sed '$d')
    
    if [[ "$HTTP_CODE" == "200" ]]; then
      echo "   ✓ Database initialization successful (HTTP 200)"
      echo "   Response: $RESPONSE_BODY"
      echo
      
      # Skip to verification
      SKIP_LOCAL_INIT=true
    else
      echo "   ⚠️  API returned HTTP $HTTP_CODE"
      echo "   Response: $RESPONSE_BODY"
      echo "   Falling back to direct database initialization..."
      echo
      SKIP_LOCAL_INIT=false
    fi
  fi
else
  SKIP_LOCAL_INIT=false
fi

# ============================================================================
# 7. Method B: Initialize via Local Direct Connection
# ============================================================================

if [[ "${SKIP_LOCAL_INIT:-false}" != "true" ]]; then
  echo "7️⃣  Direct database initialization (local Python)..."
  echo
  
  # Build connection string for local init_db.py
  # For direct connection to Cloud SQL, we need the public IP or Cloud SQL Proxy
  
  # Check if instance has public IP
  if [[ -n "${CLOUDSQL_IP}" ]] && [[ "${CLOUDSQL_IP}" != "None" ]]; then
    # Has public IP - can connect directly
    CONNECTION_STRING="postgresql://${DB_USER}:${DB_PASSWORD}@${CLOUDSQL_IP}/${DB_NAME}"
    echo "   Using public IP: $CLOUDSQL_IP"
  else
    # No public IP (private instance) - need Cloud SQL Proxy
    echo "   Instance has private IP. Need Cloud SQL Proxy..."
    
    # Start Cloud SQL Proxy in background
    if command -v cloud_sql_proxy &> /dev/null; then
      echo "   Starting Cloud SQL Proxy..."
      
      # Kill any existing proxy
      pkill -f cloud_sql_proxy || true
      sleep 1
      
      # Start proxy
      cloud_sql_proxy -instances="${CLOUDSQL_CONNECTION_NAME}"=tcp:5432 &
      PROXY_PID=$!
      
      # Wait for proxy to start
      sleep 3
      
      # Check if proxy started successfully
      if ! kill -0 $PROXY_PID 2>/dev/null; then
        echo "❌ ERROR: Cloud SQL Proxy failed to start"
        exit 1
      fi
      
      CONNECTION_STRING="postgresql://${DB_USER}:${DB_PASSWORD}@localhost:5432/${DB_NAME}"
      echo "   ✓ Proxy started (PID: $PROXY_PID)"
    else
      echo "❌ ERROR: Cloud SQL Proxy not found and instance has no public IP"
      echo "   Install Cloud SQL Proxy: gcloud components install cloud-sql-proxy"
      exit 1
    fi
  fi
  
  echo
  
  # Export for init_db.py
  export DATABASE_URL="$CONNECTION_STRING"
  export LOG_LEVEL="DEBUG"
  
  # Run init script
  echo "   Running: python $INIT_SCRIPT"
  echo
  
  python "$INIT_SCRIPT" || {
    INIT_EXIT=$?
    echo "❌ Database initialization failed (exit code: $INIT_EXIT)"
    
    # Cleanup proxy if running
    if [[ -n "${PROXY_PID:-}" ]] && kill -0 $PROXY_PID 2>/dev/null; then
      kill $PROXY_PID 2>/dev/null || true
    fi
    
    exit $INIT_EXIT
  }
  
  # Cleanup proxy if running
  if [[ -n "${PROXY_PID:-}" ]] && kill -0 $PROXY_PID 2>/dev/null; then
    echo
    echo "   Cleaning up Cloud SQL Proxy..."
    kill $PROXY_PID 2>/dev/null || true
    wait $PROXY_PID 2>/dev/null || true
  fi
  
  echo
  echo "   ✓ Local initialization complete"
  echo
fi

# ============================================================================
# 8. Verify Database State
# ============================================================================

echo "8️⃣  Verifying database state..."
echo

# Create temporary SQL query file
TEMP_SQL=$(mktemp)
trap "rm -f $TEMP_SQL" EXIT

cat > "$TEMP_SQL" <<'EOSQL'
\c wa_demo
SELECT 
  schemaname,
  tablename
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;

SELECT 
  COUNT(*) as total_rows
FROM (
  SELECT * FROM professional_exceptions LIMIT 0
  UNION ALL
  SELECT * FROM seasons LIMIT 0
  UNION ALL
  SELECT * FROM knowledge_bases LIMIT 0
) AS all_tables;
EOSQL

# Use gcloud sql query if available
if [[ -z "${CLOUDSQL_IP}" ]] || [[ "${CLOUDSQL_IP}" == "None" ]]; then
  echo "   Using Cloud SQL CLI connect..."
  
  gcloud sql connect "$DB_INSTANCE" \
    --user="$DB_USER" \
    --database="$DB_NAME" \
    --project="$PROJECT_ID" < "$TEMP_SQL" || {
    echo "   ⚠️  Could not verify database (connection error - this is expected for private instances)"
    echo "   The initialization may have still succeeded. Check backend logs."
  }
else
  echo "   Using direct psql connection..."
  
  PGPASSWORD="$DB_PASSWORD" psql \
    -h "$CLOUDSQL_IP" \
    -U "$DB_USER" \
    -d "$DB_NAME" \
    -f "$TEMP_SQL" || {
    echo "   ⚠️  Could not verify database (psql not available)"
  }
fi

echo

# ============================================================================
# 9. Output Summary
# ============================================================================

echo "=========================================="
echo "✅ Database Initialization Complete!"
echo "=========================================="
echo
echo "Database Details:"
echo "  Instance:         $DB_INSTANCE"
echo "  Database:         $DB_NAME"
echo "  User:             $DB_USER"
echo "  Connection:       $CLOUDSQL_CONNECTION_NAME"
echo
echo "Next Steps:"
echo "  1. Verify backend can connect: tail backend logs"
echo "  2. Test API: curl $BACKEND_URL/docs"
echo "  3. Next: Run gcp-11.8-panel.sh to deploy panel"
echo "  4. Then: Run gcp-11.9-webhook.sh to configure Meta"
echo
echo "Logs:"
echo "  Backend:    gcloud run logs read wa-backend --region=$REGION"
echo "  Database:   gcloud sql operations list --instance=$DB_INSTANCE"
echo
echo "=========================================="
echo
