package com.iot.pipeline.producer;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.iot.pipeline.model.SensorData;
import org.apache.pulsar.client.api.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.Random;
import java.util.concurrent.TimeUnit;

public class    IoTDataProducer {
    private static final Logger logger = LoggerFactory.getLogger(IoTDataProducer.class);
    private static final ObjectMapper mapper = new ObjectMapper();
    private static final Random random = new Random();
    
    private static final String[] SENSOR_TYPES = {"temperature", "humidity", "pressure", "motion", "light"};
    private static final String[] LOCATIONS = {"warehouse-1", "warehouse-2", "office-1", "factory-floor", "storage-room"};
    private static final String[] STATUSES = {"active", "idle", "warning", "maintenance"};
    private static final String[] MANUFACTURERS = {"SensorCorp", "IoTech", "SmartDevices", "TechSense"};
    
    public static void main(String[] args) throws Exception {
        String pulsarUrl = System.getenv().getOrDefault("PULSAR_URL", "pulsar://localhost:6650");
        String topicName = System.getenv().getOrDefault("PULSAR_TOPIC", "persistent://public/default/iot-sensor-data");
        
        PulsarClient client = PulsarClient.builder()
                .serviceUrl(pulsarUrl)
                .build();
        
        Producer<byte[]> producer = client.newProducer()
                .topic(topicName)
                .compressionType(CompressionType.LZ4)
                .batchingMaxPublishDelay(10, TimeUnit.MILLISECONDS)
                .sendTimeout(10, TimeUnit.SECONDS)
                .blockIfQueueFull(true)
                .create();
        
        logger.info("Starting IoT Data Producer - Publishing to topic: {}", topicName);
        
        int messageCount = 0;
        while (true) {
            try {
                SensorData sensorData = generateSensorData();
                String jsonData = mapper.writeValueAsString(sensorData);
                
                producer.newMessage()
                        .key(sensorData.getSensorId())
                        .value(jsonData.getBytes())
                        .property("sensorType", sensorData.getSensorType())
                        .property("location", sensorData.getLocation())
                        .send();
                
                messageCount++;
                if (messageCount % 100 == 0) {
                    logger.info("Published {} messages", messageCount);
                }
                
                Thread.sleep(random.nextInt(1000) + 500);
                
            } catch (Exception e) {
                logger.error("Error publishing message", e);
            }
        }
    }
    
    private static SensorData generateSensorData() {
        String sensorId = "sensor-" + (random.nextInt(100) + 1);
        String sensorType = SENSOR_TYPES[random.nextInt(SENSOR_TYPES.length)];
        String location = LOCATIONS[random.nextInt(LOCATIONS.length)];
        String status = STATUSES[random.nextInt(STATUSES.length)];
        
        double temperature = 20 + random.nextDouble() * 15;
        double humidity = 30 + random.nextDouble() * 40;
        double pressure = 1000 + random.nextDouble() * 50;
        double batteryLevel = 20 + random.nextDouble() * 80;
        
        SensorData.MetaData metadata = new SensorData.MetaData(
                MANUFACTURERS[random.nextInt(MANUFACTURERS.length)],
                "Model-" + (random.nextInt(10) + 1),
                "v" + (1 + random.nextInt(3)) + "." + random.nextInt(10),
                37.7749 + random.nextDouble() * 0.1,
                -122.4194 + random.nextDouble() * 0.1
        );
        
        return new SensorData(sensorId, sensorType, location, 
                temperature, humidity, pressure, batteryLevel, status, metadata);
    }
}