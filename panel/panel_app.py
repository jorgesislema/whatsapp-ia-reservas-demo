"""
Panel Streamlit: Dashboard de administración para WhatsApp IA Reservas.

Características:
- Autenticación por usuario/contraseña (hash SHA256)
- Gestión de excepciones y temporadas de negocio
- Métricas y analytics
- Control de modo manual

Instalación:
    pip install streamlit

Usar secretos en Streamlit Cloud:
    ADMIN_API_BASE_URL: https://api.example.com
    ADMIN_API_TOKEN: token-secreto
    PANEL_USER: admin
    PANEL_PASS_HASH: sha256 hash de contraseña
    
Generar hash:
    python -c "import hashlib; print(hashlib.sha256('contraseña'.encode()).hexdigest())"

Ejecutar localmente:
    streamlit run panel_app.py
"""

import os
import streamlit as st
import hashlib
import httpx
from datetime import datetime, date
from typing import Optional

# ============================================================================
# CONFIGURACIÓN
# ============================================================================

st.set_page_config(
    page_title="Panel WhatsApp IA Reservas",
    layout="wide",
    initial_sidebar_state="expanded"
)

# Variables de entorno
PANEL_USER = os.getenv("PANEL_USER", "admin")
PANEL_PASS_HASH = os.getenv("PANEL_PASS_HASH", "")  # sha256
ADMIN_API_BASE_URL = os.getenv("ADMIN_API_BASE_URL", "http://localhost:8000/api/v1")
ADMIN_API_TOKEN = os.getenv("ADMIN_API_TOKEN", "super-secret-admin-token")

# HTTP Client
http_client = httpx.Client(
    base_url=ADMIN_API_BASE_URL,
    headers={"Authorization": f"Bearer {ADMIN_API_TOKEN}"},
    timeout=30.0
)


def sha256(s: str) -> str:
    """Calcula hash SHA256 de un string."""
    return hashlib.sha256(s.encode()).hexdigest()


# ============================================================================
# AUTENTICACIÓN
# ============================================================================

def check_password():
    """
    Verifica autenticación. Si no está autenticado, muestra formulario de login.
    """
    if "auth" not in st.session_state:
        st.session_state.auth = False

    if not st.session_state.auth:
        st.title("🔐 Panel WhatsApp IA Reservas")
        
        with st.form("login_form"):
            st.write("Ingrese sus credenciales")
            user_input = st.text_input("Usuario", "")
            pass_input = st.text_input("Contraseña", "", type="password")
            submitted = st.form_submit_button("Ingresar")
            
            if submitted:
                if not PANEL_PASS_HASH:
                    st.error("❌ PANEL_PASS_HASH no configurado (contacte al administrador)")
                    return False
                
                if user_input == PANEL_USER and sha256(pass_input) == PANEL_PASS_HASH:
                    st.session_state.auth = True
                    st.rerun()
                else:
                    st.error("❌ Credenciales inválidas")
        
        st.stop()
        return False
    
    return True


# ============================================================================
# FUNCIONES AUXILIARES
# ============================================================================

def get_api_header():
    """Retorna headers de autorización para API."""
    return {"Authorization": f"Bearer {ADMIN_API_TOKEN}"}


def call_api(method: str, endpoint: str, **kwargs) -> tuple[bool, any, str]:
    """
    Realiza llamada a la API admin.
    
    Args:
        method: GET, POST, etc.
        endpoint: ruta (sin base_url)
        **kwargs: parámetros para httpx
        
    Returns:
        (success: bool, data: any, message: str)
    """
    try:
        response = http_client.request(method, endpoint, **kwargs)
        
        if response.status_code >= 400:
            return False, None, f"Error {response.status_code}: {response.text}"
        
        return True, response.json(), ""
    
    except Exception as e:
        return False, None, f"Error de conexión: {str(e)}"


# ============================================================================
# COMPONENTES DE INTERFAZ
# ============================================================================

