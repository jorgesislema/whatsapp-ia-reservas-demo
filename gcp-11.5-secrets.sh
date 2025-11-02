#!/bin/bash
# ============================================================================
# 11.5 SECRET MANAGER (TOKENS Y CREDENCIALES)
# ============================================================================
#
# Crea secretos en Google Secret Manager para:
# - WhatsApp Token (Meta Graph API)
# - WhatsApp App Secret (para firmar webhook)
# - Admin API Token (panel → backend)
# - Contraseña PostgreSQL
#
# Uso:
#   source gcp-variables.sh
#   bash gcp-11.5-secrets.sh
#
# ============================================================================

set -euo pipefail

echo "═══════════════════════════════════════════════════════════════"
echo "11.5 Creando Secretos en Secret Manager"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Verificar variables
if [ -z "$PROJECT_ID" ] || [ -z "$DB_PASS" ]; then
  echo "❌ Error: variables no cargadas. Ejecuta: source gcp-variables.sh"
  exit 1
fi

echo "Variables de secretos:"
echo "  SEC_WA_TOKEN: $SEC_WA_TOKEN"
echo "  SEC_WA_APP_SECRET: $SEC_WA_APP_SECRET"
echo "  SEC_ADMIN_TOKEN: $SEC_ADMIN_TOKEN"
echo "  SEC_DB_PASS: $SEC_DB_PASS"
echo ""
echo "⚠️  Estos secretos se guardarán en Secret Manager de GCP"
echo "    Necesitarás proporcionar valores para WhatsApp tokens"
echo ""

read -p "¿Continuar? (s/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Ss]$ ]]; then
  echo "Cancelado."
  exit 1
fi

echo ""

# ============================================================================
# Crear/Actualizar Secretos
# ============================================================================

echo "Guardando secretos en Secret Manager..."
echo ""

# 1. Contraseña PostgreSQL
echo "1. Guardando contraseña PostgreSQL..."
if gcloud secrets describe "$SEC_DB_PASS" --project="$PROJECT_ID" &>/dev/null; then
  echo "   Actualizando versión..."
  echo -n "$DB_PASS" | gcloud secrets versions add "$SEC_DB_PASS" \
    --data-file=- \
    --project="$PROJECT_ID"
else
  echo "   Creando secreto..."
  echo -n "$DB_PASS" | gcloud secrets create "$SEC_DB_PASS" \
    --data-file=- \
    --project="$PROJECT_ID" \
    --replication-policy="user-managed" \
    --locations="$REGION"
fi
echo "   ✅ '$SEC_DB_PASS' guardado"
echo ""

# 2. Admin API Token
echo "2. Guardando Admin API Token..."
ADMIN_TOKEN="super-secret-panel-admin-$(date +%s)"  # Generar token único

if gcloud secrets describe "$SEC_ADMIN_TOKEN" --project="$PROJECT_ID" &>/dev/null; then
  echo "   Actualizando versión..."
  echo -n "$ADMIN_TOKEN" | gcloud secrets versions add "$SEC_ADMIN_TOKEN" \
    --data-file=- \
    --project="$PROJECT_ID"
else
  echo "   Creando secreto..."
  echo -n "$ADMIN_TOKEN" | gcloud secrets create "$SEC_ADMIN_TOKEN" \
    --data-file=- \
    --project="$PROJECT_ID"
fi
echo "   ✅ '$SEC_ADMIN_TOKEN' guardado"
echo "   Token: $ADMIN_TOKEN"
echo ""

# 3. WhatsApp App Secret
echo "3. Configurando WhatsApp App Secret..."
echo ""
echo "   ⚠️  Este es el 'App Secret' de Meta para verificar firmas webhook"
echo "   Encuentra en: https://developers.facebook.com/apps → tu app → Settings → Basic"
echo ""

read -p "Ingresa WhatsApp App Secret (o ENTER para usar valor de prueba): " WA_APP_SECRET_INPUT
if [ -z "$WA_APP_SECRET_INPUT" ]; then
  WA_APP_SECRET_INPUT="test_app_secret_$(date +%s)"
  echo "Usando valor de prueba: $WA_APP_SECRET_INPUT"
