#!/bin/bash
# ============================================================================
# 11.4 SERVERLESS VPC ACCESS CONNECTOR
# ============================================================================
#
# Crea VPC Connector para que Cloud Run acceda a Cloud SQL (IP privada).
#
# Uso:
#   source gcp-variables.sh
#   bash gcp-11.4-vpc.sh
#
# ============================================================================

set -euo pipefail

echo "═══════════════════════════════════════════════════════════════"
echo "11.4 Creando Serverless VPC Connector"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Verificar variables
if [ -z "$PROJECT_ID" ] || [ -z "$VPC_CON" ] || [ -z "$REGION" ]; then
  echo "❌ Error: variables no cargadas. Ejecuta: source gcp-variables.sh"
  exit 1
fi

confirm_vars

# ============================================================================
# Crear VPC Connector
# ============================================================================

echo "Creando Serverless VPC Connector '$VPC_CON'..."
echo ""
echo "  Rango de IP: $VPC_RANGE"
echo "  Región: $REGION"
echo ""

if gcloud compute networks vpc-access connectors describe "$VPC_CON" \
    --region="$REGION" \
    --project="$PROJECT_ID" &>/dev/null; then
  echo "  ⓘ VPC Connector '$VPC_CON' ya existe"
else
  echo "  Creando connector (toma ~5 minutos)..."
  gcloud compute networks vpc-access connectors create "$VPC_CON" \
    --region="$REGION" \
    --network=default \
    --range="$VPC_RANGE" \
    --project="$PROJECT_ID"

  echo "  ✅ VPC Connector '$VPC_CON' creado"
fi

echo ""

# ============================================================================
# Verificar estado
# ============================================================================

echo "Estado del VPC Connector:"
echo ""

gcloud compute networks vpc-access connectors describe "$VPC_CON" \
  --region="$REGION" \
  --project="$PROJECT_ID" \
  --format="table(
    name,
    region,
    network,
    ipCidrRange,
    state
  )"

echo ""

# ============================================================================
# Información de uso
# ============================================================================

echo "Para usar en Cloud Run:"
echo ""
echo "  gcloud run deploy <SERVICE> \\"
echo "    ... \\"
echo "    --vpc-connector ${VPC_CON} \\"
echo "    ..."
echo ""

echo "═══════════════════════════════════════════════════════════════"
echo "✅ VPC Connector configurado"
echo ""
echo "Próximo paso: bash gcp-11.5-secrets.sh"
echo "═══════════════════════════════════════════════════════════════"