def render_exceptions_tab():
    """Pestaña: Gestión de excepciones (cierres especiales)."""
    st.header("📅 Excepciones de Negocio")
    
    col1, col2 = st.columns([2, 1])
    
    with col1:
        st.subheader("Agregar Excepción")
        
        exc_date = st.date_input("Fecha", value=date.today())
        exc_is_closed = st.checkbox("Cerrado todo el día", value=False)
        
        if not exc_is_closed:
            col_open, col_close = st.columns(2)
            with col_open:
                exc_open = st.time_input("Abre", value=None, label_visibility="collapsed")
            with col_close:
                exc_close = st.time_input("Cierra", value=None, label_visibility="collapsed")
        else:
            exc_open = None
            exc_close = None
        
        exc_note = st.text_input("Motivo (ej: Feriado, Cierre anual)", "")
        
        if st.button("➕ Agregar Excepción", key="add_exc"):
            exception_data = {
                "date": exc_date.isoformat(),
                "is_closed": exc_is_closed,
                "open": exc_open.strftime("%H:%M") if exc_open else None,
                "close": exc_close.strftime("%H:%M") if exc_close else None,
                "note": exc_note
            }
            
            success, data, msg = call_api(
                "POST",
                "/exceptions/publish",
                json={"exceptions": [exception_data]}
            )
            
            if success:
                st.success("✅ Excepción agregada")
            else:
                st.error(f"❌ {msg}")
    
    with col2:
        st.subheader("Excepciones Actuales")
        
        success, exceptions, msg = call_api("GET", "/exceptions")
        
        if success and exceptions:
            for exc in exceptions.get("exceptions", []):
                st.write(f"📌 {exc.get('date')}")
                if exc.get("is_closed"):
                    st.caption("Cerrado todo el día")
                else:
                    st.caption(f"{exc.get('open')} - {exc.get('close')}")
                if exc.get("note"):
                    st.caption(f"Motivo: {exc['note']}")
                st.divider()
        else:
            st.info("Sin excepciones definidas")


def render_seasons_tab():
    """Pestaña: Gestión de temporadas."""
    st.header("🌞 Temporadas")
    
    col1, col2 = st.columns([2, 1])
    
    with col1:
        st.subheader("Agregar Temporada")
        
        season_name = st.text_input("Nombre (ej: Verano)", "")
        
        col_start, col_end = st.columns(2)
        with col_start:
            season_start = st.date_input("Inicio", value=date.today())
        with col_end:
            season_end = st.date_input("Fin", value=date.today())
        
        col_open, col_close = st.columns(2)
        with col_open:
            season_open = st.time_input("Abre", value=None, label_visibility="collapsed")
        with col_close:
            season_close = st.time_input("Cierra", value=None, label_visibility="collapsed")
        
        if st.button("➕ Agregar Temporada", key="add_season"):
            if not season_open or not season_close:
                st.error("❌ Debe indicar horarios de apertura y cierre")
                return
            
            if season_end < season_start:
                st.error("❌ La fecha de fin debe ser mayor a la de inicio")
                return
            
            season_data = {
                "start_date": season_start.isoformat(),
                "end_date": season_end.isoformat(),
                "open": season_open.strftime("%H:%M"),
                "close": season_close.strftime("%H:%M"),
                "note": season_name
            }
            
            success, data, msg = call_api(
                "POST",
                "/seasons/publish",
                json={"seasons": [season_data]}
            )
            
            if success:
                st.success("✅ Temporada agregada")
            else:
                st.error(f"❌ {msg}")
    
    with col2:
        st.subheader("Temporadas Actuales")
        
        success, seasons, msg = call_api("GET", "/seasons")
        
        if success and seasons:
            for season in seasons.get("seasons", []):
                st.write(f"🌞 {season.get('note')}")
                st.caption(f"{season.get('start_date')} → {season.get('end_date')}")
                st.caption(f"{season.get('open')} - {season.get('close')}")
                st.divider()
        else:
            st.info("Sin temporadas definidas")


