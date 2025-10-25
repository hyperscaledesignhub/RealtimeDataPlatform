#!/usr/bin/env python3
"""
Simple Pulsar consumer to verify data flow and simulate Flink processing
"""

import json
import time
import sys
from datetime import datetime

try:
    import pulsar
except ImportError:
    print("Installing pulsar-client...")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "pulsar-client"])
    import pulsar

def process_sensor_data(data):
    """Simulate Flink processing logic"""
    try:
        sensor_data = json.loads(data.decode('utf-8'))
        
        # Simulate alert detection
        alerts = []
        temp = sensor_data.get('temperature', 0)
        humidity = sensor_data.get('humidity', 0)
        battery = sensor_data.get('batteryLevel', 0)
        
        if temp > 35:
            alerts.append('HIGH_TEMPERATURE')
        if humidity > 80:
            alerts.append('HIGH_HUMIDITY')  
        if battery < 20:
            alerts.append('LOW_BATTERY')
            
        return {
            'sensor_id': sensor_data.get('sensorId'),
            'sensor_type': sensor_data.get('sensorType'),
            'location': sensor_data.get('location'),
            'temperature': temp,
            'humidity': humidity,
            'battery_level': battery,
            'alerts': alerts,
            'processed_time': datetime.now().isoformat()
        }
    except Exception as e:
        print(f"Error processing data: {e}")
        return None

def main():
    pulsar_url = 'pulsar://localhost:6650'
    topic = 'persistent://public/default/iot-sensor-data'
    
    print(f"Connecting to Pulsar at {pulsar_url}")
    client = pulsar.Client(pulsar_url)
    
    consumer = client.subscribe(
        topic,
        subscription_name='python-test-consumer',
        consumer_type=pulsar.ConsumerType.Shared
    )
    
    print(f"Subscribed to topic: {topic}")
    print("Waiting for messages...")
    
    message_count = 0
    
    try:
        while True:
            try:
                msg = consumer.receive(timeout_millis=5000)
                
                # Process the message
                processed_data = process_sensor_data(msg.data())
                
                if processed_data:
                    message_count += 1
                    print(f"\nMessage {message_count}:")
                    print(f"  Sensor: {processed_data['sensor_id']}")
                    print(f"  Type: {processed_data['sensor_type']}")
                    print(f"  Location: {processed_data['location']}")
                    print(f"  Temperature: {processed_data['temperature']:.1f}°C")
                    print(f"  Humidity: {processed_data['humidity']:.1f}%")
                    print(f"  Battery: {processed_data['battery_level']:.1f}%")
                    
                    if processed_data['alerts']:
                        print(f"  🚨 ALERTS: {', '.join(processed_data['alerts'])}")
                    else:
                        print(f"  ✅ Normal readings")
                
                consumer.acknowledge(msg)
                
            except Exception as e:
                if "Timeout" not in str(e):
                    print(f"Error receiving message: {e}")
                    
    except KeyboardInterrupt:
        print(f"\nStopping consumer after processing {message_count} messages")
        
    finally:
        consumer.close()
        client.close()

if __name__ == "__main__":
    main()