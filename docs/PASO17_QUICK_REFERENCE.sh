#!/bin/bash
# PASO 17: Quick Reference - Comandos y Ejemplos
# Uso: Guardar este archivo y ejecutar ./PASO17_QUICK_REFERENCE.sh

set -e  # Exit on error

echo "🚀 PASO 17: Quick Reference"
echo "================================================"

# ============================================================================
# 1. LISTAR ENDPOINTS EXISTENTES
# ============================================================================

echo ""
echo "1️⃣  Listar endpoints configurados:"
echo "-----------------------------------"

curl -X GET http://localhost:8000/api/v1/admin/notify/endpoints \
  -H "Authorization: Bearer your_admin_token" \
  -H "Content-Type: application/json" \
  -s | jq '.'

# ============================================================================
# 2. REGISTRAR ENDPOINT SLACK
# ============================================================================

echo ""
echo "2️⃣  Registrar endpoint Slack:"
echo "------------------------------"

curl -X POST http://localhost:8000/api/v1/admin/notify/endpoints \
  -H "Authorization: Bearer your_admin_token" \
  -H "Content-Type: application/json" \
  -d '{
    "kind": "slack",
    "target": "https://hooks.slack.com/services/T123456789/B123456789/xxxxxxxxxxx",
    "enabled": true,
    "filters": {
      "events": ["reservation.created", "reservation.cancelled", "handoff.opened"],
      "intents": null
    },
    "secret": null
  }' \
  -s | jq '.'

# ============================================================================
# 3. REGISTRAR ENDPOINT EMAIL
# ============================================================================

echo ""
echo "3️⃣  Registrar endpoint Email:"
echo "------------------------------"

curl -X POST http://localhost:8000/api/v1/admin/notify/endpoints \
  -H "Authorization: Bearer your_admin_token" \
  -H "Content-Type: application/json" \
  -d '{
    "kind": "email",
    "target": "manager@restaurant.com",
    "enabled": true,
    "filters": {
      "events": ["reservation.created", "sla.breached"],
      "intents": null
    },
    "secret": null
  }' \
  -s | jq '.'

# ============================================================================
# 4. REGISTRAR ENDPOINT WEBHOOK (con HMAC)
# ============================================================================

echo ""
echo "4️⃣  Registrar endpoint Webhook (CRM):"
echo "--------------------------------------"

curl -X POST http://localhost:8000/api/v1/admin/notify/endpoints \
  -H "Authorization: Bearer your_admin_token" \
  -H "Content-Type: application/json" \
  -d '{
    "kind": "webhook",
    "target": "https://crm.company.com/webhook/reservations",
    "enabled": true,
    "filters": {
      "events": ["reservation.created", "reservation.modified", "reservation.cancelled"],
      "intents": ["reservar", "modificar", "cancelar"]
    },
    "secret": "sk_prod_1234567890abcdef1234567890abcdef"
  }' \
  -s | jq '.'

# ============================================================================
# 5. PROBAR ENDPOINT (envía test.ping)
# ============================================================================

echo ""
echo "5️⃣  Probar endpoint (ID=1):"
echo "------------------------------"

curl -X POST http://localhost:8000/api/v1/admin/notify/test/1 \
  -H "Authorization: Bearer your_admin_token" \
  -s | jq '.'

# ============================================================================
# 6. HABILITAR/DESHABILITAR ENDPOINT
# ============================================================================

echo ""
echo "6️⃣  Toggle endpoint (ID=1):"
echo "------------------------------"

curl -X POST http://localhost:8000/api/v1/admin/notify/endpoints/1/toggle \
  -H "Authorization: Bearer your_admin_token" \
  -s | jq '.'

# ============================================================================
# 7. ELIMINAR ENDPOINT
# ============================================================================

echo ""
echo "7️⃣  Eliminar endpoint (ID=1):"
echo "------------------------------"

# Descomenta para ejecutar:
# curl -X DELETE http://localhost:8000/api/v1/admin/notify/endpoints/1 \
#   -H "Authorization: Bearer your_admin_token" \
#   -s | jq '.'

echo "# Comando comentado para evitar eliminación accidental"
echo "curl -X DELETE http://localhost:8000/api/v1/admin/notify/endpoints/1 \\"
echo "  -H \"Authorization: Bearer your_admin_token\""

# ============================================================================
# 8. EJECUTAR REMINDERS JOB
# ============================================================================

echo ""
echo "8️⃣  Ejecutar Reminders Job:"
echo "------------------------------"

curl -X POST http://localhost:8000/api/v1/admin/jobs/reminders \
  -H "Authorization: Bearer your_admin_token" \
  -s | jq '.'

# ============================================================================
# 9. EJECUTAR SLA WATCH JOB
# ============================================================================

echo ""
echo "9️⃣  Ejecutar SLA Watch Job:"
echo "------------------------------"

curl -X POST http://localhost:8000/api/v1/admin/jobs/sla-watch \
  -H "Authorization: Bearer your_admin_token" \
  -s | jq '.'

# ============================================================================
# 10. VER LOGS DE NOTIFICACIONES
# ============================================================================

echo ""
echo "🔟 Ver logs (últimos 20):"
echo "------------------------------"

curl -X GET "http://localhost:8000/api/v1/admin/notify/logs?limit=20" \
  -H "Authorization: Bearer your_admin_token" \
  -s | jq '.'

# ============================================================================
# NOTAS
# ============================================================================

cat <<EOF

📝 NOTAS IMPORTANTES:
=====================

1. Reemplaza "your_admin_token" con tu Bearer token real

2. URLs de ejemplo:
   - Local: http://localhost:8000/api/v1/...
   - Cloud Run: https://whatsapp-ia-xxx.run.app/api/v1/...

3. Webhook URL en Slack:
   https://api.slack.com/messaging/webhooks

4. Para webhooks con HMAC:
   - Secret mínimo 32 caracteres
   - Verificar X-Signature en receptor

5. Filtros opcionales:
   - Si "events" está vacío → recibe TODOS los eventos
   - Si "intents" está null → no filtra por intención

6. Eventos disponibles:
   - reservation.created
   - reservation.modified
   - reservation.cancelled
   - reservation.confirmed
   - reminder.24h.sent
   - reminder.2h.sent
   - reminder.no_show
   - handoff.opened
   - sla.breached
   - incident.sla_cluster
   - test.ping

EOF

echo ""
echo "✅ Script completado"