fi

if gcloud secrets describe "$SEC_WA_APP_SECRET" --project="$PROJECT_ID" &>/dev/null; then
  echo "   Actualizando versión..."
  echo -n "$WA_APP_SECRET_INPUT" | gcloud secrets versions add "$SEC_WA_APP_SECRET" \
    --data-file=- \
    --project="$PROJECT_ID"
else
  echo "   Creando secreto..."
  echo -n "$WA_APP_SECRET_INPUT" | gcloud secrets create "$SEC_WA_APP_SECRET" \
    --data-file=- \
    --project="$PROJECT_ID"
fi
echo "   ✅ '$SEC_WA_APP_SECRET' guardado"
echo ""

# 4. WhatsApp Token (Graph API)
echo "4. Configurando WhatsApp Token..."
echo ""
echo "   ⚠️  Este es el 'Access Token' de Meta para llamar Graph API"
echo "   Encuentra en: https://developers.facebook.com/apps → tu app → Messenger API → Settings"
echo ""

read -p "Ingresa WhatsApp Access Token (o ENTER para usar valor de prueba): " WA_TOKEN_INPUT
if [ -z "$WA_TOKEN_INPUT" ]; then
  WA_TOKEN_INPUT="test_token_$(date +%s)"
  echo "Usando valor de prueba: $WA_TOKEN_INPUT"
fi

if gcloud secrets describe "$SEC_WA_TOKEN" --project="$PROJECT_ID" &>/dev/null; then
  echo "   Actualizando versión..."
  echo -n "$WA_TOKEN_INPUT" | gcloud secrets versions add "$SEC_WA_TOKEN" \
    --data-file=- \
    --project="$PROJECT_ID"
else
  echo "   Creando secreto..."
  echo -n "$WA_TOKEN_INPUT" | gcloud secrets create "$SEC_WA_TOKEN" \
    --data-file=- \
    --project="$PROJECT_ID"
fi
echo "   ✅ '$SEC_WA_TOKEN' guardado"
echo ""

# ============================================================================
# Dar permisos a Service Accounts
# ============================================================================

echo "Dando permisos a Service Accounts para acceder secretos..."
echo ""

BACKEND_SA="${BACKEND_SVC}@${PROJECT_ID}.iam.gserviceaccount.com"
PANEL_SA="${PANEL_SVC}@${PROJECT_ID}.iam.gserviceaccount.com"

# Backend accede a todos los secretos
for secret in "$SEC_WA_TOKEN" "$SEC_WA_APP_SECRET" "$SEC_ADMIN_TOKEN" "$SEC_DB_PASS"; do
  gcloud secrets add-iam-policy-binding "$secret" \
    --member="serviceAccount:${BACKEND_SA}" \
    --role="roles/secretmanager.secretAccessor" \
    --project="$PROJECT_ID" \
    --quiet
done

echo "  ✅ Backend puede acceder a todos los secretos"
echo ""

# Panel accede a ADMIN_TOKEN
gcloud secrets add-iam-policy-binding "$SEC_ADMIN_TOKEN" \
  --member="serviceAccount:${PANEL_SA}" \
  --role="roles/secretmanager.secretAccessor" \
  --project="$PROJECT_ID" \
  --quiet

echo "  ✅ Panel puede acceder a $SEC_ADMIN_TOKEN"
echo ""

# ============================================================================
# Listado de secretos
# ============================================================================

echo "Secretos guardados:"
echo ""

gcloud secrets list --project="$PROJECT_ID" --format="table(name, created, labels)"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ Secretos configurados en Secret Manager"
echo ""
echo "Admin Token guardado: $ADMIN_TOKEN"
echo "⚠️  Copia este token para configurar panel más tarde"
echo ""
echo "Próximo paso: bash gcp-11.6-backend.sh"
echo "═══════════════════════════════════════════════════════════════"
