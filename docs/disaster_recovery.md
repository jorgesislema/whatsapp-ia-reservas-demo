# 12.6 Plan de Disaster Recovery (DR)

## Objetivos RTO/RPO

| Métrica | Objetivo | Estrategia |
|---------|----------|-----------|
| **RPO** (Recovery Point Objective) | 5-15 min | Cloud SQL automated backups |
| **RTO** (Recovery Time Objective) | < 30 min | Cloud Run auto-restart + DB restore |
| **Availability Target** | 99.5% uptime | Redundancia, health checks, auto-scaling |

### Definiciones
- **RPO 5-15 min:** Máximo 15 minutos de datos perdidos en caso de desastre
- **RTO < 30 min:** Sistema operativo en < 30 minutos desde declaración de desastre

## Escenarios de Desastre

### 1. Backend está down (no responde)

**Síntomas:**
- `/healthz` devuelve timeout
- Error rate 100%
- Métricas no se actualizan

**Causas posibles:**
- Código bug en deployment
- Out of memory / CPU exhaustion
- Network connectivity lost
- Dependency service down (Cloud SQL)

**Procedimiento (< 5 min):**

```bash
# 1. Diagnosticar
gcloud run services describe wa-backend --region=us-central1

# 2. Check logs
gcloud run services logs read wa-backend --region=us-central1 --limit=50

# 3. Check Cloud SQL
gcloud sql instances describe wa-db

# Si Cloud SQL down:
# → Activar replica regional (si existe)
# → Si no: Restaurar backup

# 4. Si backend code bug → Rollback
gcloud run services update-traffic wa-backend \
  --to-revisions "wa-backend-previous=100" \
  --region=us-central1

# 5. Verificar
curl https://wa-backend-xxxxx.a.run.app/healthz
```

### 2. Database está corrupta (rows perdidas, inconsistencias)

**Síntomas:**
- Queries retornan NULL inesperadamente
- Foreign key violations
- Data integrity checks fallan

**Causas posibles:**
- Migration script con bug
- Deployment destructivo sin rollback
- Corrupción física (muy raro en Cloud SQL)

**Procedimiento (< 20 min):**

```bash
# 1. Declarar desastre
echo "[$(date)] DATABASE CORRUPTION DETECTED" >> INCIDENT_LOG.txt

# 2. Activar manual mode en WhatsApp
#    (Pasos 8 - dejar de responder automáticamente)
gcloud run services update wa-backend \
  --set-env-vars="MANUAL_MODE=true" \
  --region=us-central1

# 3. Listar backups
gcloud sql backups list --instance=wa-db

# 4. Escoger backup punto-en-tiempo (PITR) seguro
BACKUP_TIME="2024-01-15 10:00:00"  # Última versión buena
BACKUP_ID=$(gcloud sql backups list --instance=wa-db \
  --filter="windowStartTime<'$BACKUP_TIME'" \
  --format="value(name)" | head -1)

# 5. Restaurar a nueva instancia
gcloud sql backups restore $BACKUP_ID \
  --backup-instance=wa-db \
  --backup-config=legacy

# Esperar ~10 min...

# 6. Validar datos nuevos
gcloud sql connect wa-db-restored --user=root
> SELECT COUNT(*) FROM reservas;  -- Verificar datos
> SELECT * FROM reservas ORDER BY created_at DESC LIMIT 1;  -- Última reserva

# 7. Actualizar DATABASE_URL
OLD_DB_URL=$(gcloud run services describe wa-backend --region=us-central1 \
  --format='value(spec.template.spec.containers[0].env[?name==DATABASE_URL].value)')

NEW_DB_URL="postgresql://user:pass@wa-db-restored:5432/wa_reservas"

# Guardar en Secret Manager
echo -n "$NEW_DB_URL" | gcloud secrets versions add database-url-restored --data-file=-

# 8. Actualizar Cloud Run
gcloud run services update wa-backend \
  --set-secrets="DATABASE_URL=database-url-restored:latest" \
  --region=us-central1

# 9. Desactivar manual mode
gcloud run services update wa-backend \
  --set-env-vars="MANUAL_MODE=false" \
  --region=us-central1

# 10. Verificar
curl https://wa-backend-xxxxx.a.run.app/healthz
curl https://wa-backend-xxxxx.a.run.app/metrics
```

### 3. Region outage (Google Cloud region down)

