# WhatsApp IA Reservas Demo

Sistema de demostración para gestión inteligente de reservas de restaurante vía WhatsApp usando Python, FastAPI y técnicas de IA.

## Características Principales

- 🤖 **NLU (Natural Language Understanding)**: Detección de intenciones usando regex patterns
- 📚 **RAG (Retrieval-Augmented Generation)**: Búsqueda semántica con TF-IDF en knowledge base
- 🗄️ **Base de datos**: SQLAlchemy con SQLite para gestión de reservas
- 📱 **WhatsApp Integration**: Webhook y stub para WhatsApp Business Cloud API
- 🎯 **Casos de uso**: reservar, modificar, cancelar, disponibilidad, menú, horarios, atención humana

## Arquitectura

```
whatsapp-ia-reservas-demo/
├─ wa_webhook/           # Servicio webhook de WhatsApp
│  └─ main.py           # Endpoints GET/POST para webhook
├─ wa_orchestrator/     # Orquestador principal
│  ├─ main.py          # API principal con lógica de negocio
│  ├─ config.py        # Configuración centralizada
│  ├─ db/              # Modelos y base de datos
│  │  ├─ models.py     # SQLAlchemy models
│  │  └─ init_db.py    # Inicialización y seed
│  ├─ nlu/             # Natural Language Understanding
│  │  └─ router.py     # Clasificación de intenciones
│  ├─ rag/             # Retrieval-Augmented Generation
│  │  ├─ ingest.py     # Indexación de documentos
│  │  └─ retriever.py  # Búsqueda semántica
│  └─ services/        # Servicios de negocio
│     ├─ reservations.py  # Lógica de reservas
│     └─ whatsapp.py     # Integración WhatsApp
├─ data/
│  ├─ kb/              # Knowledge base (markdown)
│  │  ├─ menus_v1.md   # Información del menú
│  │  ├─ policies_v1.md # Políticas del restaurante
│  │  └─ info_v1.md    # Información general
│  └─ seed/
│     └─ tables.csv    # Datos iniciales de mesas
└─ tests/              # Pruebas unitarias
```

## Requisitos del Sistema

- Python 3.10 o superior
- SQLite (incluido con Python)
- Espacio en disco: ~100MB
- RAM: ~512MB mínimo

## Instalación y Configuración

### 1. Clonar el repositorio

```bash
git clone <repository-url>
cd whatsapp-ia-reservas-demo
```

### 2. Crear entorno virtual

```bash
# Windows
python -m venv .venv
.venv\Scripts\activate

# Linux/Mac
python -m venv .venv
source .venv/bin/activate
```

### 3. Instalar dependencias

```bash
pip install -r requirements.txt
```

### 4. Configurar variables de entorno

```bash
# Copiar archivo de ejemplo
copy .env.example .env

# Editar .env con tus configuraciones
# Las configuraciones por defecto funcionan para demo local
```

### 5. Inicializar base de datos

```bash
python -m wa_orchestrator.db.init_db
```

### 6. Construir índice RAG

```bash
python -m wa_orchestrator.rag.ingest
```

## Ejecución

### Iniciar servicios

**Terminal 1 - Webhook Service (Puerto 8000)**
```bash
uvicorn wa_webhook.main:app --reload --port 8000
```

**Terminal 2 - Orchestrator Service (Puerto 8001)**
```bash
uvicorn wa_orchestrator.main:app --reload --port 8001
```

### Verificar servicios

```bash
# Health check webhook
curl http://localhost:8000/health

# Health check orchestrator
curl http://localhost:8001/health

# Estadísticas del sistema
curl http://localhost:8001/stats
```

## Uso y Testing

### 1. Test completo de flujo

```bash
# Simular mensaje de WhatsApp
curl -X POST http://localhost:8000/webhook \
  -H "Content-Type: application/json" \
  -d '{
    "object": "whatsapp_business_account",
    "entry": [{
      "id": "PHONE_NUMBER_ID",
      "changes": [{
        "value": {
          "messages": [{
            "from": "5491134567890",
            "text": {"body": "mesa para 4 hoy 20:30 en terraza"}
          }]
        }
      }]
    }]
  }'
```

### 2. Ejemplos de mensajes soportados

```
# Reservas
"mesa para 4 personas mañana a las 20:30"
"quiero reservar para 6 el viernes a las 21:00"
"necesito una mesa para 2 hoy en terraza"

# Disponibilidad
"hay mesa para 4 el sábado?"
"disponibilidad para 8 personas el domingo"

# Menú
"qué platos tienen?"
"precios del menú"
"opciones vegetarianas"

# Horarios
"a qué hora abren?"
"horarios de atención"

# Cancelación
"cancelar mi reserva"
"no puedo ir mañana"

# Atención humana
"quiero hablar con una persona"
"atención al cliente"
```

### 3. Testing de componentes individuales

