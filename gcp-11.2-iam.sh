#!/bin/bash
# ============================================================================
# 11.2 SERVICE ACCOUNTS E IAM BINDINGS
# ============================================================================
#
# Crea service accounts separadas para backend y panel, con IAM roles mínimos.
#
# Uso:
#   source gcp-variables.sh
#   bash gcp-11.2-iam.sh
#
# ============================================================================

set -euo pipefail

echo "═══════════════════════════════════════════════════════════════"
echo "11.2 Creando Service Accounts e IAM Bindings"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Verificar variables
if [ -z "$PROJECT_ID" ] || [ -z "$BACKEND_SVC" ]; then
  echo "❌ Error: variables no cargadas. Ejecuta: source gcp-variables.sh"
  exit 1
fi

confirm_vars

# ============================================================================
# Crear Service Accounts
# ============================================================================

echo "Creando Service Accounts..."
echo ""

# Backend SA
if gcloud iam service-accounts describe "${BACKEND_SVC}@${PROJECT_ID}.iam.gserviceaccount.com" &>/dev/null; then
  echo "  ⓘ Service Account '${BACKEND_SVC}' ya existe"
else
  echo "  Creando '${BACKEND_SVC}'..."
  gcloud iam service-accounts create "$BACKEND_SVC" \
    --display-name="Service Account para Backend (FastAPI)"
  echo "  ✅ '${BACKEND_SVC}' creado"
fi

# Panel SA
if gcloud iam service-accounts describe "${PANEL_SVC}@${PROJECT_ID}.iam.gserviceaccount.com" &>/dev/null; then
  echo "  ⓘ Service Account '${PANEL_SVC}' ya existe"
else
  echo "  Creando '${PANEL_SVC}'..."
  gcloud iam service-accounts create "$PANEL_SVC" \
    --display-name="Service Account para Panel (Streamlit)"
  echo "  ✅ '${PANEL_SVC}' creado"
fi

echo ""

# ============================================================================
# IAM Bindings para Backend
# ============================================================================

echo "Configurando permisos para Backend..."
echo ""

BACKEND_SA="${BACKEND_SVC}@${PROJECT_ID}.iam.gserviceaccount.com"

# Roles para Backend (Cloud SQL + Secret Manager)
BACKEND_ROLES=(
  "roles/run.invoker"                      # Invocar Cloud Run
  "roles/cloudsql.client"                  # Conectar a Cloud SQL
  "roles/secretmanager.secretAccessor"     # Acceder secretos
)

for role in "${BACKEND_ROLES[@]}"; do
  echo "  Asignando ${role}..."
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${BACKEND_SA}" \
    --role="$role" \
    --condition=None \
    --quiet
done

echo "  ✅ Permisos backend configurados"
echo ""

# ============================================================================
# IAM Bindings para Panel
# ============================================================================

echo "Configurando permisos para Panel..."
echo ""

PANEL_SA="${PANEL_SVC}@${PROJECT_ID}.iam.gserviceaccount.com"

# Roles para Panel (Secret Manager + invocar backend si lo necesita)
PANEL_ROLES=(
  "roles/run.invoker"                      # Invocar Cloud Run (backend)
  "roles/secretmanager.secretAccessor"     # Acceder secretos del panel
)

for role in "${PANEL_ROLES[@]}"; do
  echo "  Asignando ${role}..."
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${PANEL_SA}" \
    --role="$role" \
    --condition=None \
    --quiet
done

echo "  ✅ Permisos panel configurados"
echo ""

# ============================================================================
# Verificación
# ============================================================================

echo "Verificando Service Accounts..."
echo ""

echo "Backend SA:"
gcloud iam service-accounts describe "$BACKEND_SA" \
  --format="value(email, displayName)"

echo ""
echo "Panel SA:"
gcloud iam service-accounts describe "$PANEL_SA" \
  --format="value(email, displayName)"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ Service Accounts e IAM configurados"
echo ""
echo "Próximo paso: bash gcp-11.3-cloudsql.sh"
echo "═══════════════════════════════════════════════════════════════"
