package com.iot.pipeline.flink;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.configuration.Configuration;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.functions.sink.RichSinkFunction;
import org.apache.flink.streaming.api.functions.source.RichSourceFunction;
import org.apache.pulsar.client.api.*;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.time.Duration;
import java.util.concurrent.TimeUnit;

public class JDBCFlinkConsumer {
    private static final ObjectMapper mapper = new ObjectMapper();
    
    public static void main(String[] args) throws Exception {
        String pulsarUrl = System.getenv().getOrDefault("PULSAR_URL", "pulsar://localhost:6650");
        String topicName = System.getenv().getOrDefault("PULSAR_TOPIC", "persistent://public/default/iot-sensor-data");
        String clickhouseUrl = System.getenv().getOrDefault("CLICKHOUSE_URL", "jdbc:clickhouse://localhost:8123/iot");
        
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        env.setParallelism(1);
        
        System.out.println("Starting JDBC Flink IoT Consumer...");
        System.out.println("Pulsar URL: " + pulsarUrl);
        System.out.println("Topic: " + topicName);
        System.out.println("ClickHouse URL: " + clickhouseUrl);
        
        // Create Pulsar source
        DataStream<String> pulsarStream = env.addSource(
                new PulsarSource(pulsarUrl, topicName),
                "Pulsar IoT Source"
        );
        
        // Process and sink to ClickHouse via JDBC
        pulsarStream
                .map(jsonStr -> {
                    try {
                        JsonNode json = mapper.readTree(jsonStr);
                        System.out.println("Processing: " + json.get("sensorId").asText());
                        return new SensorRecord(json);
                    } catch (Exception e) {
                        System.err.println("Error parsing JSON: " + e.getMessage());
                        return null;
                    }
                })
                .filter(data -> data != null)
                .addSink(new ClickHouseJDBCSink(clickhouseUrl));
        
        System.out.println("JDBC Flink job started!");
        env.execute("JDBC IoT Data Pipeline");
    }
    
    public static class SensorRecord {
        public String sensorId;
        public String sensorType;
        public String location;
        public double temperature;
        public double humidity;
        public double pressure;
        public double batteryLevel;
        public String status;
        public String manufacturer;
        public String model;
        public String firmwareVersion;
        public double latitude;
        public double longitude;
        
        public SensorRecord(JsonNode json) {
            this.sensorId = json.get("sensorId").asText();
            this.sensorType = json.get("sensorType").asText();
            this.location = json.get("location").asText();
            this.temperature = json.get("temperature").asDouble();
            this.humidity = json.get("humidity").asDouble();
            this.pressure = json.get("pressure").asDouble();
            this.batteryLevel = json.get("batteryLevel").asDouble();
            this.status = json.get("status").asText();
            
            JsonNode metadata = json.get("metadata");
            if (metadata != null) {
                this.manufacturer = metadata.get("manufacturer").asText();
                this.model = metadata.get("model").asText();
                this.firmwareVersion = metadata.get("firmwareVersion").asText();
                this.latitude = metadata.get("latitude").asDouble();
                this.longitude = metadata.get("longitude").asDouble();
            } else {
                this.manufacturer = "";
                this.model = "";
                this.firmwareVersion = "";
                this.latitude = 0.0;
                this.longitude = 0.0;
            }
        }
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
            
            System.out.println("Opening Pulsar JDBC connection...");
            client = PulsarClient.builder()
                    .serviceUrl(pulsarUrl)
                    .build();
            
            consumer = client.newConsumer()
                    .topic(topicName)
                    .subscriptionName("flink-jdbc-consumer")
                    .subscriptionType(SubscriptionType.Shared)
                    .ackTimeout(30, TimeUnit.SECONDS)
                    .subscribe();
            
            System.out.println("Connected to Pulsar via JDBC successfully!");
        }
        
