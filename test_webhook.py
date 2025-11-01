import requests
import json

# Mensaje de prueba simple
test_message = {
    "entry": [{
        "changes": [{
            "value": {
                "messages": [{
                    "from": "5491134567890",
                    "text": {"body": "Hola"},
                    "id": "test123",
                    "timestamp": "1234567890"
                }],
                "metadata": {"phone_number_id": "test"}
            }
        }]
    }]
}

try:
    response = requests.post(
        'http://localhost:8000/webhook', 
        json=test_message,
        timeout=5
    )
    print(f"Status: {response.status_code}")
    print(f"Response: {response.text}")
except Exception as e:
    print(f"Error: {e}")