**NLU Testing:**
```bash
python -m wa_orchestrator.nlu.router
```

**RAG Testing:**
```bash
python -m wa_orchestrator.rag.retriever
```

**WhatsApp Service Testing:**
```bash
python -m wa_orchestrator.services.whatsapp
```

## Estructura de Datos

### Base de datos

- **customers**: Información de clientes
- **tables**: Mesas del restaurante (15 mesas en diferentes áreas)
- **reservations**: Reservas con estados y tracking
- **message_logs**: Auditoría de mensajes

### Knowledge Base

- **menus_v1.md**: Menú completo con precios
- **policies_v1.md**: Políticas de reservas y cancelaciones
- **info_v1.md**: Información del restaurante, horarios, contacto

## API Endpoints

### Webhook Service (Puerto 8000)

- `GET /webhook` - Verificación de webhook de WhatsApp
- `POST /webhook` - Recepción de eventos de WhatsApp
- `GET /health` - Health check

### Orchestrator Service (Puerto 8001)

- `POST /events` - Procesamiento de eventos (NLU → RAG → Negocio)
- `GET /health` - Health check
- `GET /stats` - Estadísticas del sistema

## Configuración Avanzada

### Variables de entorno importantes

```bash
# Base de datos
DATABASE_URL=sqlite:///./restaurant.db

# Servicios
WEBHOOK_PORT=8000
ORCHESTRATOR_PORT=8001

# WhatsApp (para producción)
WEBHOOK_VERIFY_TOKEN=tu_token_aqui

# Restaurante
RESTAURANT_NAME=Restaurante Demo
OPENING_HOURS_START=18:00
OPENING_HOURS_END=23:00
```

### Personalización del NLU

Editar `wa_orchestrator/nlu/router.py` para:
- Agregar nuevas intenciones
- Modificar patrones regex
- Ajustar extracción de entidades

### Personalización del RAG

Editar archivos en `data/kb/` para:
- Actualizar información del menú
- Modificar políticas
- Agregar nueva información

Después ejecutar: `python -m wa_orchestrator.rag.ingest`

## Pruebas

### Ejecutar todas las pruebas

```bash
pytest tests/ -v
```

### Pruebas por componente

```bash
# NLU
pytest tests/test_nlu.py -v

# RAG
pytest tests/test_rag.py -v

# Reservas
pytest tests/test_reservations.py -v
```

## Troubleshooting

### Problemas comunes

**Error: "Archivo de modelo no encontrado"**
```bash
# Solución: Construir índice RAG
python -m wa_orchestrator.rag.ingest
```

**Error: "No such table"**
```bash
# Solución: Inicializar base de datos
python -m wa_orchestrator.db.init_db
```

**Puerto en uso**
```bash
# Verificar qué proceso usa el puerto
netstat -ano | findstr :8000
netstat -ano | findstr :8001

# Cambiar puertos en .env si es necesario
```

### Logs y debugging

```bash
# Aumentar nivel de logging
export LOG_LEVEL=DEBUG

# Ver logs en tiempo real
tail -f logs/app.log  # Si se configura logging a archivo
```

## Limitaciones del MVP

- **IA Simplificada**: Usa regex en lugar de ML models complejos
- **Datos sintéticos**: No contiene información real de clientes
- **Sin autenticación**: Sistema demo sin seguridad
- **WhatsApp Demo**: Imprime mensajes en lugar de enviarlos realmente
- **NLP básico**: Detección de fechas/horas simplificada

## Roadmap para Producción

1. **Integración real con WhatsApp Business Cloud API**
2. **ML models para NLU** (spaCy, transformers)
3. **Base de datos en la nube** (PostgreSQL)
4. **Autenticación y autorización**
5. **Monitoring y observabilidad**
6. **Tests de integración completos**
7. **CI/CD pipeline**
8. **Scaling con contenedores**

## Seguridad y Consideraciones

- ⚠️ **Solo para demo**: No usar en producción sin hardening de seguridad
- 🔒 **Variables sensibles**: Nunca commitear .env con datos reales
- 📱 **Tokens de WhatsApp**: Rotar tokens regularmente en producción
- 🗄️ **Base de datos**: Usar bases de datos seguras y encriptadas
- 🌐 **HTTPS**: Implementar SSL/TLS para webhooks reales

## Contribución

1. Fork del repositorio
2. Crear feature branch (`git checkout -b feature/nueva-funcionalidad`)
3. Commit cambios (`git commit -am 'Agregar nueva funcionalidad'`)
4. Push a branch (`git push origin feature/nueva-funcionalidad`)
5. Crear Pull Request

## Licencia

Este proyecto es de demostración educativa. Ver archivo LICENSE para detalles.

## Soporte

Para preguntas o problemas:
- Crear issue en GitHub
- Revisar logs del sistema
- Verificar configuración en .env

---

**Última actualización**: Octubre 2024  
**Versión**: 1.0.0 MVP
