"""
Script simple para probar el sistema de reservas.
"""
import sys
from pathlib import Path

# Agregar el directorio raíz al path
sys.path.append(str(Path(__file__).parent))

from wa_orchestrator.nlu.router import nlu_router
from wa_orchestrator.rag.retriever import document_retriever

def test_nlu():
    """Probar el sistema NLU."""
    print("=== Prueba NLU ===")
    
    test_messages = [
        "Hola, quiero hacer una reserva",
        "¿Cuál es el menú de hoy?",
        "Quiero cancelar mi reserva",
        "¿A qué hora abren?",
        "Necesito una mesa para 4 personas mañana a las 20:00"
    ]
    
    for message in test_messages:
        result = nlu_router.classify_intent(message)
        print(f"Mensaje: '{message}'")
        print(f"Intent: {result.intent}")
        print(f"Confidence: {result.confidence:.2f}")
        print(f"Entities: {result.entities}")
        print("-" * 50)

def test_rag():
    """Probar el sistema RAG."""
    print("\n=== Prueba RAG ===")
    
    queries = [
        "¿Cuál es el menú?",
        "¿Cuánto cuesta la pasta?",
        "¿Cuáles son los horarios del restaurante?",
        "¿Qué políticas de cancelación tienen?"
    ]
    
    for query in queries:
        # Cargar el índice si no está cargado
        if not document_retriever.is_loaded:
            document_retriever.load_index()
        
        results = document_retriever.retrieve(query, top_k=2)
        print(f"Query: '{query}'")
        for i, doc in enumerate(results, 1):
            print(f"  {i}. {doc['content'][:100]}... (Score: {doc['score']:.3f})")
        print("-" * 50)

if __name__ == "__main__":
    test_nlu()
    test_rag()