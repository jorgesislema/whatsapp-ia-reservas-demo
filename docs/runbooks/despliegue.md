# Runbook: Procedimiento de Despliegue

## Resumen
Guía paso-a-paso para promover código desde DEV → UAT → PROD con validaciones y rollback.

## Audiencia
- Backend engineers
- Deployment lead
- QA team

## Ambientes

| Ambiente | Descripción | Cloud Run | BD | Data |
|----------|-------------|-----------|----|----|
| **DEV** | Local + GitHub | No | Local SQLite | Mock |
| **STAGING** | Pre-production replica | wa-backend-staging | wa-db-staging (clone) | Real (anónimizado) |
| **PRODUCTION** | Live | wa-backend | wa-db | Real (activo) |

## Pre-Deployment Checklist

### 1. Verificación de Código

```bash
# Asegurar rama está actualizada
git checkout develop
git pull origin develop

# Ejecutar tests locales
pytest tests/ -v --cov=wa_orchestrator

# Si coverage < 80% → FIX y commit

# Lint check
pylint wa_orchestrator/ --exit-zero

# Security scan
bandit -r wa_orchestrator/ -f txt
```

### 2. Preparación de PR

```
PR Title: [Paso X] Brief description of change
PR Description:
- What changed
- Why
- Testing done locally (copy test output)
- Migration? (Y/N - if Y, detail migration)

Labels:
- enhancement | bugfix | hotfix
- backend | panel | infra
- ready-for-deploy (cuando listo)
```

### 3. Review + Aprobación

```
PR Checklist:
- [ ] Code reviewed (1+ approvals)
- [ ] Tests pass (CI/CD green ✅)
- [ ] Coverage > 80%
- [ ] No security warnings
- [ ] Database migration tested
- [ ] Rollback plan documented (if needed)

Approvers:
- Code: 1 senior dev
- Deployment: Tech lead
```

## Despliegue a STAGING

### Objetivo
Validar cambios en ambiente que replica PROD (pero con menos tráfico y riesgo).

### Pasos

**1. Merge a `main`**
```bash
# Después de aprobación
git checkout main
git pull origin main
git merge --no-ff develop
git push origin main

# GitHub Actions auto-disparado:
# - backend-ci.yml: Tests pass ✅
# - Panel CI pasa ✅
# → Deployment auto a staging
```

**2. Verificar Deploy en Staging**
```bash
# Esperar ~3 min por Cloud Build

# Check status
gcloud run services describe wa-backend-staging --region=us-central1 \
  --format='value(status.url)'

# Output: https://wa-backend-staging-xxxxx.a.run.app

# Test endpoint
curl https://wa-backend-staging-xxxxx.a.run.app/healthz
# Expected: 200 OK + version info

curl https://wa-backend-staging-xxxxx.a.run.app/metrics
# Expected: 200 OK + prometheus metrics
```

**3. Smoke Tests en Staging**
```bash
# Test webhook típico
curl -X POST https://wa-backend-staging-xxxxx.a.run.app/webhook \
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
            "text": {"body": "reservar para 4 el viernes a las 8"}
          }]
        }
      }]
    }]
  }'

# Check response (debe procesar)
# Expected: 200 OK, log entry en Cloud Logging
```

**4. Ejecutar UAT Checklist**
```bash
# 26 test cases en qa/UAT_checklist.md

# Crítico:
- [ ] Webhook verification (GET /events)
- [ ] Message processing (POST /webhook)
- [ ] NLU slot extraction
- [ ] RAG retrieval
- [ ] Agenda availability

# Si alguno falla: 
# 1. Anotar en PR
# 2. Revert + fix en develop
# 3. Reintentar
```

**5. Load Testing Opcional**
```bash
# Si cambios en core message handling:
cd qa/
locust -f locustfile.py --host=https://wa-backend-staging-xxxxx.a.run.app \
  -u 50 -r 10 -t 60s --headless --csv=results

# Verificar:
# - P95 latency < 800ms
# - Error rate < 1%
```

