# Runbook: Seguridad & Secret Management

## Resumen
Procedimiento para rotación de secrets, auditoría IAM, y cumplimiento de políticas de seguridad.

## Audiencia
- DevOps / SRE
- Security team
- Tech lead

## Gestión de Secrets

### Secrets Críticos

| Secret | Ubicación | Rotación | Owner |
|--------|-----------|----------|-------|
| WA_APP_SECRET | Secret Manager | Cada 90 días | Meta |
| WA_TOKEN | Secret Manager | Cada 90 días | Meta |
| WA_VERIFY_TOKEN | Secret Manager | Cada 90 días | Meta |
| ADMIN_TOKEN | Secret Manager | Cada 180 días | Team |
| DATABASE_URL | Secret Manager | Solo cambio de DB | SRE |
| GCP Service Account Key | Secret Manager | Cada 90 días | SRE |

### Dónde NO guardar Secrets

```
❌ .env.local (commiteado a git)
❌ Código source
❌ Comentarios en documentación
❌ Emails
❌ Slack messages
❌ Logs (sanitizados en Paso 10)

✅ Google Secret Manager (encriptado en rest + transit)
✅ GitHub Secrets (para CI/CD)
✅ 1Password (para team compartir)
```

## Secret Rotation (90 días)

### Procedimiento: Rotar WA_APP_SECRET

**Cronograma:**
```
Cada 90 días (primer lunes del trimestre):
- Q1: Enero
- Q2: Abril
- Q3: Julio
- Q4: Octubre
```

**Pasos:**

**1. Generar nuevo secret en Meta**

```
Meta Business Suite:
1. Ir a: Settings → WhatsApp Business Accounts → Account Settings
2. Sección: "WhatsApp App Configuration"
3. Click "Regenerate App Secret"
4. Aparecer nuevo token (guardar en portapapeles)
```

**2. Crear versión nueva en Secret Manager**

```bash
# Nuevo secret (valor obtenido de Meta)
NEW_SECRET="xyzabc123456"

# Guardar como nueva versión
echo -n "$NEW_SECRET" | \
  gcloud secrets versions add WA_APP_SECRET --data-file=-

# Verificar
gcloud secrets versions list WA_APP_SECRET | head -3
# Output:
# NAME     CREATED              STATE
# 3        2024-01-15 14:30     enabled  (nueva)
# 2        2024-10-15 10:00     enabled  (anterior)
# 1        2024-07-15 09:00     enabled  (vieja)
```

**3. Actualizar Cloud Run**

```bash
# Cloud Run referencia última versión automáticamente
# Solo verificar que está usando correcta:

gcloud run services describe wa-backend --region=us-central1 \
  --format='value(spec.template.spec.containers[0].env[?name==WA_APP_SECRET])'

# Si no se actualiza inmediatamente:
gcloud run services update wa-backend \
  --set-secrets="WA_APP_SECRET=WA_APP_SECRET:latest" \
  --region=us-central1
```

**4. Verificar webhook funcionando**

```bash
# Esperar 1 min por propagación

# Test webhook con nuevo secret
curl -X GET \
  'https://wa-backend-xxxxx.a.run.app/events?hub.challenge=test&hub.verify_token=YOUR_VERIFY_TOKEN' \
  -H 'X-Hub-Signature: sha256=NEW_HMAC_SIGNATURE'

# Expected: 200 OK, challenge echoed
```

**5. Deshabilitar versión vieja (opcional)**

```bash
# Después de 7 días de que nueva versión funciona:

gcloud secrets versions destroy 2 \
  --secret=WA_APP_SECRET

# Precaución: solo si SEGURO que nueva funciona
```

**6. Registrar rotación**

```
En docs/security/SECRET_ROTATION_LOG.md:

Date: 2024-01-15
Secret: WA_APP_SECRET
Old Version: 2
New Version: 3
Rotated By: @carlos.lopez
Verified: ✅ (webhook test passed)
Status: COMPLETE
```

## Auditoría IAM

### Principio de Menor Privilegio

```
Cada miembro tiene ROL mínimo necesario para su función:
- Developer: roles/run.developer (deploy a staging)
- Tech Lead: roles/owner (production access)
- SRE: roles/editor (infrastructure changes)
- Metrics: roles/monitoring.metricViewer (solo read)
```

### Verificar Permisos IAM

```bash
# Listar quién tiene acceso a qué
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten=bindings[].members \
  --format='table(bindings.role)' \
  | sort | uniq

# Output:
# ROLE
# roles/owner                              → only tech-lead@
# roles/editor                             → sre-team@
# roles/run.developer                      → dev-team@
# roles/monitoring.metricViewer            → ops-team@
```

### Agregar Permiso Nuevo

```bash
# Agregar nuevo dev a proyecto
NEW_USER="newdev@wa-team.com"
ROLE="roles/run.developer"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="user:$NEW_USER" \
  --role="$ROLE"

# Verificar
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten=bindings[].members \
  --filter="bindings.members=$NEW_USER"
```

