"""
Pruebas unitarias para el sistema RAG.

Verifica la ingesta de documentos, indexación y búsqueda.
"""

import pytest
import tempfile
import shutil
from pathlib import Path
from wa_orchestrator.rag.ingest import DocumentProcessor
from wa_orchestrator.rag.retriever import DocumentRetriever


class TestRAGSystem:
    """Pruebas para el sistema RAG completo."""
    
    @pytest.fixture
    def temp_kb_dir(self):
        """Crea directorio temporal con documentos de prueba."""
        temp_dir = Path(tempfile.mkdtemp())
        
        # Crear documento de menú de prueba
        menu_content = """# Menú de Prueba

## Entradas
- Empanadas de carne: $1500
- Provoleta: $1200

## Platos Principales
- Bife de chorizo: $4500
- Salmón grillado: $3800

## Postres
- Tiramisú: $800
- Flan: $600
"""
        
        # Crear documento de políticas de prueba
        policies_content = """# Políticas de Reservas

## Cancelaciones
Las reservas pueden cancelarse hasta 2 horas antes.

## Horarios
Abierto de lunes a domingo de 19:00 a 24:00.

## Grupo grandes
Grupos de más de 8 personas requieren anticipo.
"""
        
        (temp_dir / "menu_test.md").write_text(menu_content, encoding='utf-8')
        (temp_dir / "policies_test.md").write_text(policies_content, encoding='utf-8')
        
        yield temp_dir
        
        # Cleanup
        shutil.rmtree(temp_dir)
    
    @pytest.fixture
    def temp_model_file(self):
        """Crea archivo temporal para modelo."""
        temp_file = tempfile.NamedTemporaryFile(suffix='.joblib', delete=False)
        temp_file.close()
        
        yield temp_file.name
        
        # Cleanup
        Path(temp_file.name).unlink(missing_ok=True)
    
    def test_document_processing(self, temp_kb_dir):
        """Test procesamiento de documentos markdown."""
        processor = DocumentProcessor()
        processor.load_documents(temp_kb_dir)
        
        # Verificar que se cargaron documentos
        assert len(processor.documents) > 0
        
        # Verificar que se crearon secciones
        section_titles = [doc['title'] for doc in processor.documents]
        assert any('Entradas' in title for title in section_titles)
        assert any('Platos Principales' in title for title in section_titles)
        assert any('Cancelaciones' in title for title in section_titles)
    
    def test_index_building(self, temp_kb_dir, temp_model_file):
        """Test construcción de índice TF-IDF."""
        processor = DocumentProcessor()
        processor.load_documents(temp_kb_dir)
        processor.build_index()
        
        # Verificar que se creó el índice
        assert processor.vectorizer is not None
        assert processor.tfidf_matrix is not None
        assert processor.tfidf_matrix.shape[0] > 0  # Documentos
        assert processor.tfidf_matrix.shape[1] > 0  # Características
        
        # Test guardar modelo
        processor.save_index(temp_model_file)
        assert Path(temp_model_file).exists()
    
    def test_document_retrieval(self, temp_kb_dir, temp_model_file):
        """Test búsqueda de documentos."""
        # Crear y guardar índice
        processor = DocumentProcessor()
        processor.load_documents(temp_kb_dir)
        processor.build_index()
        processor.save_index(temp_model_file)
        
        # Test retrieval
        retriever = DocumentRetriever(temp_model_file)
        assert retriever.load_index()
        
        # Test búsquedas
        results = retriever.retrieve("precios empanadas", top_k=2)
        assert len(results) > 0
        assert results[0]['similarity_score'] > 0
        
        results = retriever.retrieve("cancelación reserva", top_k=2)
        assert len(results) > 0
        
        results = retriever.retrieve("horarios atención", top_k=2)
        assert len(results) > 0
    
    def test_retrieval_by_category(self, temp_kb_dir, temp_model_file):
        """Test búsqueda por categoría."""
        # Crear índice
        processor = DocumentProcessor()
        processor.load_documents(temp_kb_dir)
        processor.build_index()
        processor.save_index(temp_model_file)
        
        # Test retrieval por categoría
        retriever = DocumentRetriever(temp_model_file)
        retriever.load_index()
        
        menu_docs = retriever.retrieve_by_category("menu", top_k=3)
        assert len(menu_docs) > 0
        
        policies_docs = retriever.retrieve_by_category("policies", top_k=3)
        assert len(policies_docs) > 0
    
    def test_response_formatting(self, temp_kb_dir, temp_model_file):
        """Test formateo de respuestas."""
        # Crear índice
        processor = DocumentProcessor()
        processor.load_documents(temp_kb_dir)
        processor.build_index()
        processor.save_index(temp_model_file)
        
        # Test formateo
        retriever = DocumentRetriever(temp_model_file)
        retriever.load_index()
        
        results = retriever.retrieve("precios", top_k=2)
        response = retriever.format_response("precios", results, max_chars=500)
        
        assert len(response) > 0
        assert len(response) <= 600  # Margen para formateo
        assert "**" in response  # Formateo markdown
    
    def test_empty_query(self, temp_kb_dir, temp_model_file):
        """Test manejo de consultas vacías."""
        processor = DocumentProcessor()
        processor.load_documents(temp_kb_dir)
        processor.build_index()
        processor.save_index(temp_model_file)
        
        retriever = DocumentRetriever(temp_model_file)
        retriever.load_index()
        
        # Consulta vacía
        results = retriever.retrieve("", top_k=2)
        assert len(results) == 0
        
        # Consulta sin resultados relevantes
        results = retriever.retrieve("xyz123 sin sentido", top_k=2, min_similarity=0.5)
        assert len(results) == 0
    
    def test_index_stats(self, temp_kb_dir, temp_model_file):
        """Test estadísticas del índice."""
        processor = DocumentProcessor()
        processor.load_documents(temp_kb_dir)
        processor.build_index()
        processor.save_index(temp_model_file)
        
        retriever = DocumentRetriever(temp_model_file)
        retriever.load_index()
        
        stats = retriever.get_index_stats()
        
        assert stats['total_documents'] > 0
        assert stats['vocabulary_size'] > 0
        assert stats['files_processed'] > 0
        assert 'file_stats' in stats
        assert stats['is_loaded'] == True


if __name__ == "__main__":
    pytest.main([__file__, "-v"])