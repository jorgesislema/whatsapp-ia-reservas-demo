# Runbook: Horarios de Operación & Menú

## Resumen
Procedimiento para publicar/actualizar horarios de operación y menú de reservas mediante el panel administrativo.

## Audiencia
- Gerente de restaurante
- Operador administrativo
- Tech support

## Prerequisitos
- Acceso al panel en: https://wa-panel-xxxxx.streamlit.app
- Credenciales de admin (ADMIN_TOKEN)
- Horarios ya definidos en formato correcto

## Procesos

### 1. Actualizar Horarios de Operación

**Cuándo:** Cambios de temporada, cierre especial, horario reducido

**Pasos:**

1. Ingresamos al panel: https://wa-panel-xxxxx.streamlit.app
2. Click en "Configuración" → "Horarios de Operación"
3. Editar horarios por día:
   ```
   Lunes: 12:00 - 15:00, 19:00 - 23:30 (almuerzo y cena)
   Martes: 12:00 - 15:00, 19:00 - 23:30
   Miércoles: 12:00 - 15:00, 19:00 - 23:30
   Jueves: 12:00 - 15:00, 19:00 - 00:00
   Viernes: 12:00 - 15:00, 19:00 - 00:00
   Sábado: 12:00 - 00:00 (sin cierre)
   Domingo: 12:00 - 23:30
   Festivo: Cerrado
   ```

4. Agregar excepciones (si es necesario):
   ```
   Fecha: 2024-02-14 (San Valentín)
   Horario: 19:00 - 23:30 (solo cena, sin almuerzo)
   Aplica: Solo se reciben reservas para cena
   ```

5. Click "Guardar cambios"
6. Confirmación: ✅ "Horarios actualizados exitosamente"

**Validación:**
- Panel muestra "Último update: 2024-01-15 14:30"
- Backend recibe update (log: `INFO: Schedule updated`)

### 2. Importar Menú desde Google Sheets

**Cuándo:** Menú estacional, cambio de platos, actualización de disponibilidad

**Pasos:**

1. Preparar Google Sheet con formato:
   ```
   | id | nombre | descripcion | precio | categoría | disponible |
   |----|--------|-------------|--------|-----------|-----------|
   | 1  | Ceviche| Tradicional | 12.50  | Entrada   | Sí        |
   | 2  | Lomo   | 200g corte  | 18.00  | Plato     | Sí        |
   | 3  | Tiramisú| Postre     | 5.00   | Postre    | No        |
   ```

2. Compartir sheet (link público o CSV export)

3. En panel → "Menú" → "Importar desde Google Sheets"
4. Pegar URL: `https://docs.google.com/spreadsheets/d/xxxxx/export?format=csv`
5. Click "Validar"
6. Revisar preview:
   ```
   Nuevos items: 5
   Items actualizados: 3
   Items eliminados: 1
   ✓ Validación exitosa
   ```
7. Click "Importar"

**Confirmación:**
- ✅ "Menú importado: 8 items activos, 1 descontinuado"
- Log: `INFO: Menu imported from Google Sheets`

### 3. Publicar Cambios en WhatsApp

**Cuándo:** Después de actualizar horarios o menú

**Pasos:**

1. En panel → "Publicar" → "WhatsApp Template Messages"
2. Seleccionar cambios a publicar:
   - [ ] Horarios actualizados
   - [ ] Menú modificado
   - [ ] Excepciones especiales
3. Vista previa de mensaje:
   ```
   📋 *Nuestros horarios* (actualizado)
   
   Lunes a Viernes: 12:00 - 15:00, 19:00 - 23:30
   Sábado: 12:00 - 00:00
   Domingo: 12:00 - 23:30
   
   ¡Reserva tu mesa! Escribe "reservar"
   ```
4. Click "Enviar a todos" (o select target users)
5. Confirmación: ✅ "Mensaje enviado a 427 usuarios"

**Validación en Meta Dashboard:**
- Ir a Meta Business Suite → WhatsApp Manager
- Verificar template "updated_schedule" en status "APPROVED"

### 4. Gestionar Disponibilidad de Mesas

**Cuándo:** Mantenimiento, evento privado, capacidad reducida

**Pasos:**

1. Panel → "Operación" → "Disponibilidad de Mesas"
2. Seleccionar fecha y rango de tiempo:
   ```
   Fecha: 2024-02-14
   Hora: 20:00 - 22:00
   Disponibilidad: Parcial (75% capacidad)
   Motivo: "Evento privado piso 2"
   ```
3. Aplicar cambio:
   - [ ] Inmediato
   - [ ] Programado para: 2024-02-14 18:00
4. Click "Guardar"

**Validación:**
- Bot responde a nuevas reservas:
  ```
  ¡Hola! Para el 14/02 a las 20:00, solo tengo 3 mesas disponibles
  ¿Prefieres otra hora?
  ```

### 5. Reconstruir Knowledge Base

**Cuándo:** Después de cambios importantes en menú/horarios

**Pasos:**

1. Panel → "Administración" → "Knowledge Base"
2. Click "Reconstruir Knowledge Base"
3. Esperar procesamiento:
   ```
   ⏳ Procesando menú (8 items)...
   ⏳ Procesando horarios...
   ⏳ Procesando políticas...
   ✅ Knowledge Base actualizada en 3.2s
   ```
4. Validar:
   - Panel → "Monitoreo" → "Query Performance"
   - Verificar métricas de retrieval:
     ```
     KB retrieval accuracy: 92%
     Query latency P95: 245ms
     ```

## Troubleshooting

| Problema | Causa | Solución |
|----------|-------|----------|
| "Falló al guardar horarios" | Network timeout | Reintentar, verificar conexión |
| Menú no se importa | Formato CSV inválido | Validar headers, separadores |
| Template no se envía | Token expirado | Renovar ADMIN_TOKEN |
| KB rebuild lento | Índices corruptos | Contactar SRE, restaurar backup |

## Escalación

- **Problema de panel:** Contactar panel@wa-team.com
- **Problema de WhatsApp API:** Abrir issue en GitHub (backend repo)
- **Urgencia:** Slack #incidents, @on-call-engineer

## Métricas

Monitorear después de cambios:

```bash
# Panel de operación
- Reservas procesadas: debe estar en línea base
- Tasa de error: < 1%
- Tiempo respuesta: < 800ms P95

# Bot conversations
- Preguntas sobre horarios: cuantificar
- Preguntas sobre menú: cuantificar
- Satisfacción: monitorear en próximas 24h
```

## Contactos

| Rol | Nombre | Teléfono | Slack |
|-----|--------|----------|-------|
| Gerente | Juan Pérez | +58-0414-XXX | @juan.perez |
| Tech Lead | Carlos López | +58-0424-YYY | @carlos.lopez |
| SRE On-Call | - | - | @on-call |

## Documentación Relacionada
- Paso 4: Configuración de menú y horarios
- Paso 6: Panel administrativo
- Paso 8: Operación manual en caso de fallo

**Última actualización:** 2024-01-15
**Próxima revisión:** 2024-02-15
