# 12.8 Governance de Costos

## Objetivo
Prevenir sorpresas de facturación en Google Cloud mediante tagging, alertas, autoscaling inteligente, y presupuestos.

## Presupuesto Estimado

| Servicio | Uso | Costo Mensual | Detalle |
|----------|-----|---------------|---------|
| **Cloud Run** | 1M msgs/mes @ 50 RPS | $12 | vCPU-s + memory |
| **Cloud SQL** | 10GB DB + backups | $25 | Instance + storage |
| **Cloud Storage** | Backups + logs | $5 | Standard storage |
| **Cloud Logging** | ~1GB/día | $8 | Ingestion |
| **Networking** | Egress | $3 | Outbound traffic |
| **Secret Manager** | <10 secrets | $1 | API calls |
| **Cloud Build** | CI/CD | $0 | Free tier |
| **Monitoring** | Dashboards | $0 | Standard |
| **TOTAL ESTIMADO** | | **~$54/mes** | Producción |

## Resource Tagging

### Estrategia de Tags

Todos los recursos en GCP deben tener tags para cost allocation:

```yaml
# Standard tags en todos los recursos
labels:
  env: production           # production | staging | dev
  app: wa-bot              # nombre de aplicación
  owner: team-reservas     # equipo responsable
  cost-center: CC-2024-001 # para facturación
  component: backend       # backend | database | monitoring
```

### Aplicar Tags en Cloud Run

```bash
# Crear servicio con labels
gcloud run deploy wa-backend \
  --region=us-central1 \
  --labels="env=production,app=wa-bot,owner=team-reservas,cost-center=CC-2024-001"

# Actualizar labels existentes
gcloud run services update wa-backend \
  --region=us-central1 \
  --update-labels="env=production,app=wa-bot"

# Verificar
gcloud run services describe wa-backend \
  --region=us-central1 \
  --format='value(labels)'
```

### Aplicar Tags en Cloud SQL

```bash
# Crear instancia con labels
gcloud sql instances create wa-db \
  --labels="env=production,app=wa-bot,component=database"

# Actualizar labels existentes
gcloud sql instances patch wa-db \
  --labels="env=production,app=wa-bot"
```

### Aplicar Tags en Cloud Storage

```bash
# Buckets
gcloud storage buckets update gs://wa-backups \
  --labels="env=production,app=wa-bot,owner=team-reservas"
```

## Alertas de Costos

### Budget Alert en Google Cloud

```
GCP Console → Billing → Budgets

1. Click "Create Budget"
2. Configurar:
   - Budget name: "WA Bot Production - $100"
   - Billing account: Select correct
   - Scope: Projects → Select wa-project
   - Budget amount: $100/mes
   
3. Alerting rules:
   ├─ 50% of budget ($50) → Email warning
   ├─ 90% of budget ($90) → Email + Slack
   └─ 100% of budget ($100) → Email + Slack + Block

4. Save
```

### Alert sobre Cloud SQL Storage

```bash
# Si Cloud SQL alcanza 80% storage

gcloud monitoring policies create \
  --display-name="Cloud SQL Storage High" \
  --condition-display-name="Storage > 80%" \
  --condition-threshold-value=0.8 \
  --condition-threshold-filter='metric.type="cloudsql.googleapis.com/database/disk/utilization" AND resource.labels.database_id="wa-project:wa-db"' \
  --notification-channel=[SLACK_CHANNEL_ID]
```

### Alert sobre Cloud Run Invocations

```bash
# Si invocations exceden 10M/mes (estimado $50)

gcloud monitoring policies create \
  --display-name="Cloud Run Invocations High" \
  --condition-display-name="Invocations > 10M/month" \
  --condition-threshold-value=10000000 \
  --condition-threshold-filter='metric.type="run.googleapis.com/request_count" AND resource.labels.service_name="wa-backend"' \
  --notification-channel=[SLACK_CHANNEL_ID]
```

### Alert sobre Egress Network

```bash
# Si egress > baseline + 50% (ej. DDoS)

gcloud monitoring policies create \
  --display-name="Network Egress Spike" \
  --condition-display-name="Egress > 100GB" \
  --condition-threshold-value=107374182400 \
  --condition-threshold-filter='metric.type="compute.googleapis.com/vpc/egress_bytes_count"' \
  --notification-channel=[SLACK_CHANNEL_ID]
```

