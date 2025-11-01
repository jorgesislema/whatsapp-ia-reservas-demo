"""
Pruebas unitarias para el módulo NLU.

Verifica la detección de intenciones y extracción de entidades.
"""

import pytest
from wa_orchestrator.nlu.router import nlu_router, Intent, IntentClassificationResult


class TestNLURouter:
    """Pruebas para el router de NLU."""
    
    def test_reservar_intent(self):
        """Test detección de intención de reservar."""
        test_cases = [
            "mesa para 4 personas mañana a las 20:30",
            "quiero reservar una mesa para 6",
            "necesito una mesa para 2 hoy",
        ]
        
        for text in test_cases:
            result = nlu_router.classify_intent(text)
            assert result.intent == Intent.RESERVAR
            assert result.confidence > 0.0
    
    def test_cancelar_intent(self):
        """Test detección de intención de cancelar."""
        test_cases = [
            "cancelar mi reserva",
            "no puedo ir mañana",
            "anular la reserva de hoy",
        ]
        
        for text in test_cases:
            result = nlu_router.classify_intent(text)
            assert result.intent == Intent.CANCELAR_RESERVA
            assert result.confidence > 0.0
    
    def test_disponibilidad_intent(self):
        """Test detección de intención de disponibilidad."""
        test_cases = [
            "hay mesa para 4 el sábado?",
            "disponibilidad para 8 personas",
            "tienen lugar para mañana?",
        ]
        
        for text in test_cases:
            result = nlu_router.classify_intent(text)
            assert result.intent == Intent.DISPONIBILIDAD
            assert result.confidence > 0.0
    
    def test_menu_intent(self):
        """Test detección de intención de menú."""
        test_cases = [
            "qué platos tienen?",
            "ver el menú",
            "precios de la comida",
        ]
        
        for text in test_cases:
            result = nlu_router.classify_intent(text)
            assert result.intent == Intent.MENU
            assert result.confidence > 0.0
    
    def test_horario_intent(self):
        """Test detección de intención de horarios."""
        test_cases = [
            "a qué hora abren?",
            "horarios de atención",
            "cuándo están abiertos?",
        ]
        
        for text in test_cases:
            result = nlu_router.classify_intent(text)
            assert result.intent == Intent.HORARIO
            assert result.confidence > 0.0
    
    def test_humano_intent(self):
        """Test detección de intención de atención humana."""
        test_cases = [
            "quiero hablar con una persona",
            "atención al cliente",
            "necesito ayuda de un humano",
        ]
        
        for text in test_cases:
            result = nlu_router.classify_intent(text)
            assert result.intent == Intent.HUMANO
            assert result.confidence > 0.0
    
    def test_fallback_intent(self):
        """Test detección de fallback para textos no reconocidos."""
        test_cases = [
            "xyz abc 123",
            "",
            "texto completamente irrelevante sin sentido",
        ]
        
        for text in test_cases:
            result = nlu_router.classify_intent(text)
            assert result.intent == Intent.FALLBACK
    
    def test_entity_extraction_party_size(self):
        """Test extracción de entidad party_size."""
        test_cases = [
            ("mesa para 4 personas", 4),
            ("somos 6 comensales", 6),
            ("para 2", 2),
        ]
        
        for text, expected_size in test_cases:
            result = nlu_router.classify_intent(text)
            assert "party_size" in result.entities
            assert result.entities["party_size"] == expected_size
    
    def test_entity_extraction_time(self):
        """Test extracción de entidad time."""
        test_cases = [
            ("a las 20:30", "20:30"),
            ("mañana a las 21:00", "21:00"),
            ("19:30", "19:30"),
        ]
        
        for text, expected_time in test_cases:
            result = nlu_router.classify_intent(text)
            if "time" in result.entities:
                assert expected_time in result.entities["time"]
    
    def test_entity_extraction_area(self):
        """Test extracción de entidad area."""
        test_cases = [
            ("mesa en terraza", "terraza"),
            ("en el salón privado", "salon_privado"),
            ("en la barra", "barra"),
        ]
        
        for text, expected_area in test_cases:
            result = nlu_router.classify_intent(text)
            if "area" in result.entities:
                assert result.entities["area"] == expected_area


if __name__ == "__main__":
    pytest.main([__file__, "-v"])