**Síntomas:**
- Todos los servicios en región caen simultáneamente
- Google Cloud status page reporta outage

**Causas:**
- Datacenters en región afectados
- Network/infrastructure failures

**Procedimiento (30-60 min, recovery):**

```bash
# 1. Verificar Google Cloud status
# https://status.cloud.google.com/

# 2. Si outage confirmado, activar DR failover
#    (Solo si RTO > 30 min y región no recupera)

# 3. Preparar deploynment en región alternativa (us-east1)
export BACKUP_REGION="us-east1"

# 4. Restaurar DB en nueva región
gcloud sql backups list --instance=wa-db
gcloud sql backups restore $LATEST_BACKUP \
  --backup-instance=wa-db \
  --backup-location=us-east1 \
  --backup-config=legacy

# 5. Deploy backend en nueva región
docker build -t us-east1-docker.pkg.dev/$PROJECT_ID/wa-app/wa-backend:latest .
docker push us-east1-docker.pkg.dev/$PROJECT_ID/wa-app/wa-backend:latest

gcloud run deploy wa-backend-failover \
  --image=us-east1-docker.pkg.dev/$PROJECT_ID/wa-app/wa-backend:latest \
  --region=us-east1 \
  --cpu=1 \
  --memory=512Mi

# 6. Actualizar DNS/Load Balancer apuntar a us-east1
# (Configurable en Cloud Load Balancing)

# 7. Verificar disponibilidad
curl https://wa-backend-failover-xxxxx.a.run.app/healthz

# 8. Notificar team + usuarios
```

**Nota:** Este escenario es raro (<0.1% probabilidad anual). Prioridad: región recover a normales dentro de <1h generalmente.

## Backup Strategy

### Backups Cloud SQL (Automático)

```bash
# Configurado en Paso 11
# - Frecuencia: Cada 24 horas
# - Retención: 30 días
# - Ubicación: Multi-región (automático)

# Verificar
gcloud sql backups list --instance=wa-db

# Output:
# NAME                                         STATUS      WINDOW_START_TIME
# bkp_on_demand_20240115_120000               SUCCESSFUL  2024-01-15 12:00:00
# bkp_on_demand_20240114_120000               SUCCESSFUL  2024-01-14 12:00:00
# ...

# Descargar backup para auditoría (si necesario)
gcloud sql backups describe bkp_on_demand_20240115_120000 \
  --instance=wa-db
```

### Point-In-Time Recovery (PITR)

```bash
# Restaurar a momento específico (últimas 35 días)
RESTORE_TIME="2024-01-15 10:30:00"  # UTC

gcloud sql backups restore \
  --backup-instance=wa-db \
  --backup-config=legacy \
  --clone-target=wa-db-pitr-$(date +%s)

# Validar restauración
gcloud sql connect wa-db-pitr-1234567890 --user=root
> SELECT MAX(created_at) FROM reservas;
```

### Backup de Secrets

Secrets se guardan en Google Secret Manager (replicación automática):
- WA_APP_SECRET
- WA_TOKEN
- WA_VERIFY_TOKEN
- DATABASE_URL
- ADMIN_TOKEN

**Verificar:**
```bash
gcloud secrets list
gcloud secrets versions list WA_APP_SECRET
```

**Restauración:** Automática si secret manager accessible.

## Test Plan de DR

### Test Mensual: Database Recovery

```bash
# Primer viernes de cada mes
# Responsable: DBA / SRE

# 1. Seleccionar backup aleatorio (< 7 días viejo)
gcloud sql backups list --instance=wa-db --limit=5

# 2. Restaurar a clone nuevo
CLONE_ID="wa-db-dr-test-$(date +%m%d)"
gcloud sql backups restore bkp_on_demand_XXXXX \
  --backup-instance=wa-db \
  --clone-target=$CLONE_ID

# 3. Conectar + validar
gcloud sql connect $CLONE_ID --user=root

# Queries de validación:
SELECT COUNT(*) as total_reservas FROM reservas;
SELECT COUNT(*) as total_usuarios FROM usuarios;
SELECT COUNT(*) as total_audits FROM audit_log;

# Verificar integridad
SELECT * FROM reservas WHERE created_at > NOW() - INTERVAL '24 hours' LIMIT 1;

# 4. Registrar resultado
echo "✅ DR Test PASS - Backup restaurado exitosamente - $(date)" >> DR_TEST_LOG.txt

# 5. Limpiar
gcloud sql instances delete $CLONE_ID --quiet
```

