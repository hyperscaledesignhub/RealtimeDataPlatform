package com.iot.pipeline.producer;

import org.apache.pulsar.client.api.*;
import java.util.concurrent.TimeUnit;

public class SimpleProducer {
    public static void main(String[] args) throws Exception {
        String pulsarUrl = System.getenv().getOrDefault("PULSAR_URL", "pulsar://localhost:6650");
        String topicName = System.getenv().getOrDefault("PULSAR_TOPIC", "persistent://public/default/iot-sensor-data");
        
        System.out.println("Connecting to Pulsar at: " + pulsarUrl);
        System.out.println("Publishing to topic: " + topicName);
        
        PulsarClient client = PulsarClient.builder()
                .serviceUrl(pulsarUrl)
                .build();
        
        Producer<byte[]> producer = client.newProducer()
                .topic(topicName)
                .create();
        
        System.out.println("Producer created successfully!");
        
        int messageCount = 0;
        while (true) {
            try {
                String message = String.format(
                    "{\"sensorId\":\"sensor-%d\",\"sensorType\":\"temperature\",\"location\":\"test-location\",\"temperature\":%.1f,\"humidity\":%.1f,\"pressure\":%.1f,\"batteryLevel\":%.1f,\"status\":\"active\",\"timestamp\":\"%s\",\"metadata\":{\"manufacturer\":\"TestCorp\",\"model\":\"Test-1\",\"firmwareVersion\":\"v1.0\",\"latitude\":37.7749,\"longitude\":-122.4194}}",
                    (messageCount % 10) + 1,
                    20.0 + Math.random() * 20,
                    40.0 + Math.random() * 40,
                    1000.0 + Math.random() * 50,
                    20.0 + Math.random() * 80,
                    java.time.Instant.now().toString()
                );
                
                producer.send(message.getBytes());
                messageCount++;
                
                if (messageCount % 10 == 0) {
                    System.out.println("Published " + messageCount + " messages");
                }
                
                Thread.sleep(1000); // Send one message per second
                
            } catch (Exception e) {
                System.err.println("Error sending message: " + e.getMessage());
                e.printStackTrace();
            }
        }
    }
}