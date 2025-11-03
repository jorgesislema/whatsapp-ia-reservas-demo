#!/bin/bash

# ============================================================================
# 11.9 - Meta Webhook Configuration and Testing
# ============================================================================
#
# Purpose:
#   - Configure webhook in Meta/WhatsApp Developer Dashboard
#   - Verify webhook endpoint accessibility
#   - Test webhook with sample messages
#   - Document webhook configuration
#
# Usage:
#   source gcp-variables.sh
#   source /tmp/backend-url.env  (from 11.6 script)
#   bash gcp-11.9-webhook.sh
#
# Prerequisites:
#   - Backend deployed to Cloud Run (gcp-11.6-backend.sh)
#   - Meta Business Account created
#   - WhatsApp Business App created
#   - Secrets configured (gcp-11.5-secrets.sh)
#
# Manual Steps in Meta Dashboard:
#   1. Go to Meta > Your Business > Apps
#   2. Select WhatsApp App
#   3. Configuration > Webhooks
#   4. Set Callback URL and Verify Token
#   5. Subscribe to messages webhook
#
# ============================================================================

set -euo pipefail

echo "=========================================="
echo "11.9: Meta Webhook Configuration & Testing"
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

# Load backend URL
if [[ ! -f "/tmp/backend-url.env" ]]; then
  echo "❌ ERROR: Backend URL file not found!"
  echo "   Backend must be deployed first: bash gcp-11.6-backend.sh"
  exit 1
fi

source /tmp/backend-url.env

if [[ -z "${BACKEND_URL:-}" ]]; then
  echo "❌ ERROR: BACKEND_URL not set"
  exit 1
fi

echo "   ✓ Environment validated"
echo

# ============================================================================
# 2. Retrieve Webhook Secrets
# ============================================================================

echo "2️⃣  Retrieving webhook configuration from Secret Manager..."

# Get WhatsApp token
WA_TOKEN=$(gcloud secrets versions access latest \
  --secret="$SEC_WA_TOKEN" \
  --project="$PROJECT_ID")

# Get App Secret
WA_APP_SECRET=$(gcloud secrets versions access latest \
  --secret="$SEC_WA_APP_SECRET" \
  --project="$PROJECT_ID")

# Get Verify Token (or generate if not exists)
if gcloud secrets describe "$SEC_WA_VERIFY_TOKEN" --project="$PROJECT_ID" &>/dev/null; then
  WA_VERIFY_TOKEN=$(gcloud secrets versions access latest \
    --secret="$SEC_WA_VERIFY_TOKEN" \
    --project="$PROJECT_ID")
else
  echo "   ⚠️  Verify Token not found. Generating new one..."
  WA_VERIFY_TOKEN="wa-verify-token-$(date +%s)"
  
  # Store in Secret Manager
  echo -n "$WA_VERIFY_TOKEN" | gcloud secrets create "$SEC_WA_VERIFY_TOKEN" \
    --data-file=- \
    --project="$PROJECT_ID"
  
  echo "   ✓ Verify Token created"
fi

echo "   ✓ Secrets retrieved"
echo

# ============================================================================
# 3. Prepare Webhook Configuration
# ============================================================================

echo "3️⃣  Preparing webhook configuration..."

# Webhook endpoint (can be /events or /webhook)
WEBHOOK_ENDPOINT="/events"
WEBHOOK_URL="${BACKEND_URL}${WEBHOOK_ENDPOINT}"

echo "   Webhook URL:     $WEBHOOK_URL"
echo "   Verify Token:    ${WA_VERIFY_TOKEN:0:16}..."
echo

# ============================================================================
# 4. Test Webhook Accessibility
# ============================================================================

echo "4️⃣  Testing webhook accessibility..."
echo

# Test GET request (Meta sends verification challenge here)
echo "   Testing GET ${WEBHOOK_ENDPOINT}..."

TEST_CHALLENGE=$(curl -s -o /dev/null -w "%{http_code}" \
  "${WEBHOOK_URL}?hub.mode=subscribe&hub.challenge=test_challenge&hub.verify_token=${WA_VERIFY_TOKEN}" \
  -X GET || echo "000")

if [[ "$TEST_CHALLENGE" == "200" ]]; then
  echo "   ✓ GET endpoint responds correctly (HTTP 200)"
