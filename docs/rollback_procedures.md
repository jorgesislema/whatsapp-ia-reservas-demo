# 12.5 Plan de Rollback & Blue/Green

## Estrategia: Blue/Green con Cloud Run

Cada deployment crea una **nueva revisión** en Cloud Run. El tráfico se controla independientemente:
- **Blue (anterior):** Revisión en producción (100% tráfico)
- **Green (nueva):** Revisión recién desplegada (0% tráfico inicialmente)

### Flujo de Deployment

```
1. Deploy Green
   └─ Nueva revisión sin tráfico (0%)
   
2. Smoke Tests en Green
   └─ Verificar /healthz, /metrics
   └─ Si falla → ROLLBACK inmediato
   
3. Tráfico gradual (canary)
   └─ Green: 10% → 50% → 100%
   └─ Blue: 90% → 50% → 0%
   
4. Validación
   └─ Métricas estables
   └─ Error rate < 1%
   └─ Latency P95 < 800ms
```

## Rollback Inmediato (< 5 min)

### Opción 1: Cloud Console UI (Más rápido)

```
1. Ir a Cloud Run → wa-backend → Revisions tab
2. Encontrar revisión anterior (estado "No longer receiving traffic")
3. Click "Set as serving" → traslada 100% tráfico
4. Verificar /healthz
```

**Tiempo:** ~2 minutos

### Opción 2: CLI (Programático)

```bash
# Obtener revisiones activas
gcloud run services describe wa-backend \
  --region=us-central1 \
  --format='table(status.traffic[].revisionName, status.traffic[].percent)'

# Rollback a revisión anterior
PREV_REVISION="wa-backend-xxxxx"  # de salida anterior
gcloud run services update-traffic wa-backend \
  --to-revisions "$PREV_REVISION=100" \
  --region=us-central1

# Verificar
curl https://wa-backend-xxxxx.a.run.app/healthz
```

**Tiempo:** ~1 minuto

### Opción 3: GitHub Actions Manual Rollback

```yaml
# En Actions: Run workflow → Deploy Backend (Manual)
# Environment: production
# Revision traffic %: 0  (mantiene Green sin tráfico)

# Luego, desde Cloud Console, traslada tráfico a Blue anterior
```

## Incidentes: Cuándo Rollback

| Condición | Acción | Timeout |
|-----------|--------|---------|
| `/healthz` falla | Rollback inmediato | <1 min |
| Error rate > 5% | Rollback inmediato | <2 min |
| Latency P95 > 2s | Rollback inmediato | <3 min |
| Error rate > 1% pero < 5% | Observar 5 min, luego rollback | <8 min |
| Error rate < 1%, P95 < 800ms | Proceder a 100% tráfico | N/A |

## Base de Datos: Mitigación Pre-Rollback

### Migraciones Aditivas (Seguras)

```sql
-- ✅ Seguro: agregar columna
ALTER TABLE reservas ADD COLUMN notes VARCHAR(500);

-- ✅ Seguro: nuevo índice
CREATE INDEX idx_reservas_date ON reservas(fecha);

-- ✅ Seguro: nueva tabla
CREATE TABLE audit_log (...);
```

**Rollback:** No necesita cambios DB (columns nuevas ignoradas por código viejo)

### Migraciones Destructivas (No Permitidas sin aprobación)

```sql
-- ❌ Riesgoso: renombrar/eliminar columna
-- → Código viejo falla al acceder a columna
-- → Solución: Feature flag + validación

-- ❌ Riesgoso: cambiar tipo de dato
-- → Código viejo no parsea nuevo tipo
-- → Solución: Feature flag + validación
```

### Feature Flags para Cambios Destructivos

```python
# wa_orchestrator/feature_flags.py
ENABLE_NEW_SCHEMA_VERSION = os.getenv("FEATURE_FLAG_NEW_SCHEMA") == "true"

# En handlers.py
if ENABLE_NEW_SCHEMA_VERSION:
    # Usar nueva estructura
    slots = reserva.get_slots_v2()
else:
    # Usar estructura antigua
    slots = reserva.get_slots()
```

**Despliegue:**
1. Deploy código (flag=false)
2. Validar 100% tráfico en Blue
3. `gcloud run services update wa-backend --set-env-vars FEATURE_FLAG_NEW_SCHEMA=true`
4. Monitor 5 min
5. Si OK → flag queda activado