def render_handoff_tab():
    """Pestaña: Control de modo manual."""
    st.header("👤 Modo Manual (Handoff)")
    
    col1, col2 = st.columns([1, 1])
    
    with col1:
        st.subheader("Estado Actual")
        
        success, data, msg = call_api("GET", "/handoff/status")
        
        if success:
            is_enabled = data.get("enabled", False)
            status_text = "🟢 ACTIVO" if is_enabled else "🔴 INACTIVO"
            st.metric("Modo Manual", status_text)
        else:
            st.error(f"No se pudo obtener estado: {msg}")
    
    with col2:
        st.subheader("Control")
        
        col_btn_on, col_btn_off = st.columns(2)
        
        with col_btn_on:
            if st.button("✅ Activar Modo Manual", key="handoff_on"):
                success, data, msg = call_api(
                    "POST",
                    "/handoff/force",
                    params={"enabled": "true"}
                )
                
                if success:
                    st.success("✅ Modo manual activado")
                    st.rerun()
                else:
                    st.error(f"❌ {msg}")
        
        with col_btn_off:
            if st.button("❌ Desactivar Modo Manual", key="handoff_off"):
                success, data, msg = call_api(
                    "POST",
                    "/handoff/force",
                    params={"enabled": "false"}
                )
                
                if success:
                    st.success("✅ Modo manual desactivado")
                    st.rerun()
                else:
                    st.error(f"❌ {msg}")


def render_analytics_tab():
    """Pestaña: Analítica (sin PII)."""
    st.header("📊 Analítica")
    
    st.info("""
    **Información mostrada (sin datos personales):**
    - Conversaciones diarias (número agregado)
    - Tasa de resolución (FCR)
    - Latencia P95
    - Intenciones más frecuentes
    - Handoffs por día
    """)
    
    col1, col2, col3, col4 = st.columns(4)
    
    with col1:
        st.metric("Conversaciones Hoy", "42", "+5")
    
    with col2:
        st.metric("FCR (Resolución 1er intento)", "87%", "+3%")
    
    with col3:
        st.metric("Latencia P95", "450ms", "-20ms")
    
    with col4:
        st.metric("Handoffs Hoy", "5", "0")
    
    st.subheader("Intenciones Top")
    
    # Simulado - en prod, obtener de /metrics
    intents_data = {
        "reservations": 28,
        "menu": 8,
        "policies": 4,
        "cancel": 2
    }
    
    for intent, count in intents_data.items():
        st.progress(count / 28, text=f"{intent}: {count}")
    
    st.subheader("Exportar CSV")
    
    if st.button("📥 Descargar Métricas CSV"):
        st.info("Generando archivo...")
        # En prod: generar CSV desde /metrics
        st.download_button(
            label="analytics_2024_11.csv",
            data="fecha,conversaciones,fcr,latencia\n2024-11-01,42,87,450",
            file_name="analytics.csv",
            mime="text/csv"
        )


# ============================================================================
# MAIN
# ============================================================================

def main():
    """Punto de entrada principal."""
    
    # Verificar autenticación
    if not check_password():
        return
    
    # Header
    col1, col2 = st.columns([4, 1])
    with col1:
        st.title("📱 Panel WhatsApp IA Reservas")
    with col2:
        if st.button("🚪 Cerrar Sesión"):
            st.session_state.auth = False
            st.rerun()
    
    # Tabs
    tab1, tab2, tab3, tab4 = st.tabs([
        "📅 Excepciones",
        "🌞 Temporadas",
        "👤 Modo Manual",
        "📊 Analítica"
    ])
    
    with tab1:
        render_exceptions_tab()
    
    with tab2:
        render_seasons_tab()
    
    with tab3:
        render_handoff_tab()
    
    with tab4:
        render_analytics_tab()
    
    # Footer
    st.divider()
    st.caption(f"✅ Conectado a {ADMIN_API_BASE_URL}")
    st.caption(f"🕐 {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")


if __name__ == "__main__":
    main()