### Revocar Permiso (Offboarding)

```bash
# Cuando dev se va
DEPARTED_USER="departed@wa-team.com"

gcloud projects remove-iam-policy-binding $PROJECT_ID \
  --member="user:$DEPARTED_USER" \
  --role="roles/run.developer"

# Verificar removido
gcloud projects get-iam-policy $PROJECT_ID \
  --flatten=bindings[].members \
  --filter="bindings.members=$DEPARTED_USER"
```

### Auditoría Mensual

```bash
# Primer viernes de cada mes:

# 1. Exportar IAM bindings
gcloud projects get-iam-policy $PROJECT_ID \
  > /tmp/iam-audit-$(date +%Y%m%d).yaml

# 2. Revisar
cat /tmp/iam-audit-202401.yaml

# 3. Verificar:
# - ¿Hay usuarios que no debería estar?
# - ¿Hay roles que son muy altos?
# - ¿Hay service accounts abandonados?

# 4. Documentar
echo "IAM audit $(date +%Y-%m-%d): OK / CHANGES NEEDED" >> docs/security/IAM_AUDIT_LOG.md
```

## PII Logging & Sanitización

### Qué información NO loguear

```python
# ❌ NO PERMITIDO en logs
- phone_number (clientes)
- email (clientes)
- nombre completo cliente
- tarjeta de crédito (si se guarda)
- documento de identidad

# ✅ PERMITIDO en logs
- request_id
- endpoint
- status_code
- timestamp
- latency_ms
- error_type
```

### Sanitizar Logs (Paso 10)

```python
# wa_orchestrator/obs/logging.py

import re

def sanitize_phone(text: str) -> str:
    """Reemplaza números telefónicos con [REDACTED]"""
    return re.sub(r'\+\d{10,15}', '[PHONE_REDACTED]', text)

def sanitize_email(text: str) -> str:
    """Reemplaza emails con [REDACTED]"""
    return re.sub(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}', 
                  '[EMAIL_REDACTED]', text)

# En handlers:
logger.info(f"Message from {sanitize_phone(phone)}: {text}")
# Output: "Message from [PHONE_REDACTED]: hola"
```

### Verificar Logs No Tienen PII

```bash
# Buscar patterns de PII en logs
gcloud run services logs read wa-backend --limit=1000 | \
  grep -E '(\+[0-9]{10,15}|[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})'

# Si encuentra resultados: ❌ ISSUE
# → Revisar logging, aplicar sanitización
# → Purgar logs históricos con PII
```

## Validación de Webhook Signature

### HMAC-SHA256 en X-Hub-Signature

Cada webhook debe validarse:

```python
# wa_orchestrator/handlers/webhook.py

import hmac
import hashlib

def verify_wa_signature(request_body: bytes, signature_header: str, app_secret: str) -> bool:
    """
    Verifica X-Hub-Signature (HMAC-SHA256)
    
    Formato header: sha256=abcd1234...
    """
    expected_signature = hmac.new(
        key=app_secret.encode(),
        msg=request_body,
        digestmod=hashlib.sha256
    ).hexdigest()
    
    provided_signature = signature_header.replace("sha256=", "")
    
    # Constant-time comparison (evita timing attacks)
    return hmac.compare_digest(expected_signature, provided_signature)

# En FastAPI:
@app.post("/webhook")
async def webhook(request: Request):
    body = await request.body()
    signature = request.headers.get("X-Hub-Signature", "")
    
    if not verify_wa_signature(body, signature, WA_APP_SECRET):
        logger.warning(f"Invalid signature: {signature}")
        raise HTTPException(status_code=401, detail="Unauthorized")
    
    # Procesar mensaje...
    return {"status": "ok"}
```

### Rate Limiting

Proteger contra abuso:

```python
# wa_orchestrator/middleware/rate_limit.py

from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(
    key_func=get_remote_address,
    default_limits=["200/day", "50/hour"]
)

# En FastAPI:
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

@app.post("/webhook")
@limiter.limit("120/minute")  # 120 requests per minute max
async def webhook(request: Request):
    ...
```

### Verificación en Tests

```python
# tests/test_nlu_slots.py - ya incluido

def test_webhook_sin_firma():
    """Rechaza webhook sin firma"""
    response = client.post("/webhook", json={})
    assert response.status_code == 401

def test_webhook_firma_invalida():
    """Rechaza webhook con HMAC inválido"""
    payload = {"test": "data"}
    invalid_signature = "sha256=invalid_hmac_signature"
    
    response = client.post(
        "/webhook",
        json=payload,
        headers={"X-Hub-Signature": invalid_signature}
    )
    assert response.status_code == 401

def test_rate_limiting():
    """Rechaza requests después de límite (120/min)"""
    for i in range(121):
        response = client.get("/metrics")
        if i < 120:
            assert response.status_code == 200
        else:
            assert response.status_code == 429  # Too Many Requests
```