**Rollback (si falla):**
1. `gcloud run services update wa-backend --set-env-vars FEATURE_FLAG_NEW_SCHEMA=false`
2. Tráfico sigue en Green (sin necesidad de cambio DB)

## Backups Pre-Deployment

### Backup Manual de Cloud SQL

```bash
# Antes de migración crítica (ej. cambio de schema)
BACKUP_ID="backup-$(date +%Y%m%d-%H%M%S)"

gcloud sql backups create $BACKUP_ID \
  --instance=wa-db \
  --description="Pre-deployment: [descripción del cambio]"

# Verificar
gcloud sql backups list --instance=wa-db
```

### Backup Automático (ya configurado en Paso 11)

- **Frecuencia:** Cada 24 horas
- **Retención:** 30 días
- **Ubicación:** Cloud SQL automated backups

## Restauración Post-Desastre

Si el rollback de código no es suficiente (ej. corrupción de datos):

```bash
# 1. Listar backups disponibles
gcloud sql backups list --instance=wa-db

# 2. Restaurar a nuevo clone
gcloud sql backups restore [BACKUP_ID] \
  --backup-instance=wa-db \
  --backup-config=legacy

# 3. Validar clone
gcloud sql instances describe wa-db-restore

# 4. Actualizar DATABASE_URL en Cloud Run
gcloud run services update wa-backend \
  --set-secrets="DATABASE_URL=sec-database-url-restored:latest" \
  --region=us-central1

# 5. Monitor /healthz y métricas
```

## Validación Pre-Production

### Checklist de Rollback

- [ ] Código viejo ejecutándose en Blue (último deployment)
- [ ] Revisiones anteriores aún disponibles en Cloud Run
- [ ] Secrets guardados en Secret Manager (no en código)
- [ ] Feature flags funcionando (endpoint: GET /config/flags)
- [ ] Backups Cloud SQL recientes (<24h)
- [ ] Disaster recovery runbook (docs/disaster_recovery.md) actualizado
- [ ] Equipo notificado de procedimiento rollback

### Test Rollback Mensual

```bash
# Una vez al mes:

# 1. Deploy versión "test" a staging
./scripts/deploy-staging.sh v1.2.3-test

# 2. Verificar /healthz
curl https://wa-staging-xxxxx.a.run.app/healthz

# 3. Simular rollback en staging
gcloud run services update-traffic wa-backend-staging \
  --to-revisions "wa-backend-staging-xxxxx=100" \
  --region=us-central1

# 4. Verificar funcionamiento
curl https://wa-staging-xxxxx.a.run.app/metrics

# 5. Registrar resultado
echo "✅ Rollback test passed - $(date)" >> ROLLBACK_TEST_LOG.txt
```

## Comunicación & Postmortem

### Durante Incidente

```
Slack notification (automated):
❌ [PROD] Error rate spike detected
   - Metric: error_rate
   - Threshold: > 1%
   - Current: 2.1%
   - Action: Rollback triggered

Dashboard: https://console.cloud.google.com/run
```

### Post-Rollback

1. **Comunicar:** Slack #incidents (status, ETA)
2. **Investigar:** Revisar logs (Paso 10 - Cloud Logging)
3. **Postmortem:** Template en docs/runbooks/incidentes.md
   - Qué falló
   - Por qué no se detectó
   - Cómo prevenir
   - Acción correctiva

## Autorización & Aprobaciones

| Acción | Quién | Aprobación |
|--------|-------|-----------|
| Deploy a staging | Cualquier dev | Auto (CI/CD pasa) |
| Deploy a prod (canary 10%) | Senior dev | Self-approval |
| Deploy a prod (100% tráfico) | Tech lead | 1 aprobación |
| Rollback (< 5 min) | On-call engineer | Self-approval (incidents) |
| Rollback (programado) | Tech lead | 1 aprobación |

## Resumen

- **Rollback tiempo:** < 5 minutos (solo tráfico shift)
- **Código:** Aditivo → sin cambios DB necesarios
- **DB Destructivo:** Feature flags + validación
- **Backup:** Pre-deployment para cambios críticos
- **Test:** Mensual en staging
- **Notificación:** Automática + postmortem documentado

**Resultado:** Capacidad de revertir deployments problemáticos en < 5 min sin pérdida de datos.
