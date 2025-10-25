package com.iot.pipeline.flink;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.api.common.serialization.SimpleStringSchema;
import org.apache.flink.configuration.Configuration;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.functions.sink.RichSinkFunction;
import org.apache.flink.streaming.api.functions.source.RichSourceFunction;
import org.apache.pulsar.client.api.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.time.Duration;
import java.util.concurrent.TimeUnit;

public class SimpleFlinkConsumer {
    private static final Logger logger = LoggerFactory.getLogger(SimpleFlinkConsumer.class);
    private static final ObjectMapper mapper = new ObjectMapper();
    
    public static void main(String[] args) throws Exception {
        String pulsarUrl = System.getenv().getOrDefault("PULSAR_URL", "pulsar://localhost:6650");
        String topicName = System.getenv().getOrDefault("PULSAR_TOPIC", "persistent://public/default/iot-sensor-data");
        String clickhouseUrl = System.getenv().getOrDefault("CLICKHOUSE_URL", "http://localhost:8123");
        
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        env.setParallelism(1);
        
        System.out.println("Starting Flink IoT Consumer...");
        System.out.println("Pulsar URL: " + pulsarUrl);
        System.out.println("Topic: " + topicName);
        System.out.println("ClickHouse URL: " + clickhouseUrl);
        
        // Create Pulsar source
        DataStream<String> pulsarStream = env.addSource(
                new PulsarSource(pulsarUrl, topicName),
                "Pulsar IoT Source"
        );
        
        // Process and sink to ClickHouse
        pulsarStream
                .map(jsonStr -> {
                    try {
                        JsonNode json = mapper.readTree(jsonStr);
                        System.out.println("Processing: " + json.get("sensorId").asText());
                        return jsonStr;
                    } catch (Exception e) {
                        System.err.println("Error parsing JSON: " + e.getMessage());
                        return null;
                    }
                })
                .filter(data -> data != null)
                .addSink(new ClickHouseSink(clickhouseUrl));
        
        System.out.println("Flink job started!");
        env.execute("Simple IoT Data Pipeline");
    }
    
    public static class PulsarSource extends RichSourceFunction<String> {
        private volatile boolean isRunning = true;
        private final String pulsarUrl;
        private final String topicName;
        private PulsarClient client;
        private Consumer<byte[]> consumer;
        
        public PulsarSource(String pulsarUrl, String topicName) {
            this.pulsarUrl = pulsarUrl;
            this.topicName = topicName;
        }
        
        @Override
        public void open(Configuration parameters) throws Exception {
            super.open(parameters);
            
            System.out.println("Opening Pulsar connection...");
            client = PulsarClient.builder()
                    .serviceUrl(pulsarUrl)
                    .build();
            
            consumer = client.newConsumer()
                    .topic(topicName)
                    .subscriptionName("flink-simple-consumer")
                    .subscriptionType(SubscriptionType.Shared)
                    .ackTimeout(30, TimeUnit.SECONDS)
                    .subscribe();
            
            System.out.println("Connected to Pulsar successfully!");
        }
        
        @Override
        public void run(SourceContext<String> ctx) throws Exception {
            System.out.println("Starting to consume messages...");
            while (isRunning) {
                try {
                    Message<byte[]> message = consumer.receive(5, TimeUnit.SECONDS);
                    if (message != null) {
                        String jsonData = new String(message.getData());
                        ctx.collect(jsonData);
                        consumer.acknowledge(message);
                    }
                } catch (Exception e) {
                    if (isRunning) {
                        System.err.println("Error receiving message: " + e.getMessage());
                    }
                }
            }
        }
        
        @Override
        public void cancel() {
            isRunning = false;
        }
        
        @Override
        public void close() throws Exception {
            System.out.println("Closing Pulsar connection...");
            if (consumer != null) {
                consumer.close();
            }
            if (client != null) {
                client.close();
            }
            super.close();
        }
    }
    
    public static class ClickHouseSink extends RichSinkFunction<String> {
        private final String clickhouseUrl;
        
        public ClickHouseSink(String clickhouseUrl) {
            this.clickhouseUrl = clickhouseUrl;
        }
        
        @Override
        public void invoke(String jsonData, Context context) throws Exception {
            try {
                JsonNode json = mapper.readTree(jsonData);
                
                // Insert raw sensor data
                String sensorId = json.get("sensorId").asText();
                String sensorType = json.get("sensorType").asText();
                String location = json.get("location").asText();
                double temperature = json.get("temperature").asDouble();
                double humidity = json.get("humidity").asDouble();
                double pressure = json.get("pressure").asDouble();
                double batteryLevel = json.get("batteryLevel").asDouble();
                String status = json.get("status").asText();
                
                JsonNode metadata = json.get("metadata");
                String manufacturer = metadata != null ? metadata.get("manufacturer").asText() : "";
                String model = metadata != null ? metadata.get("model").asText() : "";
                String firmwareVersion = metadata != null ? metadata.get("firmwareVersion").asText() : "";
                double latitude = metadata != null ? metadata.get("latitude").asDouble() : 0.0;
                double longitude = metadata != null ? metadata.get("longitude").asDouble() : 0.0;
                
                String insertQuery = String.format(
                    "INSERT INTO iot.sensor_raw_data VALUES ('%s', '%s', '%s', %.2f, %.2f, %.2f, %.2f, '%s', now(), '%s', '%s', '%s', %.6f, %.6f)",
                    sensorId, sensorType, location, temperature, humidity, pressure, batteryLevel, status,
                    manufacturer, model, firmwareVersion, latitude, longitude
                );
                
                sendToClickHouse(insertQuery);
                
                // Check for alerts and insert if needed
                String alertType = "NORMAL";
                if (temperature > 35) {
                    alertType = "HIGH_TEMPERATURE";
                } else if (humidity > 80) {
                    alertType = "HIGH_HUMIDITY";
                } else if (batteryLevel < 20) {
                    alertType = "LOW_BATTERY";
                }
                
                if (!"NORMAL".equals(alertType)) {
                    String alertQuery = String.format(
                        "INSERT INTO iot.sensor_alerts VALUES ('%s', '%s', '%s', %.2f, %.2f, %.2f, '%s', now())",
                        sensorId, sensorType, location, temperature, humidity, batteryLevel, alertType
                    );
                    sendToClickHouse(alertQuery);
                    System.out.println("🚨 ALERT: " + sensorId + " - " + alertType);
                }
                
                System.out.println("✅ Processed: " + sensorId + " (T:" + String.format("%.1f", temperature) + "°C)");
                
            } catch (Exception e) {
                System.err.println("Error processing data: " + e.getMessage());
            }
        }
        
        private void sendToClickHouse(String query) throws Exception {
            URL url = new URL(clickhouseUrl + "/");
            HttpURLConnection conn = (HttpURLConnection) url.openConnection();
            conn.setRequestMethod("POST");
            conn.setDoOutput(true);
            conn.setRequestProperty("Content-Type", "text/plain");
            
            try (OutputStream os = conn.getOutputStream()) {
                os.write(query.getBytes());
                os.flush();
            }
            
            int responseCode = conn.getResponseCode();
            if (responseCode != 200) {
                try (BufferedReader br = new BufferedReader(new InputStreamReader(conn.getErrorStream()))) {
                    String line;
                    StringBuilder response = new StringBuilder();
                    while ((line = br.readLine()) != null) {
                        response.append(line);
                    }
                    throw new Exception("ClickHouse error: " + responseCode + " - " + response.toString());
                }
            }
        }
    }
}