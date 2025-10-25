package com.iot.pipeline.producer;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import com.iot.pipeline.model.SensorData;
import org.apache.pulsar.client.api.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.time.Instant;
import java.util.Random;
import java.util.concurrent.TimeUnit;

/**
 * High-throughput IoT Data Producer for benchmark.sensors_local
 * Generates realistic sensor data matching ClickHouse schema
 */
public class IoTDataProducer {
    private static final Logger logger = LoggerFactory.getLogger(IoTDataProducer.class);
    private static final ObjectMapper mapper = new ObjectMapper().registerModule(new JavaTimeModule());
    private static final Random random = new Random();
    
    // Device types (20 types as per schema)
    private static final String[] DEVICE_TYPES = {
        "temperature_sensor", "humidity_sensor", "pressure_sensor", "motion_sensor",
        "light_sensor", "co2_sensor", "noise_sensor", "multisensor",
        "smart_thermostat", "air_quality", "water_quality", "soil_moisture",
        "wind_speed", "rain_gauge", "uv_sensor", "vibration_sensor",
        "proximity_sensor", "gas_detector", "smoke_detector", "door_sensor"
    };
    
    // Configuration
    private static final int NUM_DEVICES = 100000;      // 100K devices
    private static final int NUM_CUSTOMERS = 10000;     // 10K customers
    private static final int NUM_SITES = 1000;          // 1K sites
    
    // Message rate control
    private static int messagesPerSecond = 1000;  // Can be overridden by env var
    private static long totalMessages = 0;
    private static long startTime = System.currentTimeMillis();
    
    public static void main(String[] args) throws Exception {
        String pulsarUrl = System.getenv().getOrDefault("PULSAR_URL", "pulsar://localhost:6650");
        String topicName = System.getenv().getOrDefault("PULSAR_TOPIC", "persistent://public/default/iot-sensor-data");
        messagesPerSecond = Integer.parseInt(System.getenv().getOrDefault("MESSAGES_PER_SECOND", "1000"));
        
        logger.info("=".repeat(80));
        logger.info("IoT Data Producer Starting");
        logger.info("Pulsar URL: {}", pulsarUrl);
        logger.info("Topic: {}", topicName);
        logger.info("Target Rate: {} msg/sec", messagesPerSecond);
        logger.info("Device Pool: {} devices, {} customers, {} sites", NUM_DEVICES, NUM_CUSTOMERS, NUM_SITES);
        logger.info("=".repeat(80));
        
        PulsarClient client = PulsarClient.builder()
                .serviceUrl(pulsarUrl)
                .build();
        
        Producer<byte[]> producer = client.newProducer()
                .topic(topicName)
                .compressionType(CompressionType.LZ4)
                .batchingMaxPublishDelay(10, TimeUnit.MILLISECONDS)
                .batchingMaxMessages(100)
                .sendTimeout(30, TimeUnit.SECONDS)
                .blockIfQueueFull(true)
                .maxPendingMessages(10000)
                .create();
        
        logger.info("Producer connected successfully!");
        
        // Start stats reporter thread
        Thread statsThread = new Thread(() -> printStats());
        statsThread.setDaemon(true);
        statsThread.start();
        
        // Calculate sleep time between messages to achieve target rate
        long sleepNanos = 1_000_000_000L / messagesPerSecond;
        
        while (true) {
            long batchStart = System.nanoTime();
            
            try {
                SensorData sensorData = generateSensorData();
                String jsonData = mapper.writeValueAsString(sensorData);
                
                producer.newMessage()
                        .key(sensorData.getDeviceId())
                        .value(jsonData.getBytes())
                        .property("device_type", sensorData.getDeviceType())
                        .property("customer_id", sensorData.getCustomerId())
                        .sendAsync();
                
                totalMessages++;
                
                // Rate limiting
                long elapsed = System.nanoTime() - batchStart;
                if (elapsed < sleepNanos) {
                    long sleepMs = (sleepNanos - elapsed) / 1_000_000;
                    if (sleepMs > 0) {
                        Thread.sleep(sleepMs);
                    }
                }
                
            } catch (Exception e) {
                logger.error("Error publishing message", e);
                Thread.sleep(1000);  // Back off on error
            }
        }
    }
    
