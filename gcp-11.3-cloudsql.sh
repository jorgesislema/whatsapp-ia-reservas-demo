#!/bin/bash
# ============================================================================
# 11.3 CLOUD SQL POSTGRES (IP PRIVADA + CREDENCIALES)
# ============================================================================
#
# Crea instancia Cloud SQL Postgres con IP privada, base de datos y usuario.
#
# Uso:
#   source gcp-variables.sh
#   bash gcp-11.3-cloudsql.sh
#
# Nota: Cloud Run necesitará VPC Connector para conectarse (11.4).
#
# ============================================================================

set -euo pipefail

echo "═══════════════════════════════════════════════════════════════"
echo "11.3 Creando Cloud SQL Postgres (IP privada)"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Verificar variables
if [ -z "$PROJECT_ID" ] || [ -z "$DB_INSTANCE" ]; then
  echo "❌ Error: variables no cargadas. Ejecuta: source gcp-variables.sh"
  exit 1
fi

confirm_vars

# ============================================================================
# Crear instancia Cloud SQL
# ============================================================================

echo "Creando instancia Cloud SQL Postgres..."
echo ""

if gcloud sql instances describe "$DB_INSTANCE" --project="$PROJECT_ID" &>/dev/null; then
  echo "  ⓘ Instancia '$DB_INSTANCE' ya existe"
else
  echo "  Creando instancia (esto toma ~5-10 minutos)..."
  gcloud sql instances create "$DB_INSTANCE" \
    --project="$PROJECT_ID" \
    --database-version="$DB_VERSION" \
    --region="$REGION" \
    --network=default \
    --no-assign-ip \
    --storage-size=20GB \
    --tier=db-f1-micro \
    --storage-auto-increase \
    --backup-start-time=03:00 \
    --retained-backups-count=7 \
    --transaction-log-retention-days=7

  echo "  ✅ Instancia creada (espera validación interna de GCP)"
fi

echo ""

# ============================================================================
# Crear base de datos
# ============================================================================

echo "Creando base de datos '$DB_NAME'..."
echo ""

if gcloud sql databases describe "$DB_NAME" \
    --instance="$DB_INSTANCE" \
    --project="$PROJECT_ID" &>/dev/null; then
  echo "  ⓘ Base de datos '$DB_NAME' ya existe"
else
  echo "  Creando DB..."
  gcloud sql databases create "$DB_NAME" \
    --instance="$DB_INSTANCE" \
    --project="$PROJECT_ID" \
    --charset=UTF8 \
    --collation=en_US.utf8

  echo "  ✅ Base de datos '$DB_NAME' creada"
fi

echo ""

# ============================================================================
# Crear usuario de base de datos
# ============================================================================

echo "Creando usuario '$DB_USER'..."
echo ""

# Verificar si el usuario ya existe
if gcloud sql users describe "$DB_USER" \
    --instance="$DB_INSTANCE" \
    --project="$PROJECT_ID" &>/dev/null; then
  echo "  ⓘ Usuario '$DB_USER' ya existe"
  echo "  Actualizando contraseña..."
  gcloud sql users set-password "$DB_USER" \
    --instance="$DB_INSTANCE" \
    --project="$PROJECT_ID" \
    --password="$DB_PASS"
else
  echo "  Creando usuario con contraseña..."
  gcloud sql users create "$DB_USER" \
    --instance="$DB_INSTANCE" \
    --project="$PROJECT_ID" \
    --password="$DB_PASS"

  echo "  ✅ Usuario '$DB_USER' creado"
fi

echo ""

# ============================================================================
# Información de conexión
# ============================================================================

echo "Información de conexión local (para init):"
echo ""

# Obtener IP privada
PRIVATE_IP=$(gcloud sql instances describe "$DB_INSTANCE" \
  --project="$PROJECT_ID" \
  --format="value(ipAddresses[0].ipAddress)")

echo "  Instancia: $DB_INSTANCE"
echo "  IP privada: $PRIVATE_IP"
echo "  Base de datos: $DB_NAME"
echo "  Usuario: $DB_USER"
echo "  Contraseña: ${DB_PASS:0:5}... (oscurecida)"
echo ""

echo "Connection string para Python (socket con Cloud SQL Proxy):"
echo "  postgresql+pg8000://${DB_USER}:${DB_PASS}@/${DB_NAME}?unix_sock=/cloudsql/${PROJECT_ID}:${REGION}:${DB_INSTANCE}/.s.PGSQL.5432"
echo ""

echo "Connection string para psql (desde máquina con Cloud SQL Proxy):"
echo "  psql -h localhost -U $DB_USER -d $DB_NAME"
echo "  (necesita: cloud_sql_proxy -instances=${PROJECT_ID}:${REGION}:${DB_INSTANCE}=tcp:5432)"
echo ""

echo "═══════════════════════════════════════════════════════════════"
echo "✅ Cloud SQL Postgres configurado"
echo ""
echo "Próximo paso: bash gcp-11.4-vpc.sh"
echo "═══════════════════════════════════════════════════════════════"