## Autoscaling Guardrails

### Cloud Run Max Instances

Prevenir runaway costs:

```bash
# Establecer límite máximo (3-5 para este proyecto)
gcloud run services update wa-backend \
  --max-instances=5 \
  --region=us-central1

# Justificación:
# - 1 instancia = ~50 RPS (suficiente)
# - 5 instancias = ~250 RPS (10x capacidad)
# - Con límite: costo máximo mensual predecible (~$60)
```

### Cloud SQL Memory & Storage

```bash
# Limitar tamaño máximo de instancia
# (Evita auto-upgrade a máquina más cara)

gcloud sql instances patch wa-db \
  --tier=db-g1-small  # 3.75 GB RAM
  
# ❌ NO: No auto-upgraar a tier superior sin aprobación

# Guardrail: Si storage > 10GB:
# - Alert a team (actualización necesaria)
# - Manual approval requerida
```

### Conexiones Simultáneas

```bash
# Cloud SQL max_connections = 1000

# Monitorear actual connections:
# Dashboard → Cloud SQL → Connections

# Si connections > 800:
# - Alert a team
# - Investigar leaked connections
# - Review connection pool settings
```

## Cost Analysis & Dashboard

### Comando de Billing Query

```bash
# Exportar costos últimos 30 días
# (Requiere BigQuery dataset con billing export)

bq query --use_legacy_sql=false '
  SELECT
    service.description as service,
    ROUND(SUM(cost), 2) as total_cost,
    ROUND(SUM(usage.amount), 2) as usage
  FROM `PROJECT_ID.billing_dataset.gcp_billing_export_v1_XXXXXXX`
  WHERE
    DATE(usage_start_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 30 DAY)
    AND resource.labels.service_name = "wa-backend"
  GROUP BY service
  ORDER BY total_cost DESC;
'

# Output:
# service                        total_cost   usage
# Cloud Run                      12.45        2500000.00 (invocations)
# Cloud SQL                      28.30        10.00 (GB)
# Cloud Logging                  8.50         1000.00 (MB)
# ...
```

### Dashboard Grafana (Opcional)

Conectar BigQuery para visualizar costos en tiempo real:

```
1. Instalar datasource BigQuery en Grafana
2. Query:
   SELECT DATE(usage_start_time) as date, SUM(cost) as cost
   FROM `PROJECT_ID.billing_export`
   WHERE DATE(usage_start_time) >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
   GROUP BY date
   ORDER BY date DESC

3. Visualizar: Gráfico de línea con trend
```

## Optimización de Costos

### Cloud Run: CPU Allocation

```bash
# Opción 1: CPU on request only (ahorrar ~ 10%)
gcloud run services update wa-backend \
  --cpu-throttling \
  --region=us-central1

# Opción 2: Usar 2 CPU en pico, 0.5 en standby
# (Requiere configuración manual en Revision)

# Tradeoff:
# - CPU on request: latency +50-100ms en cold start
# - Full CPU: latency consistente, costo +10%
```

### Cloud SQL: Shared-core Machine Types

```bash
# Para dev/staging, usar db-f1-micro (cheaper)
gcloud sql instances create wa-db-staging \
  --tier=db-f1-micro  # $7/mes (vs $25 para db-g1-small)

# Downside:
# - Shared CPU (variable latency)
# - <1GB RAM
# - Solo para desarrollo
```

### Storage: Lifecycle Policy

```bash
# Limpiar backups antiguos automáticamente

gsutil lifecycle set - gs://wa-backups <<EOF
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {"age": 90}  # Borrar backups > 90 días
      }
    ]
  }
}
EOF

# Ahorrar: ~$2/mes (menos storage)
```

### Logging: Reduce Ingestion

```yaml
# En Cloud Logging, excluir logs innecesarios:

exclusions:
  - name: "exclude-health-checks"
    description: "Exclude /healthz requests"
    filter: 'resource.type="cloud_run_revision" AND http_request.request_url=~".*healthz.*"'
    disabled: false
  
  - name: "exclude-metrics"
    description: "Exclude /metrics requests"
    filter: 'resource.type="cloud_run_revision" AND http_request.request_url=~".*metrics.*"'
    disabled: false
```