    private static void printStats() {
        while (true) {
            try {
                Thread.sleep(10000);  // Print every 10 seconds
                long elapsed = (System.currentTimeMillis() - startTime) / 1000;
                long rate = totalMessages / Math.max(1, elapsed);
                logger.info("Stats: {} messages sent | {} msg/sec | {} total seconds", 
                           totalMessages, rate, elapsed);
            } catch (InterruptedException e) {
                break;
            }
        }
    }
    
    private static SensorData generateSensorData() {
        SensorData data = new SensorData();
        
        // Device identifiers
        int deviceNum = random.nextInt(NUM_DEVICES);
        int customerNum = random.nextInt(NUM_CUSTOMERS);
        int siteNum = random.nextInt(NUM_SITES);
        
        data.setDeviceId(String.format("dev-%07d", deviceNum));
        data.setDeviceType(DEVICE_TYPES[random.nextInt(DEVICE_TYPES.length)]);
        data.setCustomerId(String.format("cust-%06d", customerNum));
        data.setSiteId(String.format("site-%05d", siteNum));
        
        // Location data (random locations across US)
        data.setLatitude(25.0 + random.nextDouble() * 24.0);  // 25-49 degrees (US mainland)
        data.setLongitude(-125.0 + random.nextDouble() * 58.0);  // -125 to -67 (US mainland)
        data.setAltitude((float)(random.nextDouble() * 3000));  // 0-3000m
        
        // Timestamp
        data.setTime(Instant.now());
        
        // Sensor readings (realistic ranges)
        data.setTemperature(10 + (float)(random.nextDouble() * 30));  // 10-40°C
        data.setHumidity(20 + (float)(random.nextDouble() * 60));     // 20-80%
        data.setPressure(980 + (float)(random.nextDouble() * 50));    // 980-1030 hPa
        data.setCo2Level(400 + (float)(random.nextDouble() * 1600));  // 400-2000 ppm
        data.setNoiseLevel(30 + (float)(random.nextDouble() * 60));   // 30-90 dB
        data.setLightLevel((float)(random.nextDouble() * 1000));      // 0-1000 lux
        data.setMotionDetected(random.nextInt(10) < 2 ? 1 : 0);      // 20% motion detected
        
        // Device metrics
        data.setBatteryLevel(20 + (float)(random.nextDouble() * 80));      // 20-100%
        data.setSignalStrength(-90 + (float)(random.nextDouble() * 50));   // -90 to -40 dBm
        data.setMemoryUsage(10 + (float)(random.nextDouble() * 85));       // 10-95%
        data.setCpuUsage((float)(random.nextDouble() * 100));              // 0-100%
        
        // Status (1=online, 2=offline, 3=maintenance, 4=error)
        // 85% online, 5% offline, 5% maintenance, 5% error
        int statusRoll = random.nextInt(100);
        if (statusRoll < 85) {
            data.setStatus(1);  // online
            data.setErrorCount(0);
        } else if (statusRoll < 90) {
            data.setStatus(2);  // offline
            data.setErrorCount(random.nextInt(5));
        } else if (statusRoll < 95) {
            data.setStatus(3);  // maintenance
            data.setErrorCount(0);
        } else {
            data.setStatus(4);  // error
            data.setErrorCount(1 + random.nextInt(20));
        }
        
        // Network metrics (realistic IoT device traffic)
        long basePackets = random.nextInt(10000);
        data.setPacketsSent(basePackets + random.nextInt(1000));
        data.setPacketsReceived(basePackets + random.nextInt(1000));
        data.setBytesSent(data.getPacketsSent() * (200 + random.nextInt(1000)));  // 200-1200 bytes/packet
        data.setBytesReceived(data.getPacketsReceived() * (200 + random.nextInt(1000)));
        
        return data;
    }
}

