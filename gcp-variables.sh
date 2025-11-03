#!/bin/bash
# ============================================================================
# PASO 11: DESPLIEGUE EN GOOGLE CLOUD
# ============================================================================
# 
# Script de configuración de infraestructura GCP para WhatsApp IA Reservas
# Incluye: Cloud SQL, Secret Manager, Cloud Run, VPC Connector, IAM
#
# Uso:
#   source gcp-variables.sh
#   # luego ejecutar scripts individuales (11.2, 11.3, etc.)
#
# Requisitos:
#   - gcloud CLI instalado y autenticado
#   - Permisos de propietario/editor en GCP
#   - Python 3.10+, Docker (para builds locales)
#
# ============================================================================

# ============================================================================
# 11.0 VARIABLES BASE - AJUSTA A TU PROYECTO
# ============================================================================

# Identificación del proyecto GCP
export PROJECT_ID="mi-proyecto-bot"          # CAMBIAR: tu project-id
export REGION="us-central1"                  # CAMBIAR: región preferida
export ZONE="${REGION}-a"

# Base de datos
export DB_INSTANCE="wa-pg"                   # Nombre instancia Cloud SQL
export DB_VERSION="POSTGRES_15"              # Versión PostgreSQL
export DB_NAME="wa_demo"                     # Nombre de la DB
export DB_USER="wa_user"                     # Usuario DB
export DB_PASS="Gen3ra_un4_cl4ve_segura"    # Contraseña fuerte (generar nueva)

# Conectividad
export VPC_NAME="default"                    # VPC (default para MVP)
export VPC_CON="wa-serverless-vpc"           # Nombre VPC Connector
export VPC_RANGE="10.8.0.0/28"               # Rango para connector

# Service Accounts
export BACKEND_SVC="wa-backend"              # SA para backend
export PANEL_SVC="wa-panel"                  # SA para panel

# Secretos (Secret Manager)
export SEC_WA_TOKEN="WA_TOKEN"               # Token de Meta/WhatsApp
export SEC_WA_APP_SECRET="WA_APP_SECRET"     # App Secret para firmar webhook
export SEC_ADMIN_TOKEN="ADMIN_API_TOKEN"     # Token para panel → backend
export SEC_DB_PASS="DB_PASSWORD"             # Contraseña PostgreSQL

# Cloud Run
export BACKEND_SVC_NAME="wa-backend"         # Nombre servicio Cloud Run
export PANEL_SVC_NAME="wa-panel"             # Nombre servicio panel

# Container Registry (Artifact Registry)
export ARTIFACT_REPO="whatsapp-bot"          # Repo en Artifact Registry
export IMAGE_TAG="latest"                    # Tag de imagen

# ============================================================================
# 11.1 CONFIGURACIÓN INICIAL Y HABILITACIÓN DE APIS
# ============================================================================

echo "═══════════════════════════════════════════════════════════════"
echo "PASO 11: Preparando infraestructura GCP"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Variables:"
echo "  PROJECT_ID: $PROJECT_ID"
echo "  REGION: $REGION"
echo "  DB_INSTANCE: $DB_INSTANCE"
echo ""

# Seleccionar proyecto
gcloud config set project $PROJECT_ID

# Habilitar APIs necesarias
echo "Habilitando APIs de GCP..."
gcloud services enable \
  run.googleapis.com \
  sqladmin.googleapis.com \
  secretmanager.googleapis.com \
  compute.googleapis.com \
  vpcaccess.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com

echo "✅ APIs habilitadas"
echo ""

# ============================================================================
# FUNCIONES AUXILIARES
# ============================================================================

# Función para confirmar variables antes de ejecutar
confirm_vars() {
  echo "Variables principales:"
  echo "  PROJECT_ID: $PROJECT_ID"
  echo "  REGION: $REGION"
  echo "  DB_INSTANCE: $DB_INSTANCE"
  echo "  DB_PASS: ${DB_PASS:0:5}... (oscurecida)"
  echo ""
  read -p "¿Continuar? (s/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Ss]$ ]]; then
    echo "Cancelado."
    exit 1
  fi
}

# Función para crear secret
create_secret() {
  local name=$1
  local value=$2
  
  if gcloud secrets describe "$name" &>/dev/null; then
    echo "  Secret '$name' ya existe. Actualizando..."
    echo -n "$value" | gcloud secrets versions add "$name" --data-file=-
  else
    echo "  Creando secret '$name'..."
    echo -n "$value" | gcloud secrets create "$name" --data-file=-
    echo "  ✅ Secret '$name' creado"
  fi
}

export -f confirm_vars
export -f create_secret

echo "✅ Función confirm_vars() y create_secret() disponibles"
echo ""
echo "Próximos pasos:"
echo "  1. source gcp-variables.sh"
echo "  2. bash gcp-11.2-iam.sh      # Service Accounts + IAM"
echo "  3. bash gcp-11.3-cloudsql.sh # Cloud SQL"
echo "  4. bash gcp-11.4-vpc.sh      # VPC Connector"
echo "  5. bash gcp-11.5-secrets.sh  # Secret Manager"
echo "  6. bash gcp-11.6-backend.sh  # Backend Cloud Run"
echo "  7. bash gcp-11.8-panel.sh    # Panel Streamlit"
echo ""
echo "═══════════════════════════════════════════════════════════════"
