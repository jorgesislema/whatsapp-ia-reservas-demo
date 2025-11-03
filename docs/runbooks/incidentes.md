# Runbook: Respuesta a Incidentes

## Resumen
Procedimiento estandarizado para detectar, responder y resolver incidentes en producción.

## Audiencia
- On-call engineer
- Incident commander
- SRE team

## Severidad y Definiciones

| Severidad | Definición | Ejemplos | RTO |
|-----------|-----------|----------|-----|
| **SEV1** | Down total, sin workaround | Backend no responde, DB inaccesible | <15 min |
| **SEV2** | Degradation, usuarios afectados | Error rate 5-10%, latency spike | <30 min |
| **SEV3** | Anomalía, funcionalidad limitada | Métrica fuera de rango, error rate <1% | <2h |
| **SEV4** | Warning, sin impacto operacional | Disk usage high, test failure | <24h |

## Fase 1: Detección (0-2 min)

### Alertas Automáticas

Se disparan en 3 canales:

1. **PagerDuty** (crítico)
   - Webhook desde Cloud Monitoring
   - Llama on-call engineer
   
2. **Slack #incidents**
   - Mensaje automático con alerta + contexto
   - Enlace a dashboard
   
3. **Email** (backup)
   - ops@wa-team.com

### Señales de Incidente

**Backend Metrics:**
```
- /healthz error rate > 5% → SEV1
- Response latency P95 > 2s → SEV2
- Error rate > 1% (pero < 5%) → SEV3
- CPU > 90% sostenido → SEV2
```

**Database Metrics:**
```
- Connections > 80% max → SEV2
- Query latency spike > 3s → SEV3
- Storage > 90% → SEV2
```

**Manual Alerting:**
```
Usuarios reportan en Slack #support:
"No puedo hacer reservas desde hace 15 min"
→ Verificar backend status
```

### Checklist de Detección

- [ ] Alerta recibida (timestamp anotado)
- [ ] Severidad inicial estimada
- [ ] Dashboard abierto: https://console.cloud.google.com/monitoring
- [ ] Confirmación: ¿realmente hay problema?

## Fase 2: Triage (2-5 min)

### Paso 1: Declarar Incidente

En Slack #incidents (automático o manual):
```
🚨 INCIDENT DECLARED

Severidad: SEV2
Descripción: Error rate spike en backend
Iniciador: @carlos.lopez
Comenzó: 2024-01-15 14:30:00 UTC
Status: Investigating
```

### Paso 2: Incident Commander

- **SEV1:** Tech lead + SRE
- **SEV2:** SRE + backend engineer
- **SEV3:** Backend engineer solo
- **SEV4:** Documentar, no requiere coordinación

Commander actualiza Slack cada 5 min.

### Paso 3: Diagnosis Rápida (5 min máximo)

```bash
# 1. Check backend status
curl https://wa-backend-xxxxx.a.run.app/healthz
# Expected: 200 OK + latency < 500ms

# 2. Check logs inmediatos (últimos 100 líneas)
gcloud run services logs read wa-backend --limit=100

# 3. Check metrics en Cloud Console
# - Error rate (graph)
# - Response time (graph)
# - CPU / Memory usage

# 4. Check Cloud SQL
gcloud sql instances describe wa-db
# Status debe ser: RUNNABLE
# Connections: < 80% max

# 5. Check recientes deployments
gcloud run services list-revisions wa-backend --region=us-central1 | head -5
# ¿Hay revisión nueva hace < 30 min?
```

## Fase 3: Mitigación Inmediata (5-15 min)

### Si Backend está Down (SEV1)

```bash
# Opción A: Rollback a revisión anterior
gcloud run services describe wa-backend --region=us-central1 \
  --format='table(status.traffic[].revisionName)'

PREV_REVISION="wa-backend-xxxxx"  # de salida anterior
gcloud run services update-traffic wa-backend \
  --to-revisions "$PREV_REVISION=100" \
  --region=us-central1

# Esperar 30 segundos
curl https://wa-backend-xxxxx.a.run.app/healthz

# Opción B: Restart service (si no hay rollback posible)
gcloud run services update wa-backend \
  --region=us-central1

# Opción C: Activar manual mode (si nada funciona)
gcloud run services update wa-backend \
  --set-env-vars="MANUAL_MODE=true" \
  --region=us-central1
# → Bot no responde más, usuarios reciben mensaje de fuera de servicio
```

### Si Database está Down (SEV1)

```bash
# Check status
gcloud sql instances describe wa-db

# Opción A: Restart instancia (detiene/inicia)
gcloud sql instances restart wa-db
# Esperar ~2-3 min

# Opción B: Failover a replica
# (Solo si ya tienes replica regional configurada en Paso 11)
gcloud sql instances failover wa-db --async

# Opción C: Restaurar desde backup (si corrupción)
# → Ver 12.6 disaster_recovery.md
```

### Si Error Rate > 5% pero Services Respondiendo (SEV2)

```bash
# 1. Investigar qué endpoint falla
gcloud run services logs read wa-backend --limit=500 | \
  grep "ERROR\|Exception" | tail -20

# 2. Posibles causas + soluciones:
# - NLU service timeout → Reintentar
# - DB timeout → Check Cloud SQL
# - Memory leak → Rollback
# - Rate limiting issue → Check traffic

# 3. Si causado por reciente deployment → Rollback
gcloud run services update-traffic wa-backend \
  --to-revisions "wa-backend-xxxxx=100" \
  --region=us-central1
```

## Fase 4: Monitoreo (durante mitigación)

Abrir dashboard en paralelo:
```
https://console.cloud.google.com/monitoring/dashboards/custom/wa-dashboard
```

