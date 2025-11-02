# Admin API - WhatsApp IA Reservas

## Descripción

La Admin API proporciona endpoints protegidos para gestionar el contenido del restaurante:
- Menú (items, precios, alérgenos)
- Horarios de negocio (por día)
- Excepciones (feriados, eventos especiales)
- Knowledge Base (reconstrucción de índice TF-IDF)

## Seguridad: Bearer Token

Todos los endpoints admin requieren autenticación Bearer token:

```
Authorization: Bearer {ADMIN_API_TOKEN}
```

### Variable de entorno
```bash
export ADMIN_API_TOKEN="super-secret-admin-token"
```

Si no está configurada, se usa el valor por defecto: `"super-secret-admin-token"`

## Base URL

```
http://localhost:8001/api/v1/admin
```

## Endpoints

### 1. Health Check

**GET** `/admin/health`

Verifica que el Admin API funciona y tiene conexión a la base de datos.

```bash
curl -H "Authorization: Bearer super-secret-admin-token" \
  http://localhost:8001/api/v1/admin/health
```

**Respuesta:**
```json
{
  "ok": true,
  "message": "Admin API funcionando correctamente",
  "data": {
    "restaurant": "Restaurante Demo",
    "status": "healthy",
    "timestamp": "2025-11-02T20:30:00.000Z"
  }
}
```

---

### 2. Menú - Agregar/Actualizar Item

**POST** `/admin/menu/upsert`

Agrega o actualiza un item del menú (busca por nombre exacto).

```bash
curl -X POST \
  -H "Authorization: Bearer super-secret-admin-token" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Milanesa a caballo",
    "description": "Milanesa de ternera con huevo frito y papas",
    "price": 24.50,
    "category": "plato principal",
    "allergens": "gluten,huevo",
    "available": true
  }' \
  http://localhost:8001/api/v1/admin/menu/upsert
```

**Respuesta:**
```json
{
  "ok": true,
  "message": "Item del menú creado correctamente",
  "data": {
    "name": "Milanesa a caballo",
    "action": "creado"
  }
}
```

---

### 3. Menú - Importar Múltiples Items

**POST** `/admin/menu/import`

Importa múltiples items del menú. Con `replace_existing=true` vacía la tabla antes de importar.

```bash
curl -X POST \
  -H "Authorization: Bearer super-secret-admin-token" \
  -H "Content-Type: application/json" \
  -d '{
    "items": [
      {
        "name": "Milanesa a caballo",
        "description": "Milanesa de ternera con huevo frito y papas",
        "price": 24.50,
        "category": "plato principal",
        "allergens": "gluten,huevo",
        "available": true
      },
      {
        "name": "Ensalada mixta",
        "description": "Ensalada fresca con verduras de estación",
        "price": 12.00,
        "category": "entrada",
        "allergens": null,
        "available": true
      }
    ],
    "replace_existing": false
  }' \
  http://localhost:8001/api/v1/admin/menu/import
```

**Respuesta:**
```json
{
  "ok": true,
  "message": "Menú importado correctamente",
  "data": {
    "items_created": 2,
    "items_updated": 0,
    "total": 2
  }
}
```

---

### 4. Horarios - Publicar

**POST** `/admin/hours/publish`

Publica los horarios de atención (reemplaza tabla completa).
Requiere 7 días (lunes a domingo, 0-6).

```bash
curl -X POST \
  -H "Authorization: Bearer super-secret-admin-token" \
  -H "Content-Type: application/json" \
  -d '{
    "hours": [
      {"day_of_week": 0, "opening_time": "18:00", "closing_time": "23:30", "is_open": true},
      {"day_of_week": 1, "opening_time": "18:00", "closing_time": "23:30", "is_open": true},
      {"day_of_week": 2, "opening_time": "18:00", "closing_time": "23:30", "is_open": true},
      {"day_of_week": 3, "opening_time": "18:00", "closing_time": "23:30", "is_open": true},
      {"day_of_week": 4, "opening_time": "18:00", "closing_time": "00:00", "is_open": true},
      {"day_of_week": 5, "opening_time": "18:00", "closing_time": "00:00", "is_open": true},
      {"day_of_week": 6, "opening_time": "12:00", "closing_time": "23:30", "is_open": true}
    ]
  }' \
  http://localhost:8001/api/v1/admin/hours/publish
```

**Respuesta:**
```json
{
  "ok": true,
  "message": "Horarios publicados correctamente",
  "data": {
    "days_updated": 7
  }
}
```

---

### 5. Horarios - Obtener

**GET** `/admin/hours`

Obtiene los horarios actuales.

```bash
curl -H "Authorization: Bearer super-secret-admin-token" \
  http://localhost:8001/api/v1/admin/hours
```

**Respuesta:**
```json
{
  "ok": true,
  "message": "Horarios recuperados",
  "data": {
    "hours": [
      {
        "day": 0,
        "day_name": "Lunes",
        "open": "18:00",
        "close": "23:30",
        "is_closed": false
      },
      ...
    ]
  }
}
```

---

### 6. Excepciones - Publicar

**POST** `/admin/exceptions/publish`

Publica excepciones de horario (feriados, eventos especiales).

```bash
curl -X POST \
  -H "Authorization: Bearer super-secret-admin-token" \
  -H "Content-Type: application/json" \
  -d '{
    "exceptions": [
      {
        "date": "2025-12-25",
        "opening_time": null,
        "closing_time": null,
        "is_open": false,
        "reason": "Feriado - Navidad"
      },
      {
        "date": "2025-01-01",
        "opening_time": "20:00",
        "closing_time": "23:00",
        "is_open": true,
        "reason": "Año Nuevo - Horario especial"
      }
    ],
    "replace_existing": false
  }' \
  http://localhost:8001/api/v1/admin/exceptions/publish
```

