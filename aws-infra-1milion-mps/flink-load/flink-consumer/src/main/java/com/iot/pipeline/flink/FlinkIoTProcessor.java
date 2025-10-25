package com.iot.pipeline.flink;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.iot.pipeline.model.SensorData;
import org.apache.flink.api.common.serialization.DeserializationSchema;
import org.apache.flink.api.common.typeinfo.TypeInformation;
import org.apache.flink.api.java.typeutils.TypeExtractor;
import org.apache.flink.configuration.Configuration;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.functions.source.RichSourceFunction;
import org.apache.flink.streaming.api.functions.sink.RichSinkFunction;
import org.apache.flink.table.api.EnvironmentSettings;
import org.apache.flink.table.api.Table;
import org.apache.flink.table.api.bridge.java.StreamTableEnvironment;
import org.apache.pulsar.client.api.*;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.time.Duration;
import java.util.concurrent.TimeUnit;

public class FlinkIoTProcessor {
    private static final Logger logger = LoggerFactory.getLogger(FlinkIoTProcessor.class);
    
    public static void main(String[] args) throws Exception {
        String pulsarUrl = System.getenv().getOrDefault("PULSAR_URL", "pulsar://localhost:6650");
        String topicName = System.getenv().getOrDefault("PULSAR_TOPIC", "persistent://public/default/iot-sensor-data");
        String clickhouseUrl = System.getenv().getOrDefault("CLICKHOUSE_URL", "jdbc:clickhouse://localhost:8123/iot");
        
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        env.setParallelism(2);
        env.enableCheckpointing(60000);
        
        EnvironmentSettings settings = EnvironmentSettings.newInstance()
                .inStreamingMode()
                .build();
        StreamTableEnvironment tableEnv = StreamTableEnvironment.create(env, settings);
        
        // Create Pulsar source
        DataStream<SensorData> sensorDataStream = env.addSource(
                new PulsarSensorSource(pulsarUrl, topicName),
                "Pulsar IoT Source"
        );
        
        // Filter only active sensors (status = 1)
        DataStream<SensorData> activeSensors = sensorDataStream
                .filter(data -> data != null && data.isActive());
        
        // Create alerts stream
        DataStream<SensorAlert> alertStream = activeSensors
                .map(data -> {
                    String alertType = "NORMAL";
                    if (data.getTemperature() > 35) {
                        alertType = "HIGH_TEMPERATURE";
                    } else if (data.getHumidity() > 80) {
                        alertType = "HIGH_HUMIDITY";
                    } else if (data.getBatteryLevel() < 20) {
                        alertType = "LOW_BATTERY";
                    }
                    
                    return new SensorAlert(
                            data.getSensorId(),
                            data.getSensorType(),
                            data.getLocation(),
                            data.getTemperature(),
                            data.getHumidity(),
                            data.getBatteryLevel(),
                            alertType,
                            System.currentTimeMillis()
                    );
                })
                .filter(alert -> !"NORMAL".equals(alert.getAlertType()));
        
        // Sink alerts to ClickHouse
        alertStream.addSink(new ClickHouseSink<SensorAlert>(clickhouseUrl, "sensor_alerts") {
            @Override
            protected String getInsertSQL() {
                return "INSERT INTO sensor_alerts (sensor_id, sensor_type, location, temperature, humidity, battery_level, alert_type, alert_time) VALUES (?, ?, ?, ?, ?, ?, ?, ?)";
            }
            
            @Override
            protected void setParameters(PreparedStatement stmt, SensorAlert alert) throws Exception {
                stmt.setInt(1, alert.getSensorId());
                stmt.setInt(2, alert.getSensorType());
                stmt.setInt(3, alert.getLocation());
                stmt.setDouble(4, alert.getTemperature());
                stmt.setDouble(5, alert.getHumidity());
                stmt.setDouble(6, alert.getBatteryLevel());
                stmt.setString(7, alert.getAlertType());
                stmt.setTimestamp(8, new java.sql.Timestamp(alert.getAlertTime()));
            }
        });
        
        // Sink raw data to ClickHouse
        activeSensors.addSink(new ClickHouseSink<SensorData>(clickhouseUrl, "sensor_raw_data") {
            @Override
            protected String getInsertSQL() {
                return "INSERT INTO sensor_raw_data (sensor_id, sensor_type, location, temperature, humidity, pressure, battery_level, status, timestamp) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)";
            }
            
            @Override
            protected void setParameters(PreparedStatement stmt, SensorData data) throws Exception {
                stmt.setInt(1, data.getSensorId());
                stmt.setInt(2, data.getSensorType());
                stmt.setInt(3, data.getLocation());
                stmt.setDouble(4, data.getTemperature());
                stmt.setDouble(5, data.getHumidity());
                stmt.setDouble(6, data.getPressure());
                stmt.setDouble(7, data.getBatteryLevel());
                stmt.setInt(8, data.getStatus());
                stmt.setTimestamp(9, new java.sql.Timestamp(data.getTimestamp().toEpochMilli()));
            }
        });
        
        logger.info("Starting Flink IoT Processing Pipeline");
        env.execute("IoT Data Processing Pipeline");
    }
    
