#!/usr/bin/env python3
"""
Simple IoT Consumer to read messages from pulsar-sensor-perf producer
"""

import pulsar
import json
import time
from datetime import datetime

def main():
    pulsar_url = 'pulsar://localhost:6650'
    topic = 'persistent://public/default/iot-sensor-data2'
    
    print(f"🔌 Connecting to Pulsar at {pulsar_url}")
    client = pulsar.Client(pulsar_url)
    
    # Use completely new subscription name to get fresh messages
    subscription_name = f'fresh-consumer-{int(time.time() * 1000)}'
    consumer = client.subscribe(
        topic,
        subscription_name=subscription_name,
        initial_position=pulsar.InitialPosition.Latest
    )
    
    print(f"📡 Subscribed to topic: {topic}")
    print(f"🆔 Subscription: {subscription_name}")
    print("⏳ Waiting for NEW messages...")
    print("=" * 60)
    
    message_count = 0
    
    try:
        while True:
            try:
                msg = consumer.receive(timeout_millis=5000)
                data = json.loads(msg.data().decode('utf-8'))
                message_count += 1
                
                print(f"\n📨 Message #{message_count} - {datetime.now().strftime('%H:%M:%S')}")
                print(f"   🔢 Device ID: {data.get('deviceId', 'N/A')}")
                print(f"   📱 Device Type: {data.get('deviceType', 'N/A')}")
                print(f"   🌡️  Temperature: {data.get('temperature', 'N/A'):.1f}°C")
                print(f"   💧 Humidity: {data.get('humidity', 'N/A'):.1f}%")
                print(f"   🔋 Battery: {data.get('batteryLevel', 'N/A'):.1f}%")
                print(f"   🏢 Customer: {data.get('customerId', 'N/A')}")
                print(f"   🏭 Site: {data.get('siteId', 'N/A')}")
                
                # Check for alerts
                alerts = []
                if data.get('temperature', 0) > 35:
                    alerts.append('HIGH_TEMP')
                if data.get('humidity', 0) > 80:
                    alerts.append('HIGH_HUMIDITY')
                if data.get('batteryLevel', 100) < 20:
                    alerts.append('LOW_BATTERY')
                
                if alerts:
                    print(f"   🚨 ALERTS: {', '.join(alerts)}")
                else:
                    print(f"   ✅ Normal readings")
                
                consumer.acknowledge(msg)
                
            except Exception as e:
                if "Timeout" not in str(e):
                    print(f"❌ Error receiving message: {e}")
                    
    except KeyboardInterrupt:
        print(f"\n🛑 Stopping consumer after processing {message_count} messages")
        
    finally:
        consumer.close()
        client.close()
        print("🔌 Disconnected from Pulsar")

if __name__ == "__main__":
    main()
