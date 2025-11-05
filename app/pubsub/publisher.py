"""
Google Cloud Pub/Sub Publisher para eventos WhatsApp.

Publica eventos de forma async a Pub/Sub:
- publish_incoming_event() - Mensajes entrantes del webhook (rápido, <50ms)
- publish_internal_event() - Cambios de estado del sistema

De esta forma el webhook devuelve inmediatamente y el procesamiento
se realiza async en workers conscritos al topic.
"""

import logging
import json
import os
from typing import Dict, Any, Optional
from google.cloud import pubsub_v1

logger = logging.getLogger(__name__)

# Configuración
GCP_PROJECT = os.getenv("GCP_PROJECT", "your-project-id")
PUBSUB_TOPIC_IN = os.getenv("PUBSUB_TOPIC_IN", "wa-incoming")
PUBSUB_TOPIC_INTERNAL = os.getenv("PUBSUB_TOPIC_INTERNAL", "wa-internal-events")

# Singleton PublisherClient (thread-safe)
_publisher: Optional[pubsub_v1.PublisherClient] = None


def get_publisher() -> pubsub_v1.PublisherClient:
    """
    Obtiene o crea el cliente de Pub/Sub.
    
    Usa singleton para reutilizar conexión.
    """
    global _publisher
    if _publisher is None:
        _publisher = pubsub_v1.PublisherClient()
    return _publisher


async def publish_incoming_event(tenant_key: str, payload: Dict[str, Any]) -> str:
    """
    Publica evento de mensaje entrante a Pub/Sub.
    
    Devuelve inmediatamente (<50ms) sin esperar procesamiento.
    El procesamiento se realiza async en worker que consume la subscription.
    
    Args:
        tenant_key: ID del tenant
        payload: Datos del evento (from, text, message_id, etc.)
    
    Returns:
        Message ID de Pub/Sub
    
    Raises:
        Exception: Si falla la publicación
    """
    try:
        publisher = get_publisher()
        topic_path = publisher.topic_path(GCP_PROJECT, PUBSUB_TOPIC_IN)
        
        # Envelope: incluir tenant_key para identificar origen
        envelope = {
            "tenant_key": tenant_key,
            "data": payload,
            "message_id": payload.get("message_id", ""),
            "type": "incoming_event"
        }
        
        # Serializar a JSON + UTF-8
        message_json = json.dumps(envelope, ensure_ascii=False)
        message_bytes = message_json.encode("utf-8")
        
        # Atributos para filtering/debugging
        attributes = {
            "tenant_key": tenant_key,
            "event_type": "incoming",
            "message_id": str(payload.get("message_id", ""))
        }
        
        # Publicar de forma async
        future = publisher.publish(
            topic_path,
            message_bytes,
            **attributes
        )
        
        # Esperar confirmación (máximo 5s)
        message_id = future.result(timeout=5.0)
        logger.info(f"✅ Evento publicado a Pub/Sub: {message_id} (tenant: {tenant_key})")
        return message_id
        
    except Exception as e:
        logger.error(f"❌ Error publicando a Pub/Sub: {e}")
        raise


async def publish_internal_event(
    tenant_key: str,
    event_type: str,
    payload: Dict[str, Any]
) -> str:
    """
    Publica evento interno (cambios de estado del sistema).
    
    Usado para eventos generados por el worker o el orchestrator.
    Por ejemplo: conversation_assigned, sla_breached, etc.
    
    Args:
        tenant_key: ID del tenant
        event_type: Tipo de evento (e.g., "conversation_assigned")
        payload: Datos del evento
    
    Returns:
        Message ID de Pub/Sub
    """
    try:
        publisher = get_publisher()
        topic_path = publisher.topic_path(GCP_PROJECT, PUBSUB_TOPIC_INTERNAL)
        
        # Envelope
        envelope = {
            "tenant_key": tenant_key,
            "event_type": event_type,
            "data": payload
        }
        
        message_json = json.dumps(envelope, ensure_ascii=False)
        message_bytes = message_json.encode("utf-8")
        
        attributes = {
            "tenant_key": tenant_key,
            "event_type": event_type
        }
        
        future = publisher.publish(
            topic_path,
            message_bytes,
            **attributes
        )
        
        message_id = future.result(timeout=5.0)
        logger.info(f"✅ Evento interno publicado: {event_type} (tenant: {tenant_key})")
        return message_id
        
    except Exception as e:
        logger.error(f"❌ Error publicando evento interno: {e}")
        raise


def create_topic_if_not_exists(topic_name: str) -> str:
    """
    Crea topic en Pub/Sub si no existe.
    
    Usar durante setup/initialization.
    
    Args:
        topic_name: Nombre del topic (e.g., "wa-incoming")
    
    Returns:
        Topic path
    """
    try:
        publisher = get_publisher()
        topic_path = publisher.topic_path(GCP_PROJECT, topic_name)
        
        # Intentar crear
        publisher.create_topic(request={"name": topic_path})
        logger.info(f"✅ Topic creado: {topic_path}")
        
    except Exception as e:
        if "already exists" in str(e):
            logger.info(f"ℹ️ Topic ya existe: {topic_path}")
        else:
            logger.error(f"❌ Error creando topic: {e}")
            raise
    
    return topic_path


def create_subscription_if_not_exists(
    topic_name: str,
    subscription_name: str,
    push_endpoint: Optional[str] = None
) -> str:
    """
    Crea subscription en Pub/Sub si no existe.
    
    Args:
        topic_name: Nombre del topic (e.g., "wa-incoming")
        subscription_name: Nombre de la suscripción
        push_endpoint: URL del endpoint push (e.g., "https://worker/ps/consume")
    
    Returns:
        Subscription path
    """
    try:
        publisher = get_publisher()
        subscriber = pubsub_v1.SubscriberClient()
        
        topic_path = publisher.topic_path(GCP_PROJECT, topic_name)
        subscription_path = subscriber.subscription_path(GCP_PROJECT, subscription_name)
        
        # Crear suscripción
        if push_endpoint:
            push_config = pubsub_v1.types.PushConfig(push_endpoint=push_endpoint)
        else:
            push_config = None
        
        subscriber.create_subscription(
            request={
                "name": subscription_path,
                "topic": topic_path,
                "push_config": push_config
            }
        )
        logger.info(f"✅ Subscription creada: {subscription_path}")
        
    except Exception as e:
        if "already exists" in str(e):
            logger.info(f"ℹ️ Subscription ya existe: {subscription_path}")
        else:
            logger.error(f"❌ Error creando subscription: {e}")
            raise
    
    return subscription_path