## Checklist de Governance

**Inicialización (una vez):**
- [ ] Tagging strategy definida (env, app, owner, cost-center)
- [ ] Todos los recursos tagueados
- [ ] Budget alert configurado ($100 monthly)
- [ ] Notification channels creados (Slack, email)
- [ ] Cost alerts configurados (storage, invocations, egress)
- [ ] Max instances set en Cloud Run (5)
- [ ] Max storage policy set en Cloud SQL
- [ ] Billing export a BigQuery habilitado

**Mensual (cada mes):**
- [ ] Revisar factura (gcp.com/billing)
- [ ] Comparar con presupuesto ($54 target)
- [ ] Investigar desviaciones > 10%
- [ ] Revisar tagging consistency
- [ ] Archive old backups (> 90 días)
- [ ] Documentar en cost log

**Trimestral (cada 3 meses):**
- [ ] Análisis de tendencias (aumenta o disminuye?)
- [ ] Optimización oportunidades (ej. reducir vCPU)
- [ ] Capacity planning (necesitaremos > 5 instancias?)
- [ ] Presupuesto de siguiente trimestre

## Ejemplo: Detección de Anomalía

### Escenario: Factura sube de $54 a $120

**1. Investigar:**
```bash
# Qué cambió?
bq query --use_legacy_sql=false '
  SELECT
    DATE(usage_start_time) as date,
    ROUND(SUM(cost), 2) as daily_cost
  FROM `PROJECT_ID.billing_export`
  WHERE DATE(usage_start_time) BETWEEN "2024-01-01" AND "2024-01-15"
  GROUP BY date
  ORDER BY date DESC;
'

# Output:
# date       daily_cost
# 2024-01-15 4.20  (anormal, de 1.80)
# 2024-01-14 4.15  (anormal)
# 2024-01-13 1.75  (normal)

# Comenzó el 14: investigar qué se deployed
```

**2. Causa probable:**
```bash
# Ver qué fue deployed:
git log --oneline --all | head -20 | grep 2024-01-14

# ¿Hay código que hace más llamadas API?
git diff HEAD~5 wa_orchestrator/ | grep -E 'requests|API|loop'

# ¿Nueva feature que consume más?
git show COMMIT_HASH | head -100
```

**3. Posibles culprits:**
- Loop infinito (API call en each iteration)
- Falta de caching (mismo query 1000 veces)
- Cloud SQL queries ineficientes (full scans)
- Más invocations (pero no visible sin access control)

**4. Solución:**
- Rollback deployment si reciente
- Optimizar queries (agregar índices)
- Agregar caching (Redis/Memorystore)
- Reducir API calls

## Cálculo Manual de Costos

```
Mes typical:
- 1M mensajes procesados (invocations)
- 100KB promedio por invocation
- vCPU request: 0.5s average

Cloud Run:
- vCPU-seconds: 1M invocations × 0.5s = 500k vCPU-s
- Costo: 500k × $0.00002083 = $10.42
- Memory: 1M × 512MB × 0.5s = 256k GB-seconds
- Costo: 256k × $0.00000417 = $1.07
- Total: ~$11.50

Cloud SQL:
- Instance fee (db-g1-small): $15.20
- Storage (5GB @ $0.17/GB): $0.85
- Backups (automatic, included): $0
- Total: ~$16

Otros:
- Logging + Monitoring: $8
- Storage + Networking: $8
- TOTAL: ~$54
```

## Recursos

- GCP Billing Documentation: https://cloud.google.com/billing/docs
- Cost Management: https://cloud.google.com/architecture/best-practices-for-running-cost-effective-kubernetes-applications-on-gke
- Budget Alerts: https://cloud.google.com/billing/docs/how-to/budgets

## Contactos

| Rol | Nombre | Responsabilidad |
|-----|--------|-----------------|
| Finance | Finanzas Team | Aprobar presupuesto |
| DevOps | Carlos López | Implementar alertas |
| Engineering Lead | Juan Pérez | Investigar anomalías |

**Última actualización:** 2024-01-15
**Próxima revisión:** 2024-02-15
**Budget Status:** ON TRACK ($54/mes target)