    public static class PulsarSensorSource extends RichSourceFunction<SensorData> {
        private volatile boolean isRunning = true;
        private final String pulsarUrl;
        private final String topicName;
        private PulsarClient client;
        private Consumer<byte[]> consumer;
        private static final ObjectMapper mapper = new ObjectMapper();
        
        public PulsarSensorSource(String pulsarUrl, String topicName) {
            this.pulsarUrl = pulsarUrl;
            this.topicName = topicName;
        }
        
        @Override
        public void open(Configuration parameters) throws Exception {
            super.open(parameters);
            
            client = PulsarClient.builder()
                    .serviceUrl(pulsarUrl)
                    .build();
            
            consumer = client.newConsumer()
                    .topic(topicName)
                    .subscriptionName("flink-iot-consumer")
                    .subscriptionType(SubscriptionType.Shared)
                    .ackTimeout(30, TimeUnit.SECONDS)
                    .subscribe();
        }
        
        @Override
        public void run(SourceContext<SensorData> ctx) throws Exception {
            while (isRunning) {
                try {
                    Message<byte[]> message = consumer.receive(5, TimeUnit.SECONDS);
                    if (message != null) {
                        String jsonData = new String(message.getData());
                        SensorData sensorData = mapper.readValue(jsonData, SensorData.class);
                        ctx.collect(sensorData);
                        consumer.acknowledge(message);
                    }
                } catch (Exception e) {
                    logger.error("Error processing message", e);
                }
            }
        }
        
        @Override
        public void cancel() {
            isRunning = false;
        }
        
        @Override
        public void close() throws Exception {
            if (consumer != null) {
                consumer.close();
            }
            if (client != null) {
                client.close();
            }
            super.close();
        }
    }
    
    public static abstract class ClickHouseSink<T> extends RichSinkFunction<T> {
        private final String jdbcUrl;
        private final String tableName;
        private Connection connection;
        private PreparedStatement insertStatement;
        
        public ClickHouseSink(String jdbcUrl, String tableName) {
            this.jdbcUrl = jdbcUrl;
            this.tableName = tableName;
        }
        
        @Override
        public void open(Configuration parameters) throws Exception {
            super.open(parameters);
            Class.forName("com.clickhouse.jdbc.ClickHouseDriver");
            connection = DriverManager.getConnection(jdbcUrl);
            insertStatement = connection.prepareStatement(getInsertSQL());
        }
        
        @Override
        public void invoke(T value, Context context) throws Exception {
            setParameters(insertStatement, value);
            insertStatement.executeUpdate();
        }
        
        @Override
        public void close() throws Exception {
            if (insertStatement != null) {
                insertStatement.close();
            }
            if (connection != null) {
                connection.close();
            }
            super.close();
        }
        
        protected abstract String getInsertSQL();
        protected abstract void setParameters(PreparedStatement stmt, T value) throws Exception;
    }
    
    public static class SensorAlert {
        private int sensorId;
        private int sensorType;
        private int location;
        private double temperature;
        private double humidity;
        private double batteryLevel;
        private String alertType;
        private long alertTime;
        
        public SensorAlert() {}
        
        public SensorAlert(int sensorId, int sensorType, int location,
                          double temperature, double humidity, double batteryLevel,
                          String alertType, long alertTime) {
            this.sensorId = sensorId;
            this.sensorType = sensorType;
            this.location = location;
            this.temperature = temperature;
            this.humidity = humidity;
            this.batteryLevel = batteryLevel;
            this.alertType = alertType;
            this.alertTime = alertTime;
        }
        
        // Getters
        public int getSensorId() { return sensorId; }
        public int getSensorType() { return sensorType; }
        public int getLocation() { return location; }
        public double getTemperature() { return temperature; }
        public double getHumidity() { return humidity; }
        public double getBatteryLevel() { return batteryLevel; }
        public String getAlertType() { return alertType; }
        public long getAlertTime() { return alertTime; }
        
        // Setters
        public void setSensorId(int sensorId) { this.sensorId = sensorId; }
        public void setSensorType(int sensorType) { this.sensorType = sensorType; }
        public void setLocation(int location) { this.location = location; }
        public void setTemperature(double temperature) { this.temperature = temperature; }
        public void setHumidity(double humidity) { this.humidity = humidity; }
        public void setBatteryLevel(double batteryLevel) { this.batteryLevel = batteryLevel; }
        public void setAlertType(String alertType) { this.alertType = alertType; }
        public void setAlertTime(long alertTime) { this.alertTime = alertTime; }
    }
}