### Test Trimestral: Full Failover Simulation

```bash
# Cada trimestre: simular failover completo en staging

# 1. Snapshots estables en prod
gcloud sql backups create backup-before-failover-test \
  --instance=wa-db

# 2. Restaurar backup a staging region
gcloud sql backups restore backup-before-failover-test \
  --backup-instance=wa-db \
  --clone-target=wa-db-staging-clone

# 3. Deploy backend a staging contra clone
# 4. Ejecutar UAT checklist completo
# 5. Medir RTO actual (tiempo desde backup a sistema up)
# 6. Documentar resultados
```

## Incident Response Playbook

### Fase 1: Detección (0-5 min)

```
Alertas automáticas (Paso 10 - monitoring):
- /healthz timeout
- Error rate > 5%
- Response latency P95 > 2s
- Cloud SQL CPU > 90%

→ PagerDuty / Slack notification

On-call engineer:
1. Ack alert
2. Check dashboard: https://console.cloud.google.com/monitoring
3. Determinar severidad: SEV1 (down), SEV2 (degraded), SEV3 (slowness)
```

### Fase 2: Mitigación (5-15 min)

**Si backend down:**
```
1. Check /healthz
2. Check últimos logs
3. Si código bug → Rollback
4. Si DB down → Verify Cloud SQL
5. Si network issue → Check VPC/firewall
```

**Si database issue:**
```
1. Check Cloud SQL metrics (CPU, connections, query latency)
2. Run diagnostic query
3. Si corrupción → PITR restore
```

### Fase 3: Resolution (15-30 min)

```
1. Sistema operativo 100%
2. /healthz + /metrics respondiendo
3. Error rate < 1%, latency normal
4. Manual mode OFF (si fue activado)
```

### Fase 4: Postmortem (24-48 h después)

Documentar en `docs/runbooks/incidentes.md`:

```markdown
## Postmortem: [Título del Incidente]
- Fecha: 2024-01-15
- Severidad: SEV1
- Duración: 12 minutos
- Impact: N% de mensajes no procesados

### Causa Raíz
[Descripción detallada]

### Timeline
- 10:00 - Alert triggered (error_rate spike)
- 10:02 - On-call checked logs
- 10:03 - Rollback ejecutado
- 10:12 - Sistema normal

### Qué salió bien
- Alert fue disparado a tiempo
- Rollback ejecutado rápido

### Qué salió mal
- No se detectó en pre-production
- Log message no fue claro

### Acciones Correctivas
1. Agregar test case en pytest
2. Mejorar log messages
3. Ejecutar test de rollback

### Due Date
- ☐ Action 1 - Due: 2024-01-20
- ☐ Action 2 - Due: 2024-01-20
```

## Checklist de Preparación DR

- [ ] Cloud SQL automated backups habilitados + verificados
- [ ] PITR window >= 7 días
- [ ] Secrets guardados en Secret Manager
- [ ] Cloud Run revisions aún disponibles (últimas 5)
- [ ] Runbook incidentes actualizado
- [ ] Team entrenado en procedimiento
- [ ] Test DR mensual en calendario
- [ ] Failover región alternativa documentada
- [ ] RTO/RPO métricas monitoreadas
- [ ] Postmortem template disponible

## Recursos

- Cloud SQL Backups: https://cloud.google.com/sql/docs/mysql/backup-recovery/backing-up-instances
- PITR: https://cloud.google.com/sql/docs/mysql/backup-recovery/pitr
- Cloud Run Health Checks: https://cloud.google.com/run/docs/quickstarts/build-and-deploy
- Disaster Recovery Plan Template: https://cloud.google.com/architecture/designing-disaster-recovery-for-google-cloud

## Resumen

- **RPO:** 5-15 min (Cloud SQL backups automáticos)
- **RTO:** < 30 min (cloud run restart + DB restore)
- **Backup:** Diario, retenido 30 días, multi-región
- **Test:** Mensual recovery test, trimestral failover simulation
- **Incident response:** Playbook documentado, team entrenado
- **Postmortem:** Template + documentación de acciones correctivas

**Resultado:** Capacidad de recuperarse de desastres en < 30 min con RPO de 15 min máximo.
