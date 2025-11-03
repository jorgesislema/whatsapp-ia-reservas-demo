# Runbook: Mensajería WhatsApp 24h

## Resumen
Procedimiento para crear, publicar y mantener mensajes de plantilla en Meta WhatsApp Business API (24h window compliance).

## Audiencia
- Gerente de marketing
- Gerente de operaciones
- Admin panel

## Conceptos Clave

### Ventana de 24 horas

```
Timeline de una reserva:
├─ 12:00 - Cliente reserva (mensaje entrante desde cliente)
│   ├─ Ventana de 24h ABIERTA
│   └─ Podemos enviar mensajes de seguimiento sin template
│
├─ 12:05 - Confirmación de reserva (nosotros respondemos)
│   └─ ✅ Válida: dentro de ventana de 24h
│
├─ 18:00 - Recordatorio (nosotros iniciamos)
│   └─ ❌ Inválida: fuera de ventana 24h
│   └─ Solución: Usar plantilla pre-aprobada
│
└─ 36:00 (12:00 del día siguiente)
    └─ Ventana CERRADA: requiere plantilla para cualquier mensaje
```

### Tipos de Mensajes

| Tipo | Ejemplo | Requiere Template | Ventana |
|------|---------|-------------------|---------|
| **Response** | Confirmación de reserva | No | 24h |
| **Template** | Recordatorio de reserva | Sí | N/A (ilimitado) |
| **Manual** | Mensaje personalizado | No (pero violable) | 24h |
| **Broadcast** | Newsletter | Sí (REQUIRED) | N/A |

## Plantillas Disponibles

### 1. Confirmación de Reserva

**Nombre:** `reservation_confirmed`

```
Texto:
---
¡Hola {{name}}! 👋

Tu reserva ha sido confirmada ✅

📅 {{date}}
🕐 {{time}}
👥 {{party_size}} personas
📍 {{location}}

Tu código: {{confirmation_code}}

¿Alguna pregunta? Escribe "ayuda"
---

Variables:
- name: Nombre cliente
- date: Fecha formateada (14/01/2024)
- time: Hora (20:30)
- party_size: Número de personas (4)
- location: Zona del restaurante (terraza, interior, etc)
- confirmation_code: Código único (ABC123)
```

**Estado:** ✅ APPROVED (Meta)
**Uso:** Después de que cliente hace reserva

### 2. Recordatorio Previo

**Nombre:** `reservation_reminder_24h`

```
Texto:
---
🔔 Recordatorio

Tu reserva es {{tomorrow_time}}
Código: {{confirmation_code}}

¿Confirmas? Escribe "confirmado" o "cancelar"
---

Variables:
- tomorrow_time: Mañana a las {{time}}
- confirmation_code: Código

Trigger: Automático, 24h antes de la reserva
```

**Estado:** ⏳ PENDING (bajo revisión Meta)
**Uso:** Bot programado envía cada día a las 18:00

### 3. Seguimiento Post-Visita

**Nombre:** `visit_followup`

```
Texto:
---
¿Te gustó tu experiencia? 😊

Cuéntanos tu opinión o deja una reseña

⭐⭐⭐⭐⭐ Excelente
⭐⭐⭐⭐ Muy bueno
⭐⭐⭐ Promedio
---

Estado: ✅ APPROVED
Trigger: 2 horas después de hora de reserva

### 4. Promoción Especial

**Nombre:** `promotion_seasonal`

```
Texto:
---
🎉 ¡Oferta Especial!

Almuerzo ejecutivo: 50% desc. (de 15:00 a 17:00)
Válido: {{start_date}} - {{end_date}}

¿Reservas? Escribe "reservar"
---

Estado: ✅ APPROVED
Uso: Mensajes broadcast limitado a clientes con reservas previas
```

## Flujo Operativo

### Crear Nueva Plantilla

**Prerrequisito:** Template HTML/texto listos, variables definidas

**Pasos:**

1. **Ir a Meta Business Suite**
   ```
   https://business.facebook.com/ 
   → Select Account
   → WhatsApp Business → Message Templates
   ```

2. **Click "Create Template"**
   ```
   Template Name: reservation_reminder_24h (snake_case, en)
   Category: TRANSACTIONAL (reservas, confirmaciones)
   Language: Spanish (es)
   ```

3. **Agregar mensaje**
   ```
   Subject: Recordatorio de Reserva
   Content:
   🔔 Recordatorio
   
   Tu reserva es {{1}} a las {{2}}
   Código: {{3}}
   
   ¿Confirmas?
   ```

4. **Agregar botones (opcional)**
   - Quick Reply: "Confirmar", "Cancelar"
   - Call-to-action: URL a panel

5. **Validar Preview**
   - Sistema muestra ejemplo con variables reemplazadas
   - Verificar: longitud, caracteres especiales, URLs

6. **Enviar a revisión**
   - Click "Submit for Review"
   - Meta revisa en < 2h normalmente

7. **Monitorear estado**
   - ⏳ PENDING: bajo revisión
   - ✅ APPROVED: lista para usar
   - ❌ REJECTED: motivo especificado, re-enviar

### Enviar Mensaje Template

**Desde Backend (automático):**

```python
# wa_orchestrator/messages.py
from wa_orchestrator.whatsapp_api import send_template_message

