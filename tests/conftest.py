"""
Archivo de configuración para pytest.

Define configuraciones y fixtures globales para las pruebas.
"""

import pytest
import sys
from pathlib import Path

# Agregar el directorio raíz al path para importaciones
root_dir = Path(__file__).parent.parent
sys.path.insert(0, str(root_dir))

# Configuración de pytest
def pytest_configure(config):
    """Configuración inicial de pytest."""
    import logging
    # Reducir ruido en logs durante tests
    logging.getLogger("wa_orchestrator").setLevel(logging.WARNING)
    logging.getLogger("sqlalchemy").setLevel(logging.WARNING)

@pytest.fixture(scope="session")
def test_data_dir():
    """Directorio con datos de prueba."""
    return Path(__file__).parent / "data"

@pytest.fixture(scope="session")  
def temp_db_path():
    """Path temporal para base de datos de pruebas."""
    import tempfile
    temp_file = tempfile.NamedTemporaryFile(suffix='.db', delete=False)
    temp_file.close()
    
    yield temp_file.name
    
    # Cleanup
    Path(temp_file.name).unlink(missing_ok=True)