**6. Aprobación para PROD**
```
Si todos los tests PASS en staging:

Slack #deployments:
✅ STAGING VALIDATION PASSED
Branch: main
Commit: abc123def456
Changes: [brief summary]
Ready for PROD? [APPROVED / HOLD]
```

## Despliegue a PRODUCTION

### ⚠️ CRÍTICO: No hacer sin aprobación

**Requerimientos:**
- [ ] Staging tests PASSED
- [ ] 2 personas autorizan (code + tech lead)
- [ ] Off-peak window (fuera de rush)
- [ ] On-call engineer disponible

### Pasos

**1. Preparar Deployment Manual**

```bash
# Opción A: Desde GitHub Actions (Recomendado)
# 1. Ir a: https://github.com/tu-repo/actions
# 2. Seleccionar "Deploy Backend to Cloud Run (Manual)"
# 3. Click "Run workflow"
# 4. Inputs:
#    - environment: production
#    - revision_traffic_percent: 10 (canary)
# 5. Click "Run workflow"

# Opción B: Desde CLI (Manual)
gcloud run deploy wa-backend \
  --image=us-central1-docker.pkg.dev/$PROJECT_ID/wa-app/wa-backend:latest \
  --region=us-central1 \
  --no-traffic  # Deploy sin tráfico
```

**2. Verificar Nueva Revisión**
```bash
gcloud run services describe wa-backend --region=us-central1 \
  --format='table(status.traffic[].revisionName, status.traffic[].percent)'

# Output:
# REVISION_NAME                        PERCENT
# wa-backend-xxxxx (vieja)             100
# wa-backend-yyyyy (nueva)             0

# Nueva revisión en 0% tráfico = seguro testear
```

**3. Smoke Tests contra Prod (con 0% tráfico)**
```bash
# Esperar 30 seg por Cloud Run startup
# Acceder revisión nueva directamente:
NEW_REVISION="wa-backend-yyyyy"

curl https://${NEW_REVISION}-xxxxx.a.run.app/healthz
# Expected: 200 OK

curl https://${NEW_REVISION}-xxxxx.a.run.app/metrics
# Expected: 200 OK
```

**4. Canary Deploy (10% tráfico)**
```bash
# Shift 10% tráfico a nueva revisión
gcloud run services update-traffic wa-backend \
  --to-revisions "wa-backend-yyyyy=10,wa-backend-xxxxx=90" \
  --region=us-central1

# Monitorear por 5 minutos:
watch -n 2 'gcloud run services logs read wa-backend --limit=50'

# Buscar:
# ✅ Logs normales (INFO messages)
# ❌ Error spikes (ERROR count > 5/min)
# ❌ Latency spikes (> 1s)
```

**5. Decisión: Proceder o Rollback**

**Si 10% traffic GOOD (5 min sin errores):**
```bash
# Shift a 50%
gcloud run services update-traffic wa-backend \
  --to-revisions "wa-backend-yyyyy=50,wa-backend-xxxxx=50" \
  --region=us-central1

# Monitorear 5 min más
# Si OK → 100%
gcloud run services update-traffic wa-backend \
  --to-revisions "wa-backend-yyyyy=100" \
  --region=us-central1
```

**Si error rate > 1% a cualquier punto:**
```bash
# ROLLBACK INMEDIATO
gcloud run services update-traffic wa-backend \
  --to-revisions "wa-backend-xxxxx=100" \
  --region=us-central1

# Notificar en Slack #deployments
❌ DEPLOYMENT ROLLED BACK
Reason: Error rate spike to 2.3%
Reversion time: 2 min
Previous revision: wa-backend-xxxxx
Investigation: Check logs + postmortem
```

**6. Validación Final**
```bash
# Esperar 5 min post-100% traffic
curl https://wa-backend-xxxxx.a.run.app/healthz
curl https://wa-backend-xxxxx.a.run.app/metrics

# Verificar en dashboard
# https://console.cloud.google.com/monitoring

# Métricas objetivo:
# - Error rate: < 1% ✅
# - Latency P95: < 800ms ✅
# - CPU: < 70% ✅
# - Requests: in normal range ✅
```

