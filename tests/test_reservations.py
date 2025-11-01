"""
Pruebas unitarias para el servicio de reservas.

Verifica la lógica de negocio de creación, cancelación y consulta de reservas.
"""

import pytest
import tempfile
from datetime import datetime, timedelta
from pathlib import Path
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from wa_orchestrator.db.models import Base, Customer, Table, Reservation, ReservationStatus, TableArea
from wa_orchestrator.services.reservations import ReservationService, ReservationError


class TestReservationService:
    """Pruebas para el servicio de reservas."""
    
    @pytest.fixture
    def test_db(self):
        """Crea base de datos temporal para tests."""
        # Crear base de datos en memoria
        engine = create_engine("sqlite:///:memory:", echo=False)
        Base.metadata.create_all(engine)
        
        SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
        session = SessionLocal()
        
        # Crear mesas de prueba
        test_tables = [
            Table(number="1", capacity=2, area=TableArea.SALON_PRINCIPAL, is_active=True),
            Table(number="2", capacity=4, area=TableArea.SALON_PRINCIPAL, is_active=True),
            Table(number="T1", capacity=4, area=TableArea.TERRAZA, is_active=True),
            Table(number="T2", capacity=6, area=TableArea.TERRAZA, is_active=True),
            Table(number="P1", capacity=8, area=TableArea.SALON_PRIVADO, is_active=True),
        ]
        
        for table in test_tables:
            session.add(table)
        
        session.commit()
        session.close()
        
        yield engine, SessionLocal
        
        # Cleanup no necesario para base de datos en memoria
    
    @pytest.fixture
    def reservation_service(self, test_db):
        """Crea servicio de reservas con base de datos de prueba."""
        engine, SessionLocal = test_db
        
        # Crear servicio modificado para usar la DB de test
        service = ReservationService()
        service.engine = engine
        service.SessionLocal = SessionLocal
        
        return service
    
    def test_create_reservation_success(self, reservation_service):
        """Test creación exitosa de reserva."""
        phone = "5491134567890"
        party_size = 4
        reservation_datetime = datetime.now() + timedelta(days=1, hours=2)
        
        result = reservation_service.create_reservation(
            phone_number=phone,
            party_size=party_size,
            reservation_datetime=reservation_datetime,
            preferred_area="salon_principal"
        )
        
        assert result is not None
        assert result["party_size"] == party_size
        assert result["status"] == "confirmada"
        assert "confirmation_code" in result
        assert len(result["confirmation_code"]) == 6
        assert result["table_number"] in ["1", "2"]  # Mesas de capacidad apropiada
    
    def test_create_reservation_invalid_party_size(self, reservation_service):
        """Test falla por tamaño de grupo inválido."""
        phone = "5491134567890"
        reservation_datetime = datetime.now() + timedelta(days=1)
        
        # Grupo muy grande
        with pytest.raises(ReservationError, match="tamaño del grupo"):
            reservation_service.create_reservation(
                phone_number=phone,
                party_size=50,
                reservation_datetime=reservation_datetime
            )
        
        # Grupo muy pequeño
        with pytest.raises(ReservationError, match="tamaño del grupo"):
            reservation_service.create_reservation(
                phone_number=phone,
                party_size=0,
                reservation_datetime=reservation_datetime
            )
    
    def test_create_reservation_past_date(self, reservation_service):
        """Test falla por fecha en el pasado."""
        phone = "5491134567890"
        past_datetime = datetime.now() - timedelta(hours=1)
        
        with pytest.raises(ReservationError, match="fechas pasadas"):
            reservation_service.create_reservation(
                phone_number=phone,
                party_size=4,
                reservation_datetime=past_datetime
            )
    
    def test_create_reservation_preferred_area(self, reservation_service):
        """Test creación con área preferida."""
        phone = "5491134567890"
        party_size = 4
        reservation_datetime = datetime.now() + timedelta(days=1, hours=2)
        
        result = reservation_service.create_reservation(
            phone_number=phone,
            party_size=party_size,
            reservation_datetime=reservation_datetime,
            preferred_area="terraza"
        )
        
        assert result["area"] == "terraza"
        assert result["table_number"] in ["T1", "T2"]
    
    def test_check_availability_success(self, reservation_service):
        """Test consulta de disponibilidad exitosa."""
        party_size = 4
        future_date = datetime.now() + timedelta(days=2)
        
        result = reservation_service.check_availability(
            party_size=party_size,
            reservation_date=future_date
        )
        
        assert result["available"] == True
        assert result["party_size"] == party_size
        assert len(result["available_slots"]) > 0
        assert result["total_slots"] > 0
    
    def test_check_availability_invalid_size(self, reservation_service):
        """Test consulta con tamaño inválido."""
        future_date = datetime.now() + timedelta(days=1)
        
        result = reservation_service.check_availability(
            party_size=50,
            reservation_date=future_date
        )
        
        assert result["available"] == False
        assert "error" in result
    
    def test_cancel_reservation_success(self, reservation_service):
        """Test cancelación exitosa de reserva."""
        phone = "5491134567890"
        party_size = 4
        reservation_datetime = datetime.now() + timedelta(days=1, hours=2)
        
        # Crear reserva
        create_result = reservation_service.create_reservation(
            phone_number=phone,
            party_size=party_size,
            reservation_datetime=reservation_datetime
        )
        
        # Cancelar reserva
        cancel_result = reservation_service.cancel_reservation(
            phone_number=phone,
            reservation_id=str(create_result["reservation_id"])
        )
        
        assert cancel_result["success"] == True
        assert cancel_result["reservation_id"] == create_result["reservation_id"]
        assert cancel_result["confirmation_code"] == create_result["confirmation_code"]
    
    def test_cancel_reservation_not_found(self, reservation_service):
        """Test cancelación de reserva inexistente."""
        phone = "5491199999999"  # Teléfono sin reservas
        
        result = reservation_service.cancel_reservation(
            phone_number=phone,
            reservation_id="123456"
        )
        
        assert result["success"] == False
        assert "no se encontraron reservas" in result["error"].lower()
    
    def test_get_customer_reservations(self, reservation_service):
        """Test obtención de reservas de cliente."""
        phone = "5491134567890"
        party_size = 4
        reservation_datetime = datetime.now() + timedelta(days=1, hours=2)
        
        # Crear reserva
        reservation_service.create_reservation(
            phone_number=phone,
            party_size=party_size,
            reservation_datetime=reservation_datetime
        )
        
        # Obtener reservas
        reservations = reservation_service.get_customer_reservations(phone)
        
        assert len(reservations) == 1
        assert reservations[0]["party_size"] == party_size
        assert reservations[0]["status"] == "confirmed"
    
    def test_no_availability_for_large_group(self, reservation_service):
        """Test sin disponibilidad para grupo grande."""
        party_size = 10  # Más grande que las mesas disponibles (máx 8)
        future_date = datetime.now() + timedelta(days=1)
        
        result = reservation_service.check_availability(
            party_size=party_size,
            reservation_date=future_date
        )
        
        # Debería encontrar mesa P1 de capacidad 8, pero depende de la lógica
        # En este caso, como 10 > 8, no debería haber disponibilidad
        # a menos que el sistema permita overbooking
        available_slots = result.get("available_slots", [])
        # El resultado depende de si hay mesas que acomoden 10 personas
        # Con nuestras mesas de test (máx 8), no debería haber disponibilidad
        assert len(available_slots) == 0 or result["available"] == False
    
    def test_multiple_reservations_same_time(self, reservation_service):
        """Test múltiples reservas para el mismo horario."""
        phone1 = "5491134567890"
        phone2 = "5491134567891"
        party_size = 2
        reservation_datetime = datetime.now() + timedelta(days=1, hours=2)
        
        # Primera reserva (debería funcionar)
        result1 = reservation_service.create_reservation(
            phone_number=phone1,
            party_size=party_size,
            reservation_datetime=reservation_datetime
        )
        
        # Segunda reserva mismo horario (debería encontrar otra mesa)
        result2 = reservation_service.create_reservation(
            phone_number=phone2,
            party_size=party_size,
            reservation_datetime=reservation_datetime
        )
        
        assert result1 is not None
        assert result2 is not None
        assert result1["table_number"] != result2["table_number"]


if __name__ == "__main__":
    pytest.main([__file__, "-v"])