        @Override
        public void run(SourceContext<String> ctx) throws Exception {
            System.out.println("Starting to consume messages via JDBC...");
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
            System.out.println("Closing Pulsar JDBC connection...");
            if (consumer != null) {
                consumer.close();
            }
            if (client != null) {
                client.close();
            }
            super.close();
        }
    }
    
    public static class ClickHouseJDBCSink extends RichSinkFunction<SensorRecord> {
        private final String jdbcUrl;
        private Connection connection;
        private PreparedStatement insertRawStatement;
        private PreparedStatement insertAlertStatement;
        
        public ClickHouseJDBCSink(String jdbcUrl) {
            this.jdbcUrl = jdbcUrl;
        }
        
        @Override
        public void open(Configuration parameters) throws Exception {
            super.open(parameters);
            
            System.out.println("Opening JDBC connection to ClickHouse: " + jdbcUrl);
            
            // Load ClickHouse JDBC driver
            Class.forName("com.clickhouse.jdbc.ClickHouseDriver");
            connection = DriverManager.getConnection(jdbcUrl);
            
            // Prepare statements
            insertRawStatement = connection.prepareStatement(
                "INSERT INTO sensor_raw_data (sensor_id, sensor_type, location, temperature, humidity, pressure, battery_level, status, timestamp, manufacturer, model, firmware_version, latitude, longitude) VALUES (?, ?, ?, ?, ?, ?, ?, ?, now(), ?, ?, ?, ?, ?)"
            );
            
            insertAlertStatement = connection.prepareStatement(
                "INSERT INTO sensor_alerts (sensor_id, sensor_type, location, temperature, humidity, battery_level, alert_type, alert_time) VALUES (?, ?, ?, ?, ?, ?, ?, now())"
            );
            
            System.out.println("JDBC connection established successfully!");
        }
        
        @Override
        public void invoke(SensorRecord record, Context context) throws Exception {
            try {
                // Insert raw sensor data
                insertRawStatement.setString(1, record.sensorId);
                insertRawStatement.setString(2, record.sensorType);
                insertRawStatement.setString(3, record.location);
                insertRawStatement.setDouble(4, record.temperature);
                insertRawStatement.setDouble(5, record.humidity);
                insertRawStatement.setDouble(6, record.pressure);
                insertRawStatement.setDouble(7, record.batteryLevel);
                insertRawStatement.setString(8, record.status);
                insertRawStatement.setString(9, record.manufacturer);
                insertRawStatement.setString(10, record.model);
                insertRawStatement.setString(11, record.firmwareVersion);
                insertRawStatement.setDouble(12, record.latitude);
                insertRawStatement.setDouble(13, record.longitude);
                
                insertRawStatement.executeUpdate();
                
                // Check for alerts and insert if needed
                String alertType = null;
                if (record.temperature > 35) {
                    alertType = "HIGH_TEMPERATURE";
                } else if (record.humidity > 80) {
                    alertType = "HIGH_HUMIDITY";
                } else if (record.batteryLevel < 20) {
                    alertType = "LOW_BATTERY";
                }
                
                if (alertType != null) {
                    insertAlertStatement.setString(1, record.sensorId);
                    insertAlertStatement.setString(2, record.sensorType);
                    insertAlertStatement.setString(3, record.location);
                    insertAlertStatement.setDouble(4, record.temperature);
                    insertAlertStatement.setDouble(5, record.humidity);
                    insertAlertStatement.setDouble(6, record.batteryLevel);
                    insertAlertStatement.setString(7, alertType);
                    
                    insertAlertStatement.executeUpdate();
                    System.out.println("🚨 JDBC ALERT: " + record.sensorId + " - " + alertType);
                }
                
                System.out.println("✅ JDBC Processed: " + record.sensorId + " (T:" + String.format("%.1f", record.temperature) + "°C)");
                
            } catch (SQLException e) {
                System.err.println("JDBC Error processing data: " + e.getMessage());
                e.printStackTrace();
            }
        }
        
        @Override
        public void close() throws Exception {
            System.out.println("Closing JDBC connections...");
            if (insertRawStatement != null) {
                insertRawStatement.close();
            }
            if (insertAlertStatement != null) {
                insertAlertStatement.close();
            }
            if (connection != null) {
                connection.close();
            }
            super.close();
        }
    }
}