**Respuesta:**
```json
{
  "ok": true,
  "message": "Excepciones publicadas correctamente",
  "data": {
    "exceptions_created": 2,
    "exceptions_updated": 0,
    "total": 2
  }
}
```

---

### 7. Excepciones - Obtener

**GET** `/admin/exceptions`

Obtiene todas las excepciones de horario definidas.

```bash
curl -H "Authorization: Bearer super-secret-admin-token" \
  http://localhost:8001/api/v1/admin/exceptions
```

**Respuesta:**
```json
{
  "ok": true,
  "message": "Excepciones recuperadas",
  "data": {
    "exceptions": [
      {
        "date": "2025-12-25",
        "open": null,
        "close": null,
        "is_open": false,
        "reason": "Feriado - Navidad"
      }
    ]
  }
}
```

---

### 8. Knowledge Base - Reconstruir

**POST** `/admin/kb/rebuild`

Reconstruye el índice TF-IDF leyendo archivos markdown de `data/kb/`.

```bash
curl -X POST \
  -H "Authorization: Bearer super-secret-admin-token" \
  http://localhost:8001/api/v1/admin/kb/rebuild
```

**Respuesta:**
```json
{
  "ok": true,
  "message": "Knowledge Base reconstruida exitosamente",
  "data": {
    "chunks_created": 70,
    "metadata_entries": 70,
    "model_path": "wa_orchestrator/rag/tfidf.joblib",
    "status": "success"
  }
}
```

---

### 9. Versiones - Obtener

**GET** `/admin/versions`

Obtiene historial de versiones (PLACEHOLDER para futuro).

```bash
curl -H "Authorization: Bearer super-secret-admin-token" \
  http://localhost:8001/api/v1/admin/versions
```

**Respuesta:**
```json
{
  "ok": true,
  "message": "Versiones disponibles",
  "data": {
    "versions": [
      {
        "version": 1,
        "timestamp": "2025-11-02T20:30:00.000Z",
        "type": "kb"
      }
    ]
  }
}
```

---

### 10. Versiones - Rollback

**POST** `/admin/versions/rollback`

Revierte a una versión anterior (PLACEHOLDER para futuro).

```bash
curl -X POST \
  -H "Authorization: Bearer super-secret-admin-token" \
  http://localhost:8001/api/v1/admin/versions/rollback \
  -d '{"version": 1}'
```

---

## Validaciones

### MenuItemIn
- `name`: Requerido, máx 255 caracteres
- `price`: Requerido, > 0
- `category`: Requerido, máx 50 caracteres
- `description`: Opcional, máx 1000 caracteres
- `allergens`: Opcional, formato "gluten,huevo,mariscos"
- `available`: Booleano (default: true)

### BusinessHourIn
- `day_of_week`: 0-6 (lunes-domingo)
- `opening_time`: Formato HH:MM (00:00-23:59)
- `closing_time`: Formato HH:MM, debe ser posterior a opening_time
- `is_open`: Booleano (default: true)

### ExceptionIn
- `date`: Formato YYYY-MM-DD
- `opening_time`: Formato HH:MM o null
- `closing_time`: Formato HH:MM o null
- `is_open`: Booleano
- `reason`: Opcional, máx 255 caracteres

---

## Códigos de Error

| Status | Razón |
|--------|-------|
| **401** | Header Authorization ausente |
| **403** | Token inválido o expirado |
| **422** | Validación de datos falla (payload inválido) |
| **500** | Error interno del servidor |
| **503** | Base de datos no disponible |

---

## Ejemplo Python

```python
import requests

BASE_URL = "http://localhost:8001/api/v1/admin"
ADMIN_TOKEN = "super-secret-admin-token"

headers = {
    "Authorization": f"Bearer {ADMIN_TOKEN}",
    "Content-Type": "application/json"
}

# Health check
response = requests.get(f"{BASE_URL}/health", headers=headers)
print(response.json())

# Importar menú
menu_data = {
    "items": [
        {
            "name": "Milanesa a caballo",
            "description": "Con huevo frito y papas",
            "price": 24.50,
            "category": "plato principal",
            "allergens": "gluten,huevo",
            "available": True
        }
    ],
    "replace_existing": False
}

response = requests.post(f"{BASE_URL}/menu/import", json=menu_data, headers=headers)
print(response.json())
```

---

## Integración con CI/CD

Usar script de test:
```bash
# PowerShell
.\test_admin_api.ps1

# Bash
bash test_admin_api.sh
```

---

## Notas Importantes

1. **Token Seguro**: En producción, usar variable de entorno `ADMIN_API_TOKEN` fuerte y cambiarla regularmente
2. **HTTPS**: En producción, siempre usar HTTPS, nunca HTTP
3. **Imports Atómicos**: Las importaciones son atómicas - fallan completamente o funcionan completamente
4. **Rebuild KB**: Requiere archivos markdown en `data/kb/`
5. **Timezone**: Todas las fechas/horas usan UTC; convertir según timezone del restaurante

---

## Historial de Cambios

- **v1.0** (2025-11-02): Implementación inicial Admin API
  - 10 endpoints (menu, hours, exceptions, kb, versions, health)
  - Bearer token authentication
  - Pydantic validation
  - Database persistence

---