Métricas clave a monitorear:

```
Error rate: Objetivo < 1%
Response time P95: Objetivo < 800ms
CPU: Objetivo < 70%
Memory: Objetivo < 60%
```

Actualizar Slack cada 5 min:
```
📊 UPDATE (14:35)
- Rollback ejecutado
- Error rate: 4.2% → 0.8% ✅
- Latency P95: 2500ms → 650ms ✅
- Status: Monitoring
```

## Fase 5: Validación (10-30 min post-incident)

### Smoke Tests

```bash
# 1. Verificar endpoints críticos
curl https://wa-backend-xxxxx.a.run.app/healthz
curl https://wa-backend-xxxxx.a.run.app/metrics
curl https://wa-backend-xxxxx.a.run.app/config

# 2. Simular webhook típico
curl -X POST https://wa-backend-xxxxx.a.run.app/webhook \
  -H "X-Hub-Signature: sha256=XXXXX" \
  -H "Content-Type: application/json" \
  -d '{
    "object": "whatsapp_business_account",
    "entry": [{
      "changes": [{
        "value": {
          "messages": [{
            "from": "5939999999",
            "id": "test-msg-1",
            "timestamp": "1705349400",
            "text": {"body": "hola"}
          }]
        }
      }]
    }]
  }'
# Expected: 200 OK

# 3. Check DB queries
gcloud sql connect wa-db --user=root
> SELECT COUNT(*) FROM reservas WHERE created_at > NOW() - INTERVAL '1 hour';
# Debe haber movimiento reciente
```

### Métricas Post-Incident

- Error rate < 1% por 10 min consecutivos
- Latency P95 < 800ms por 10 min
- CPU < 70%, Memory < 60%
- No hay alertas activas

Si TODO ✅: Pasar a Fase 6 (postmortem)

## Fase 6: Notificación & Cierre

### Declarar Resolved

```
Slack #incidents:
✅ INCIDENT RESOLVED

Severidad: SEV2
Duración: 8 minutos (14:30 - 14:38)
Causa Raíz: Deployment 2024-01-15-1430 con bug en NLU slots
Acción: Rollback a revisión anterior
Impacto: ~45 mensajes sin procesar (recuperados después)
Próximo Paso: Postmortem en 24h
```
```

### Escalación a Gerencia

- **SEV1:** Notificación inmediata a CTO
- **SEV2:** Notificación después de resolve
- **SEV3+:** Log en spreadsheet, no notificación

## Fase 7: Postmortem (24-48 h después)

### Template de Postmortem

```markdown
# Postmortem: [Título del Incidente]

## Metadata
- Fecha: 2024-01-15
- Severidad: SEV2
- Duración: 8 minutos
- Impacto: 45 mensajes

## Timeline
- **14:30:** Error rate spike detectada (alert disparada)
- **14:32:** On-call engineer notificado
- **14:33:** Investigación → encontrado deployment reciente
- **14:35:** Rollback ejecutado
- **14:36:** Error rate normalizada
- **14:38:** Incidente dado por resuelto

## Causa Raíz (RCA)
Deployment 2024-01-15-1430 introdujo bug en NLU slot extraction.
El slot "party_size" no se extraía correctamente, causando error en orchestrator.
Bug no fue detectado en testing porque test case no cubría variación "para dos personas".

## Contributing Factors
1. PR review superficial (no notó cambio en regex)
2. Testing no cubría todas las variaciones de language
3. Falta de E2E test en staging pre-deployment

## Qué Salió Bien
1. Alert disparada al toque (< 1 min)
2. On-call respondió rápido (< 2 min)
3. Rollback ejecutado exitosamente (< 5 min)
4. Comunicación clara en Slack

## Qué Salió Mal
1. Test case insuficiente (no cubría "para dos personas")
2. PR review no fue exhaustivo
3. No se ejecutó E2E en staging

## Acciones Correctivas

| Acción | Owner | Due Date | Status |
|--------|-------|----------|--------|
| Agregar test case para "para X personas" variaciones | @dev1 | 2024-01-20 | ☐ |
| Mejorar PR review checklist (coverage requerido) | @lead | 2024-01-18 | ☐ |
| Implementar E2E smoke test en staging (pre-deploy) | @qa | 2024-01-22 | ☐ |

## Prevention (Future)
- Requerimiento: Coverage > 80% antes de PR merge
- Requerimiento: E2E test en staging antes de deploy
- Mejorar alerting: detectar cambios en PR que afecten NLU

## Lessons Learned
1. Edge cases en NLU son críticos → invertir en test coverage
2. Staging debe tener data realista + test automation
3. Rollback rápido es mejor que fix rápido (cuando hagas ambos: rollback primero)
```

### Revisar & Distribuir

1. Asignar dueños de acciones correctivas
2. Compartir en Slack #postmortems
3. Mencionar en standup del equipo
4. Track completion de acciones (feedback loop)

## Escalación & Contactos

| Escenario | Acción | Contacto |
|-----------|--------|----------|
| SEV1 > 5 min | Llamar CTO | +58-0412-XXXXX |
| SEV1 > 15 min | Llamar CEO | +58-0412-YYYYY |
| DB irrecuperable | Activar DR failover | SRE team |
| Ataque activo | Contactar security | security@wa-team.com |

## Recursos

- Cloud Run logs: `gcloud run services logs read wa-backend --limit=500`
- Cloud SQL console: https://console.cloud.google.com/sql
- Monitoring dashboard: https://console.cloud.google.com/monitoring
- Postmortem template: docs/runbooks/postmortem_template.md

**Última actualización:** 2024-01-15
**Próxima revisión:** 2024-02-15 (después de SGI training)