## Inyección SQL & NoSQL Injection

### Prevención (ORM)

```python
# ✅ SEGURO: Usar ORM (SQLAlchemy)
from sqlalchemy import select
from wa_orchestrator.models import Reserva

# Nunca string interpolation
result = session.execute(
    select(Reserva).where(Reserva.id == reserva_id)
)

# ❌ INSEGURO: Raw SQL
result = session.execute(f"SELECT * FROM reservas WHERE id = {reserva_id}")
# → Vulnerable a: "; DROP TABLE reservas; --"
```

### Validación de Input

```python
# wa_orchestrator/validators.py

from pydantic import BaseModel, validator
import re

class ReservationRequest(BaseModel):
    party_size: int  # Solo número
    date: str        # Formato: YYYY-MM-DD
    name: str        # Solo alfanuméricos + espacios
    
    @validator('name')
    def name_alphanumeric(cls, v):
        if not re.match(r"^[a-zA-ZáéíóúÁÉÍÓÚñÑ\s]{1,100}$", v):
            raise ValueError('Name must be alphanumeric')
        return v
    
    @validator('date')
    def date_format(cls, v):
        if not re.match(r"^\d{4}-\d{2}-\d{2}$", v):
            raise ValueError('Date must be YYYY-MM-DD')
        return v
```

## Prompt Injection Prevention

### Validación de Input para NLU

```python
# wa_orchestrator/nlu/validators.py

import re

def sanitize_user_input(text: str) -> str:
    """Remove potential prompt injection patterns"""
    # Remover instrucciones SQL/code
    dangerous_patterns = [
        r'(union|select|insert|update|delete)\s+(from|into)',
        r'(exec|execute|script|eval)',
        r'(java|python|bash).*(code|script|import)',
    ]
    
    sanitized = text
    for pattern in dangerous_patterns:
        sanitized = re.sub(pattern, '', sanitized, flags=re.IGNORECASE)
    
    # Limit length (evita DoS)
    sanitized = sanitized[:500]
    
    return sanitized

# En handlers:
cleaned_text = sanitize_user_input(user_message)
slots = nlu_module.extract_slots(cleaned_text)
```

### Testing

```python
# tests/test_nlu_slots.py

def test_prompt_injection_sql():
    """Detecta y rechaza SQL injection en slots"""
    malicious_input = "reservar'; DROP TABLE reservas; --"
    sanitized = sanitize_user_input(malicious_input)
    
    # No debe contener SQL keywords
    assert "DROP TABLE" not in sanitized
    assert ";" not in sanitized

def test_prompt_injection_code():
    """Detecta y rechaza code execution patterns"""
    malicious = "__import__('os').system('rm -rf /')"
    sanitized = sanitize_user_input(malicious)
    
    # No debe contener patterns peligrosos
    assert "__import__" not in sanitized
    assert "import(" not in sanitized
```

## Compliance & Auditoría

### Checklist de Seguridad (Mensual)

- [ ] Secrets rotados (últimos 90 días)
- [ ] IAM audit completado
- [ ] Logs sin PII (scanning automático)
- [ ] Webhook signatures validadas (tests pass)
- [ ] Rate limiting activo
- [ ] Input validation en lugar
- [ ] No SQL injection vulnerabilities
- [ ] GitHub security alerts: 0
- [ ] Dependency vulnerabilities: 0

### Verificar Vulnerabilidades

```bash
# Dependency vulnerabilities (desde requirements.txt)
pip install safety
safety check

# GitHub security alerts
# Ir a: https://github.com/tu-repo/security/alerts

# SAST scanning (static analysis)
# Bandit report disponible en: CI/CD logs
```

## Incident de Seguridad

Si detectas breach / acceso no autorizado:

```
1. INMEDIATO:
   - Slack #security: ⚠️ SECURITY INCIDENT
   - No compartir detalles públicamente

2. DENTRO DE 15 MIN:
   - Revisar Cloud Audit Logs (quién accedió qué)
   - Verificar si secrets fueron comprometidos
   
3. SI SECRETS COMPROMETIDOS:
   - Rotar secrets inmediatamente
   - Cambiar contraseñas admin
   - Revocar tokens

4. POSTMORTEM:
   - Investigar causa raíz (cómo ingresó?)
   - Preventivas (qué faltó?)
   - Comunicar a afectados
```

## Recursos

- Google Cloud Security Best Practices: https://cloud.google.com/security/best-practices
- OWASP Top 10: https://owasp.org/www-project-top-ten/
- Secret Management: https://cloud.google.com/secret-manager/docs
- Compliance: docs/compliance.md (si existe)

**Última actualización:** 2024-01-15
**Próxima revisión:** 2024-02-15
**Security Contact:** security@wa-team.com