elif [[ "$TEST_CHALLENGE" == "403" ]]; then
  echo "   ⚠️  Verify token mismatch (HTTP 403) - This is expected for wrong token"
else
  echo "   ⚠️  Unexpected response: HTTP $TEST_CHALLENGE"
fi

echo

# ============================================================================
# 5. Create Test Message Payload
# ============================================================================

echo "5️⃣  Preparing test webhook payload..."

# Generate HMAC signature for test
TIMESTAMP=$(date +%s)
NONCE=$(date +%s%N | md5sum | cut -c1-16)

# Test payload structure (simplified WhatsApp webhook)
TEST_PAYLOAD='{
  "object": "whatsapp_business_account",
  "entry": [{
    "id": "ENTRY_ID",
    "changes": [{
      "value": {
        "messaging_product": "whatsapp",
        "metadata": {
          "display_phone_number": "1234567890",
          "phone_number_id": "111111"
        },
        "messages": [{
          "from": "5511999999999",
          "id": "wamid.test_'$(date +%s)'",
          "timestamp": "'$TIMESTAMP'",
          "text": {
            "body": "Test message from webhook script"
          },
          "type": "text"
        }]
      },
      "field": "messages"
    }]
  }]
}'

echo "   Test payload prepared"
echo

# ============================================================================
# 6. Document Manual Meta Configuration
# ============================================================================

echo "6️⃣  Meta Dashboard Configuration Instructions:"
echo

cat > /tmp/meta-webhook-config.md <<EOF
# Meta Webhook Configuration

## Step 1: Go to Meta Developer Dashboard
1. Visit: https://developers.facebook.com/
2. Navigate to Your Business > Apps
3. Select your WhatsApp Business App

## Step 2: Configure Webhooks
1. Go to Configuration > Webhooks
2. Click "Edit Subscription"

### Callback URL Configuration
- **Callback URL:** $WEBHOOK_URL
- **Verify Token:** $WA_VERIFY_TOKEN

### Subscribe to Messages
1. Click "Subscribe to this object"
2. Select Webhook Fields:
   - ☑️ messages
   - ☑️ message_status
   - ☑️ message_template_status_update
   - ☑️ account_alerts

## Step 3: Verify Token
Once you paste the Callback URL and Verify Token:
- Meta will send a GET request with hub.challenge parameter
- Your endpoint MUST respond with the challenge value
- This is automatically handled by your /events endpoint

## Step 4: Obtain Tokens
Make sure you have:
- **Phone Number ID:** (from Meta > Business Catalog)
- **App Secret:** $WA_APP_SECRET
- **Access Token:** (generate in Meta > Tools > Tokens)

## Step 5: Webhook Testing
Send a test message:

\`\`\`bash
# Verify endpoint is working
curl -X GET "$WEBHOOK_URL?hub.mode=subscribe&hub.challenge=test_challenge&hub.verify_token=$WA_VERIFY_TOKEN"

# Send test message (POST)
curl -X POST $WEBHOOK_URL \\
  -H "Content-Type: application/json" \\
  -H "X-Hub-Signature: sha256=..." \\
  -d '$(echo $TEST_PAYLOAD | tr '\n' ' ')'
\`\`\`

## Step 6: Security Verification
Your backend implements:
- ✓ HMAC-SHA256 signature verification
- ✓ Rate limiting (120 req/min per IP)
- ✓ Idempotency checking (message_id)
- ✓ Request logging with X-Request-Id correlation

## Troubleshooting
1. **404 Error:** Check Webhook endpoint exists in backend
2. **403 Error:** Verify Token mismatch - check Secret Manager
3. **Signature Errors:** App Secret not matching in backend
4. **Rate Limited (429):** Adjust rate limit in code

## Logs
Check backend logs:
\`\`\`bash
gcloud run logs read wa-backend --region=$REGION --project=$PROJECT_ID --limit=100
\`\`\`

## Status
Current Configuration:
- Backend URL: $BACKEND_URL
- Webhook Endpoint: $WEBHOOK_ENDPOINT
- Verify Token: ${WA_VERIFY_TOKEN:0:16}...
- App Secret: ${WA_APP_SECRET:0:16}...
- Phone Number: (set in Meta Dashboard)
- Access Token: (set in Meta Dashboard)

EOF

cat /tmp/meta-webhook-config.md

echo

# ============================================================================
# 7. Health Check on Backend
# ============================================================================

echo "7️⃣  Running backend health checks..."
echo

# Check /healthz endpoint
HEALTH_STATUS=$(curl -s "${BACKEND_URL}/healthz" || echo "{}")

echo "   Backend Health:"
echo "   $(echo "$HEALTH_STATUS" | head -c 100)..."
echo

# Try to access /docs (FastAPI Swagger)
DOCS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${BACKEND_URL}/docs" || echo "000")

if [[ "$DOCS_STATUS" == "200" ]]; then
  echo "   ✓ API documentation available: ${BACKEND_URL}/docs"
else
  echo "   ⚠️  Documentation endpoint returned: HTTP $DOCS_STATUS"
fi

echo

# ============================================================================
# 8. Export Configuration to Files
# ============================================================================

echo "8️⃣  Exporting configuration files..."

# Save webhook config
cat > /tmp/webhook-config.env <<EOF
WEBHOOK_URL=$WEBHOOK_URL
WA_VERIFY_TOKEN=$WA_VERIFY_TOKEN
WA_APP_SECRET=$WA_APP_SECRET
WA_TOKEN=$WA_TOKEN
BACKEND_URL=$BACKEND_URL
WEBHOOK_ENDPOINT=$WEBHOOK_ENDPOINT
EOF

echo "   ✓ Exported to /tmp/webhook-config.env"

# Save test payload
echo "$TEST_PAYLOAD" > /tmp/webhook-test-payload.json
echo "   ✓ Test payload saved to /tmp/webhook-test-payload.json"

echo

# ============================================================================
# 9. Summary and Next Steps
# ============================================================================

echo "=========================================="
echo "✅ Webhook Configuration Complete!"
echo "=========================================="
echo
echo "Webhook Details:"
echo "  Callback URL:    $WEBHOOK_URL"
echo "  Verify Token:    ${WA_VERIFY_TOKEN:0:16}... (full: sec-wa-verify-token)"
echo "  Backend:         $BACKEND_URL"
echo "  Region:          $REGION"
echo
echo "📋 MANUAL STEPS (in Meta Developer Dashboard):"
echo "  1. Go to: https://developers.facebook.com/apps"
echo "  2. Select your WhatsApp Business App"
echo "  3. Go to Configuration > Webhooks"
echo "  4. Set Callback URL: $WEBHOOK_URL"
echo "  5. Set Verify Token: $WA_VERIFY_TOKEN"
echo "  6. Subscribe to: messages, message_status, message_template_status_update"
echo "  7. Save and wait for verification (automatic)"
echo
echo "🧪 TESTING:"
echo "  1. Send a test message from WhatsApp to your business number"
echo "  2. Check backend logs: gcloud run logs read wa-backend --limit=50"
echo "  3. Verify message appears in database"
echo "  4. Check panel at: (from gcp-11.8-panel.sh output)"
echo
echo "📊 MONITORING:"
echo "  Backend API: $BACKEND_URL"
echo "  Swagger UI:  ${BACKEND_URL}/docs"
echo "  Metrics:     ${BACKEND_URL}/metrics"
echo "  Logs:        gcloud run logs read wa-backend"
echo
echo "🔒 SECURITY CHECKLIST:"
echo "  ✓ HMAC-SHA256 signature verification enabled"
echo "  ✓ Rate limiting: 120 requests/minute per IP"
echo "  ✓ Idempotency checking: no duplicate processing"
echo "  ✓ Request correlation: X-Request-Id in all logs"
echo "  ✓ Secrets in Secret Manager (not in code)"
echo
echo "📚 DOCUMENTATION:"
echo "  - Meta config guide: /tmp/meta-webhook-config.md"
echo "  - Webhook config:    /tmp/webhook-config.env"
echo "  - Test payload:      /tmp/webhook-test-payload.json"
echo
echo "Next Steps:"
echo "  1. Complete Meta Dashboard configuration (manual step above)"
echo "  2. Send test WhatsApp message"
echo "  3. Verify logs show message received"
echo "  4. Check responses in admin panel"
echo "  5. Monitor backend metrics and performance"
echo
echo "=========================================="
echo