## Post-Deployment

### Notificación

```
Slack #deployments (automático desde GitHub Actions):
✅ DEPLOYMENT SUCCESSFUL

Service: wa-backend
Environment: production
Revision: wa-backend-yyyyy
Commit: abc123def456
Author: @carlos.lopez
Traffic: 100%
Status: ✅ Healthy

Metrics (5 min post-deploy):
- Error rate: 0.3%
- Latency P95: 620ms
- Requests: 1,250 RPS (normal)

Rollback command (if needed):
gcloud run services update-traffic wa-backend --to-revisions "wa-backend-xxxxx=100" --region=us-central1
```

### Monitoring (24h post-deploy)

```bash
# Ejecutar durante 24h:
watch -n 5 'gcloud run services logs read wa-backend --limit=20'

# Buscar:
# ✅ Requests normales
# ❌ Patterns inesperados
# ❌ Error spikes

# Si problema detectado:
1. Contactar on-call
2. Abrir incidente
3. Ejecutar playbook de incidentes (docs/runbooks/incidentes.md)
```

## Rollback Manual (Si es necesario después de 24h)

```bash
# Si descubres bug post-deployment (ej. en día 2):

# 1. Identificar revisión anterior buena
gcloud run services list-revisions wa-backend --region=us-central1

# 2. Revert tráfico
gcloud run services update-traffic wa-backend \
  --to-revisions "wa-backend-xxxxx=100" \
  --region=us-central1

# 3. Monitorear
curl https://wa-backend-xxxxx.a.run.app/healthz

# 4. Notificar
# Slack #deployments: "Deployment rolled back due to [reason]"

# 5. Postmortem
# Investigar qué se perdió en testing
# Agregar test case
```

## Database Migrations

### Si el deployment incluye schema change:

```bash
# 1. Migración debe ser ADITIVA
# ✅ Agregar columna
# ✅ Crear índice
# ❌ Eliminar columna (sin feature flag)

# 2. Ejecutar migración PRE-deploy
# En Cloud SQL:
gcloud sql connect wa-db --user=root
> ALTER TABLE reservas ADD COLUMN notes VARCHAR(500);
> CREATE INDEX idx_notes ON reservas(notes);

# 3. Esperar a que replication alcance (< 1 min)

# 4. Deploy backend (código que usa nuevas columnas)

# 5. Si rollback necesario:
# - Código viejo ignora columnas nuevas → compatible
# - No necesita rollback DB
```

## Checklist de Despliegue

**Pre-Deployment:**
- [ ] Código en `main` branch
- [ ] Tests locales PASS (pytest + lint)
- [ ] CI/CD tests PASS en GitHub
- [ ] Coverage > 80%
- [ ] No security warnings
- [ ] Staging deployment PASS
- [ ] UAT checklist PASS
- [ ] 2 approvals (code + tech lead)
- [ ] On-call available

**Deployment:**
- [ ] Deploy con 0% tráfico
- [ ] Smoke tests OK
- [ ] Canary 10% → monitorear 5 min
- [ ] Canary 50% → monitorear 5 min
- [ ] Canary 100% → validar

**Post-Deployment:**
- [ ] Error rate < 1%
- [ ] Latency P95 < 800ms
- [ ] Notificación Slack enviada
- [ ] Monitoreo 24h configurado
- [ ] Documentación actualizada

## Ventana de Deployment

**Recomendado:**
- Martes-Jueves
- 10:00-14:00 UTC (fuera de rush)
- On-call engineer disponible
- Tech lead disponible para preguntas

**Evitar:**
- Lunes (post-weekend issues)
- Viernes (problema es fin de semana)
- Noches/fines de semana
- Festivos

## Contactos

| Rol | Nombre | Teléfono |
|-----|--------|----------|
| Tech Lead | Carlos López | +58-0412-XXXXX |
| Backend Lead | Juan Pérez | +58-0424-YYYYY |
| SRE On-Call | - | #incidents |

**Última actualización:** 2024-01-15
**Próxima revisión:** 2024-02-15