def send_confirmation(phone: str, reserva: dict):
    template_name = "reservation_confirmed"
    variables = {
        "name": reserva["client_name"],
        "date": reserva["fecha"].strftime("%d/%m/%Y"),
        "time": reserva["hora"],
        "party_size": reserva["party_size"],
        "location": reserva["zona"],
        "confirmation_code": reserva["id"]
    }
    
    send_template_message(
        phone=phone,
        template_name=template_name,
        variables=variables
    )
```

**Desde Panel (manual):**

```
Panel Admin → Mensajes → Enviar Template
├─ Template: Seleccionar desde dropdown
├─ Destinatarios: 
│  - [ ] Todos
│  - [ ] Cliente específico (buscar)
│  - [ ] Rango de fechas
├─ Variables: Auto-completadas de BD
├─ Preview
└─ Enviar
```

## Administración de Plantillas

### Listar Plantillas Activas

```bash
# Desde CLI (Meta API)
curl -X GET "https://graph.instagram.com/v18.0/{WHATSAPP_BUSINESS_ACCOUNT_ID}/message_templates" \
  -H "Authorization: Bearer {ACCESS_TOKEN}"

# Output:
{
  "data": [
    {
      "name": "reservation_confirmed",
      "status": "APPROVED",
      "category": "TRANSACTIONAL",
      "created_timestamp": 1705336800
    },
    {
      "name": "reservation_reminder_24h",
      "status": "PENDING",
      "category": "TRANSACTIONAL"
    }
  ]
}
```

### Actualizar Plantilla Existente

```
1. No se pueden editar plantillas APPROVED directamente
2. Opción A: Crear versión nueva (ej. v2)
   - Nombre: reservation_confirmed_v2
   - Cambios menores
   - Enviar a revisión

3. Opción B: Eliminar + Recrear
   - Usar solo si cambios críticos
   - Documentar en changelog
```

### Archivar Plantilla No Usada

```bash
# Meta API (no hay soft-delete)
# Solo borrar si no hay referencias en BD

curl -X POST "https://graph.instagram.com/v18.0/{TEMPLATE_ID}" \
  -d "method=DELETE" \
  -H "Authorization: Bearer {ACCESS_TOKEN}"

# Antes de borrar:
# - Verificar no hay referencias en DB (SELECT * FROM messages WHERE template_name = ...)
# - Documentar decisión
# - Guardar template content en docs/templates/archived/
```

## 24h Compliance

### Checklist

- [ ] Todos los mensajes enviados fuera de ventana 24h usan templates
- [ ] Templates tienen estado "APPROVED"
- [ ] Variables coinciden con campos en BD
- [ ] No hay typos en nombres de variables
- [ ] Botones QR funcionan en preview
- [ ] URLs válidas (https)

### Monitoreo

```bash
# Dashboard - Métricas de mensajes

# 1. Mensajes enviados
SELECT 
  template_name,
  COUNT(*) as count,
  COUNT(*) / (SELECT COUNT(*) FROM messages WHERE direction = 'outbound') * 100 as pct
FROM messages
WHERE direction = 'outbound'
GROUP BY template_name
ORDER BY count DESC;

# 2. Tasa de error
SELECT 
  template_name,
  COUNT(CASE WHEN status = 'failed' THEN 1 END) as failed_count,
  COUNT(*) as total,
  COUNT(CASE WHEN status = 'failed' THEN 1 END) / COUNT(*) * 100 as error_pct
FROM messages
WHERE template_name IS NOT NULL
GROUP BY template_name;

# 3. Latencia de entrega
SELECT 
  template_name,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY delivery_latency_ms) as p95_latency_ms
FROM messages
WHERE direction = 'outbound' AND status = 'delivered'
GROUP BY template_name;
```

## Troubleshooting

| Problema | Causa | Solución |
|----------|-------|----------|
| "Template no existe" error | Nombre incorrecto o no APPROVED | Verificar nombre exacto, esperar revisión |
| Variables no reemplazadas | Mismatch en nombres | Verificar {{variable}} matches BD |
| "User rate limit" | Envíos excesivos al mismo cliente | Espaciar mensajes (min 1h entre templates) |
| Mensaje rechazado por filtro | Contenido no cumple políticas Meta | Revisar guidelines, editar mensaje |

## Límites & Guardrails

```
- Max 1000 templates por cuenta
- Max 100 caracteres en nombre
- Max 4096 caracteres en content
- Max 10 variables por template
- Max 2 buttons (quick reply o call-to-action)
- Rate limit: 80 messages/segundo por número
- Template debe tener >= 1000 caracteres (Meta policy)
```

## Changelog de Plantillas

Mantener en `docs/templates/CHANGELOG.md`:

```markdown
## Template Versions

### reservation_confirmed (v1)
- Created: 2024-01-01
- Status: APPROVED
- Variables: name, date, time, party_size, location, confirmation_code
- Content: "¡Hola {{name}}! Tu reserva ha sido confirmada..."

### reservation_reminder_24h (v1)
- Created: 2024-01-10
- Status: PENDING
- Variables: tomorrow_time, confirmation_code
- Content: "🔔 Recordatorio - Tu reserva es {{tomorrow_time}}..."
- Revision Date: 2024-01-12
```

## Recursos

- Meta WhatsApp Business API: https://developers.facebook.com/docs/whatsapp/cloud-api/
- Template Guidelines: https://www.whatsapp.com/business/api-guidelines/
- Compliance Documentation: Paso 2 - Integración WhatsApp

**Última actualización:** 2024-01-15
**Próxima revisión:** 2024-02-15
