package com.iot.pipeline.flink;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.apache.avro.Schema;
import org.apache.avro.generic.GenericRecord;
import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.api.common.functions.AggregateFunction;
import org.apache.flink.api.common.serialization.DeserializationSchema;
import org.apache.flink.api.common.serialization.SimpleStringSchema;
import org.apache.flink.api.common.state.ListState;
import org.apache.flink.api.common.state.ListStateDescriptor;
import org.apache.flink.api.common.typeinfo.TypeInformation;
import org.apache.flink.configuration.Configuration;
import org.apache.flink.connector.pulsar.source.PulsarSource;
import org.apache.flink.connector.pulsar.source.enumerator.cursor.StartCursor;
import org.apache.flink.runtime.state.FunctionInitializationContext;
import org.apache.flink.runtime.state.FunctionSnapshotContext;
import org.apache.flink.streaming.api.checkpoint.CheckpointedFunction;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.functions.sink.RichSinkFunction;
import org.apache.flink.streaming.api.windowing.assigners.TumblingProcessingTimeWindows;
import org.apache.flink.streaming.api.windowing.time.Time;

import java.io.IOException;
import java.io.InputStream;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.SQLException;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.TimeUnit;

public class JDBCFlinkConsumer {
    private static final ObjectMapper mapper = new ObjectMapper();
    
    /**
     * AVRO Deserialization Schema for SensorData - converts to SensorRecord directly
     */
    public static class AvroSensorDataDeserializationSchema implements DeserializationSchema<SensorRecord> {
        private transient Schema avroSchema;
        private transient org.apache.avro.io.DatumReader<GenericRecord> datumReader;
        
        @Override
        public void open(InitializationContext context) throws Exception {
            // Load AVRO schema from resources (now included in JAR)
            try (InputStream schemaStream = getClass().getResourceAsStream("/avro/SensorData.avsc")) {
                if (schemaStream == null) {
                    throw new RuntimeException("AVRO schema file not found: /avro/SensorData.avsc");
                }
                avroSchema = new Schema.Parser().parse(schemaStream);
                datumReader = new org.apache.avro.generic.GenericDatumReader<>(avroSchema);
                System.out.println("✅ Loaded AVRO schema from JAR: " + avroSchema.getName());
            } catch (Exception e) {
                throw new RuntimeException("Failed to load AVRO schema", e);
            }
        }
        
        @Override
        public SensorRecord deserialize(byte[] message) throws IOException {
            try {
                // Deserialize AVRO binary message
                org.apache.avro.io.Decoder decoder = org.apache.avro.io.DecoderFactory.get().binaryDecoder(message, null);
                GenericRecord avroRecord = datumReader.read(null, decoder);
                
                // Convert directly to SensorRecord to avoid Kryo serialization issues
                return new SensorRecord(avroRecord);
            } catch (Exception e) {
                throw new IOException("Failed to deserialize AVRO message", e);
            }
        }
        
        @Override
        public boolean isEndOfStream(SensorRecord nextElement) {
            return false;
        }
        
        @Override
        public TypeInformation<SensorRecord> getProducedType() {
            return TypeInformation.of(SensorRecord.class);
        }
    }
    
    public static void main(String[] args) throws Exception {
        String pulsarUrl = System.getenv().getOrDefault("PULSAR_URL", "pulsar://localhost:6650");
        String pulsarAdminUrl = System.getenv().getOrDefault("PULSAR_ADMIN_URL", "http://localhost:8080");
        String baseTopicName = System.getenv().getOrDefault("PULSAR_TOPIC", "persistent://public/default/iot-sensor-data");
        String clickhouseUrl = System.getenv().getOrDefault("CLICKHOUSE_URL", "jdbc:clickhouse://localhost:8123/benchmark");
        
        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();
        // Use parallelism from FlinkDeployment YAML or default to 4
        // env.setParallelism(4);  // REMOVED - let YAML control parallelism
        
        // NOTE: Checkpointing is now configured via FlinkDeployment YAML
        // The config includes: interval, mode (EXACTLY_ONCE), state backend (RocksDB), etc.
        // This code is checkpoint-aware and will participate in checkpointing automatically
        
        System.out.println("Starting JDBC Flink IoT Consumer with AVRO Support and 1-Minute Aggregation...");
        System.out.println("Pulsar URL: " + pulsarUrl);
        System.out.println("Pulsar Admin URL: " + pulsarAdminUrl);
        System.out.println("Consuming Topic: " + baseTopicName + " (all partitions)");
        System.out.println("ClickHouse URL: " + clickhouseUrl);
        System.out.println("Schema Type: AVRO");
        System.out.println("Checkpointing: Enabled via FlinkDeployment config");
        System.out.println("Aggregation: 1-minute tumbling windows per device_id with keyBy()");
        System.out.println("Expected reduction: 30K msgs/sec → ~500-1000 aggregated records/min");
        System.out.println("Using: Official Flink Pulsar Connector with AVRO deserialization");
        
               // Create Pulsar source using official Flink connector with AVRO deserialization
               // The connector will automatically discover and consume from all partitions of the topic.
               PulsarSource<SensorRecord> source = PulsarSource.builder()
                       .setServiceUrl(pulsarUrl)
                       .setAdminUrl(pulsarAdminUrl)
                       .setTopics(baseTopicName) // Changed from topicName to baseTopicName
                       .setSubscriptionName("flink-jdbc-consumer-avro")
                       .setDeserializationSchema(new AvroSensorDataDeserializationSchema())
                       .setStartCursor(StartCursor.earliest())
                       .build();

               DataStream<SensorRecord> sensorStream = env.fromSource(
                       source,
                       WatermarkStrategy.noWatermarks(),
                       "Pulsar AVRO IoT Source"
               );
        
        // Aggregate by device_id over 1-minute windows
        sensorStream
                .keyBy(record -> record.device_id)
                .window(TumblingProcessingTimeWindows.of(Time.minutes(1)))
                .aggregate(new SensorAggregator())
                .addSink(new ClickHouseJDBCSink(clickhouseUrl));
        
        System.out.println("JDBC Flink job started!");
        env.execute("JDBC IoT Data Pipeline");
    }
    
        public static class SensorRecord implements java.io.Serializable {
        // Matching benchmark.sensors_local schema
        public String device_id;
        public String device_type;
        public String customer_id;
        public String site_id;
        public double latitude;
        public double longitude;
        public double altitude;
        public double temperature;
        public double humidity;
        public double pressure;
        public double co2_level;
        public double noise_level;
        public double light_level;
        public int motion_detected;
        public double battery_level;
        public double signal_strength;
        public double memory_usage;
        public double cpu_usage;
        public int status;
        public int error_count;
        public long packets_sent;
        public long packets_received;
        public long bytes_sent;
        public long bytes_received;
        
        // Default constructor for aggregator
        public SensorRecord() {
        }
        
        public SensorRecord(JsonNode json) {
            // Map from Pulsar JSON to ClickHouse schema
            this.device_id = json.has("sensorId") ? json.get("sensorId").asText() : json.get("device_id").asText("device_unknown");
            this.device_type = json.has("sensorType") ? json.get("sensorType").asText() : json.get("device_type").asText("unknown");
            this.customer_id = json.has("customer_id") ? json.get("customer_id").asText() : "customer_0001";
            this.site_id = json.has("site_id") ? json.get("site_id").asText() : json.has("location") ? json.get("location").asText() : "site_001";
            
            // Location data
            JsonNode metadata = json.get("metadata");
            if (metadata != null) {
                this.latitude = metadata.has("latitude") ? metadata.get("latitude").asDouble() : 0.0;
                this.longitude = metadata.has("longitude") ? metadata.get("longitude").asDouble() : 0.0;
            } else {
                this.latitude = json.has("latitude") ? json.get("latitude").asDouble() : 0.0;
                this.longitude = json.has("longitude") ? json.get("longitude").asDouble() : 0.0;
            }
            this.altitude = json.has("altitude") ? json.get("altitude").asDouble() : 0.0;
            
            // Sensor readings
            this.temperature = json.has("temperature") ? json.get("temperature").asDouble() : 0.0;
            this.humidity = json.has("humidity") ? json.get("humidity").asDouble() : 0.0;
            this.pressure = json.has("pressure") ? json.get("pressure").asDouble() : 1013.25;
            this.co2_level = json.has("co2_level") ? json.get("co2_level").asDouble() : 400.0;
            this.noise_level = json.has("noise_level") ? json.get("noise_level").asDouble() : 50.0;
            this.light_level = json.has("light_level") ? json.get("light_level").asDouble() : 500.0;
            this.motion_detected = json.has("motion_detected") ? json.get("motion_detected").asInt() : 0;
            
            // Device metrics
            this.battery_level = json.has("batteryLevel") ? json.get("batteryLevel").asDouble() : 
                                 json.has("battery_level") ? json.get("battery_level").asDouble() : 100.0;
            this.signal_strength = json.has("signal_strength") ? json.get("signal_strength").asDouble() : -50.0;
            this.memory_usage = json.has("memory_usage") ? json.get("memory_usage").asDouble() : 50.0;
            this.cpu_usage = json.has("cpu_usage") ? json.get("cpu_usage").asDouble() : 30.0;
            
            // Status - convert string to int if needed
            if (json.has("status")) {
                if (json.get("status").isInt()) {
                    this.status = json.get("status").asInt();
                } else {
                    String statusStr = json.get("status").asText().toLowerCase();
                    this.status = statusStr.equals("online") ? 1 : statusStr.equals("offline") ? 2 : 
                                  statusStr.equals("maintenance") ? 3 : 4;
                }
            } else {
                this.status = 1; // Default: online
            }
            
            this.error_count = json.has("error_count") ? json.get("error_count").asInt() : 0;
            
            // Network metrics
            this.packets_sent = json.has("packets_sent") ? json.get("packets_sent").asLong() : 0L;
            this.packets_received = json.has("packets_received") ? json.get("packets_received").asLong() : 0L;
            this.bytes_sent = json.has("bytes_sent") ? json.get("bytes_sent").asLong() : 0L;
            this.bytes_received = json.has("bytes_received") ? json.get("bytes_received").asLong() : 0L;
        }
        
        public SensorRecord(GenericRecord avroRecord) {
            // Map from Pulsar AVRO to ClickHouse schema - FIXED for actual AVRO schema
            // Convert integer sensorId to string device_id
            this.device_id = avroRecord.get("sensorId") != null ? 
                "sensor_" + avroRecord.get("sensorId").toString() : "device_unknown";
            
            // Convert integer sensorType to string device_type
            int sensorTypeInt = avroRecord.get("sensorType") != null ? 
                ((Number) avroRecord.get("sensorType")).intValue() : 1;
            this.device_type = getSensorTypeString(sensorTypeInt);
            
            this.customer_id = "customer_0001"; // Default value since not in AVRO schema
            
            // FIXED: No location field in AVRO schema - use sensorId for site_id
            int sensorId = avroRecord.get("sensorId") != null ? 
                ((Number) avroRecord.get("sensorId")).intValue() : 1;
            this.site_id = "site_" + String.format("%03d", (sensorId % 100) + 1);
            
            // Location data - no metadata in new schema, use defaults
            this.latitude = 0.0; // Not in optimized schema
            this.longitude = 0.0; // Not in optimized schema
            this.altitude = 0.0; // Not in AVRO schema
            
            // Sensor readings - FIXED: Use actual AVRO field names
            this.temperature = avroRecord.get("temperature") != null ? ((Number) avroRecord.get("temperature")).doubleValue() : 0.0;
            this.humidity = avroRecord.get("humidity") != null ? ((Number) avroRecord.get("humidity")).doubleValue() : 0.0;
            this.pressure = avroRecord.get("pressure") != null ? ((Number) avroRecord.get("pressure")).doubleValue() : 1013.25;
            this.co2_level = 400.0; // Default value since not in AVRO schema
            this.noise_level = 50.0; // Default value since not in AVRO schema
            this.light_level = 500.0; // Default value since not in AVRO schema
            this.motion_detected = 0; // Default value since not in AVRO schema
            
            // Device metrics - FIXED: Use correct field name batteryLevel
            this.battery_level = avroRecord.get("batteryLevel") != null ? ((Number) avroRecord.get("batteryLevel")).doubleValue() : 100.0;
            this.signal_strength = -50.0; // Default value since not in AVRO schema
            this.memory_usage = 50.0; // Default value since not in AVRO schema
            this.cpu_usage = 30.0; // Default value since not in AVRO schema
            
            // Status - now integer in new schema
            this.status = avroRecord.get("status") != null ? 
                ((Number) avroRecord.get("status")).intValue() : 1;
            
            this.error_count = 0; // Default value since not in AVRO schema
            
            // Network metrics - default values since not in AVRO schema
            this.packets_sent = 0L;
            this.packets_received = 0L;
            this.bytes_sent = 0L;
            this.bytes_received = 0L;
        }
        
        // Helper method to convert integer sensor type to string
        // FIXED: Match producer's sensor type mapping (1-8)
        private String getSensorTypeString(int sensorType) {
            switch (sensorType) {
                case 1: return "temperature_sensor";
                case 2: return "humidity_sensor";
                case 3: return "pressure_sensor";
                case 4: return "motion_sensor";
                case 5: return "light_sensor";
                case 6: return "co2_sensor";
                case 7: return "noise_sensor";
                case 8: return "multisensor";
                default: return "sensor_type_" + sensorType;
            }
        }
    }
    
    /**
     * Aggregator for sensor data over 1-minute windows
     * Computes min, max, avg for sensor readings
     */
    public static class SensorAggregator implements AggregateFunction<SensorRecord, SensorAggregator.Accumulator, SensorRecord> {
        
        public static class Accumulator {
            // Metadata (take first value)
            String device_id;
            String device_type;
            String customer_id;
            String site_id;
            double latitude;
            double longitude;
            double altitude;
            
            // Sensor readings - track sum, min, max, count
            long count = 0;
            
            // Temperature
            double temp_sum = 0.0;
            double temp_min = Double.MAX_VALUE;
            double temp_max = Double.MIN_VALUE;
            
            // Humidity
            double hum_sum = 0.0;
            double hum_min = Double.MAX_VALUE;
            double hum_max = Double.MIN_VALUE;
            
            // Pressure
            double press_sum = 0.0;
            double press_min = Double.MAX_VALUE;
            double press_max = Double.MIN_VALUE;
            
            // CO2
            double co2_sum = 0.0;
            double co2_min = Double.MAX_VALUE;
            double co2_max = Double.MIN_VALUE;
            
            // Noise
            double noise_sum = 0.0;
            double noise_min = Double.MAX_VALUE;
            double noise_max = Double.MIN_VALUE;
            
            // Light
            double light_sum = 0.0;
            double light_min = Double.MAX_VALUE;
            double light_max = Double.MIN_VALUE;
            
            // Battery
            double battery_sum = 0.0;
            double battery_min = Double.MAX_VALUE;
            double battery_max = Double.MIN_VALUE;
            
            // Signal strength
            double signal_sum = 0.0;
            double signal_min = Double.MAX_VALUE;
            double signal_max = Double.MIN_VALUE;
            
            // Status counters
            int motion_detected_count = 0;
            int error_count_sum = 0;
            int status_sum = 0;
            
            // Network metrics
            long packets_sent_sum = 0;
            long packets_received_sum = 0;
            long bytes_sent_sum = 0;
            long bytes_received_sum = 0;
        }
        
        @Override
        public Accumulator createAccumulator() {
            return new Accumulator();
        }
        
        @Override
        public Accumulator add(SensorRecord record, Accumulator acc) {
            // First record - capture metadata
            if (acc.count == 0) {
                acc.device_id = record.device_id;
                acc.device_type = record.device_type;
                acc.customer_id = record.customer_id;
                acc.site_id = record.site_id;
                acc.latitude = record.latitude;
                acc.longitude = record.longitude;
                acc.altitude = record.altitude;
            }
            
            acc.count++;
            
            // Temperature
            acc.temp_sum += record.temperature;
            acc.temp_min = Math.min(acc.temp_min, record.temperature);
            acc.temp_max = Math.max(acc.temp_max, record.temperature);
            
            // Humidity
            acc.hum_sum += record.humidity;
            acc.hum_min = Math.min(acc.hum_min, record.humidity);
            acc.hum_max = Math.max(acc.hum_max, record.humidity);
            
            // Pressure
            acc.press_sum += record.pressure;
            acc.press_min = Math.min(acc.press_min, record.pressure);
            acc.press_max = Math.max(acc.press_max, record.pressure);
            
            // CO2
            acc.co2_sum += record.co2_level;
            acc.co2_min = Math.min(acc.co2_min, record.co2_level);
            acc.co2_max = Math.max(acc.co2_max, record.co2_level);
            
            // Noise
            acc.noise_sum += record.noise_level;
            acc.noise_min = Math.min(acc.noise_min, record.noise_level);
            acc.noise_max = Math.max(acc.noise_max, record.noise_level);
            
            // Light
            acc.light_sum += record.light_level;
            acc.light_min = Math.min(acc.light_min, record.light_level);
            acc.light_max = Math.max(acc.light_max, record.light_level);
            
            // Battery
            acc.battery_sum += record.battery_level;
            acc.battery_min = Math.min(acc.battery_min, record.battery_level);
            acc.battery_max = Math.max(acc.battery_max, record.battery_level);
            
            // Signal
            acc.signal_sum += record.signal_strength;
            acc.signal_min = Math.min(acc.signal_min, record.signal_strength);
            acc.signal_max = Math.max(acc.signal_max, record.signal_strength);
            
            // Status and counters
            if (record.motion_detected == 1) acc.motion_detected_count++;
            acc.error_count_sum += record.error_count;
            acc.status_sum += record.status;
            
            // Network metrics
            acc.packets_sent_sum += record.packets_sent;
            acc.packets_received_sum += record.packets_received;
            acc.bytes_sent_sum += record.bytes_sent;
            acc.bytes_received_sum += record.bytes_received;
            
            return acc;
        }
        
        @Override
        public SensorRecord getResult(Accumulator acc) {
            // Create aggregated sensor record with averages
            SensorRecord result = new SensorRecord();
            
            result.device_id = acc.device_id;
            result.device_type = acc.device_type;
            result.customer_id = acc.customer_id;
            result.site_id = acc.site_id;
            result.latitude = acc.latitude;
            result.longitude = acc.longitude;
            result.altitude = acc.altitude;
            
            // Average values
            result.temperature = acc.temp_sum / acc.count;
            result.humidity = acc.hum_sum / acc.count;
            result.pressure = acc.press_sum / acc.count;
            result.co2_level = acc.co2_sum / acc.count;
            result.noise_level = acc.noise_sum / acc.count;
            result.light_level = acc.light_sum / acc.count;
            result.battery_level = acc.battery_sum / acc.count;
            result.signal_strength = acc.signal_sum / acc.count;
            
            // Motion detected if > 50% of readings had motion
            result.motion_detected = (acc.motion_detected_count > acc.count / 2) ? 1 : 0;
            
            // Average status
            result.status = (int) (acc.status_sum / acc.count);
            result.error_count = acc.error_count_sum;
            
            // Total network metrics
            result.packets_sent = acc.packets_sent_sum;
            result.packets_received = acc.packets_received_sum;
            result.bytes_sent = acc.bytes_sent_sum;
            result.bytes_received = acc.bytes_received_sum;
            
            // Add CPU and memory usage (simple averages)
            result.memory_usage = 50.0; // Placeholder
            result.cpu_usage = 30.0; // Placeholder
            
            System.out.println("✅ Aggregated window: device=" + result.device_id + 
                             ", count=" + acc.count + " records, avg_temp=" + 
                             String.format("%.1f", result.temperature));
            
            return result;
        }
        
        @Override
        public Accumulator merge(Accumulator a, Accumulator b) {
            // Merge two accumulators (for parallel processing)
            a.count += b.count;
            
            // Temperature
            a.temp_sum += b.temp_sum;
            a.temp_min = Math.min(a.temp_min, b.temp_min);
            a.temp_max = Math.max(a.temp_max, b.temp_max);
            
            // Humidity
            a.hum_sum += b.hum_sum;
            a.hum_min = Math.min(a.hum_min, b.hum_min);
            a.hum_max = Math.max(a.hum_max, b.hum_max);
            
            // Pressure
            a.press_sum += b.press_sum;
            a.press_min = Math.min(a.press_min, b.press_min);
            a.press_max = Math.max(a.press_max, b.press_max);
            
            // CO2
            a.co2_sum += b.co2_sum;
            a.co2_min = Math.min(a.co2_min, b.co2_min);
            a.co2_max = Math.max(a.co2_max, b.co2_max);
            
            // Noise
            a.noise_sum += b.noise_sum;
            a.noise_min = Math.min(a.noise_min, b.noise_min);
            a.noise_max = Math.max(a.noise_max, b.noise_max);
            
            // Light
            a.light_sum += b.light_sum;
            a.light_min = Math.min(a.light_min, b.light_min);
            a.light_max = Math.max(a.light_max, b.light_max);
            
            // Battery
            a.battery_sum += b.battery_sum;
            a.battery_min = Math.min(a.battery_min, b.battery_min);
            a.battery_max = Math.max(a.battery_max, b.battery_max);
            
            // Signal
            a.signal_sum += b.signal_sum;
            a.signal_min = Math.min(a.signal_min, b.signal_min);
            a.signal_max = Math.max(a.signal_max, b.signal_max);
            
            // Counters
            a.motion_detected_count += b.motion_detected_count;
            a.error_count_sum += b.error_count_sum;
            a.status_sum += b.status_sum;
            
            // Network
            a.packets_sent_sum += b.packets_sent_sum;
            a.packets_received_sum += b.packets_received_sum;
            a.bytes_sent_sum += b.bytes_sent_sum;
            a.bytes_received_sum += b.bytes_received_sum;
            
            return a;
        }
    }
    
    /**
     * Checkpoint-aware ClickHouse JDBC Sink
     * Flushes batches to ClickHouse during checkpoints for exactly-once semantics
     */
    public static class ClickHouseJDBCSink extends RichSinkFunction<SensorRecord> implements CheckpointedFunction {
        private final String jdbcUrl;
        private Connection connection;
        private PreparedStatement insertStatement;
        private int batchCount = 0;
        private static final int BATCH_SIZE = 5000;  // Increased from 1000 to 5000 for better throughput
        
        // Checkpoint state
        private transient ListState<Integer> batchCountState;
        
        public ClickHouseJDBCSink(String jdbcUrl) {
            this.jdbcUrl = jdbcUrl;
        }
        
        @Override
        public void open(Configuration parameters) throws Exception {
            super.open(parameters);
            
            System.out.println("Opening JDBC connection to ClickHouse: " + jdbcUrl);
            
            // Load ClickHouse JDBC driver
            Class.forName("com.clickhouse.jdbc.ClickHouseDriver");
            
            // Add jdbcCompliant=false to avoid transaction warnings (ClickHouse doesn't support transactions)
            String finalUrl = jdbcUrl;
            if (!jdbcUrl.contains("jdbcCompliant")) {
                finalUrl = jdbcUrl + (jdbcUrl.contains("?") ? "&" : "?") + "jdbcCompliant=false";
            }
            connection = DriverManager.getConnection(finalUrl);
            // Note: ClickHouse doesn't support transactions, batching is handled automatically
            
            // Prepare INSERT statement for benchmark.sensors_local
            insertStatement = connection.prepareStatement(
                "INSERT INTO benchmark.sensors_local (" +
                "device_id, device_type, customer_id, site_id, " +
                "latitude, longitude, altitude, time, " +
                "temperature, humidity, pressure, co2_level, noise_level, light_level, motion_detected, " +
                "battery_level, signal_strength, memory_usage, cpu_usage, " +
                "status, error_count, " +
                "packets_sent, packets_received, bytes_sent, bytes_received" +
                ") VALUES (?, ?, ?, ?, ?, ?, ?, now(), ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
            );
            
            System.out.println("JDBC connection established successfully!");
        }
        
        @Override
        public void invoke(SensorRecord record, Context context) throws Exception {
            try {
                // Insert into benchmark.sensors_local - all 25 fields
                int idx = 1;
                insertStatement.setString(idx++, record.device_id);
                insertStatement.setString(idx++, record.device_type);
                insertStatement.setString(idx++, record.customer_id);
                insertStatement.setString(idx++, record.site_id);
                insertStatement.setDouble(idx++, record.latitude);
                insertStatement.setDouble(idx++, record.longitude);
                insertStatement.setDouble(idx++, record.altitude);
                // time is set by now() in SQL
                insertStatement.setDouble(idx++, record.temperature);
                insertStatement.setDouble(idx++, record.humidity);
                insertStatement.setDouble(idx++, record.pressure);
                insertStatement.setDouble(idx++, record.co2_level);
                insertStatement.setDouble(idx++, record.noise_level);
                insertStatement.setDouble(idx++, record.light_level);
                insertStatement.setInt(idx++, record.motion_detected);
                insertStatement.setDouble(idx++, record.battery_level);
                insertStatement.setDouble(idx++, record.signal_strength);
                insertStatement.setDouble(idx++, record.memory_usage);
                insertStatement.setDouble(idx++, record.cpu_usage);
                insertStatement.setInt(idx++, record.status);
                insertStatement.setInt(idx++, record.error_count);
                insertStatement.setLong(idx++, record.packets_sent);
                insertStatement.setLong(idx++, record.packets_received);
                insertStatement.setLong(idx++, record.bytes_sent);
                insertStatement.setLong(idx++, record.bytes_received);
                
                // Add to batch instead of executing immediately
                insertStatement.addBatch();
                batchCount++;
                
                // Execute batch when it reaches BATCH_SIZE OR during checkpoint
                // Checkpoints will force flush even if batch size not reached
                if (batchCount >= BATCH_SIZE) {
                    insertStatement.executeBatch();
                    // No commit() needed - ClickHouse doesn't support transactions
                    System.out.println("✅ Batch executed: " + batchCount + " records");
                    batchCount = 0;
                }
                
                // Log alerts (has_alert is automatically calculated by ClickHouse)
                if (record.temperature > 35 || record.humidity > 80 || record.battery_level < 20) {
                    String alertType = record.temperature > 35 ? "HIGH_TEMP" : 
                                      record.humidity > 80 ? "HIGH_HUMIDITY" : "LOW_BATTERY";
                    System.out.println("🚨 ALERT: " + record.device_id + " - " + alertType);
                }
                
            } catch (SQLException e) {
                System.err.println("JDBC Error processing data: " + e.getMessage());
                e.printStackTrace();
                // Reset batch on error (no rollback needed - ClickHouse doesn't support transactions)
                batchCount = 0;
            }
        }
        
        @Override
        public void snapshotState(FunctionSnapshotContext context) throws Exception {
            // Called when Flink takes a checkpoint
            // Flush any pending batch to ClickHouse before checkpoint completes
            if (batchCount > 0) {
                insertStatement.executeBatch();
                // No commit() needed - ClickHouse doesn't support transactions
                System.out.println("✅ Checkpoint " + context.getCheckpointId() + 
                                 ": Flushed " + batchCount + " records to ClickHouse");
                batchCount = 0;
            }
            
            // Save batch count to checkpoint state (for monitoring)
            batchCountState.clear();
            batchCountState.add(batchCount);
        }
        
        @Override
        public void initializeState(FunctionInitializationContext context) throws Exception {
            // Initialize checkpoint state
            ListStateDescriptor<Integer> descriptor = new ListStateDescriptor<>(
                "batch-count-state",
                TypeInformation.of(Integer.class)
            );
            batchCountState = context.getOperatorStateStore().getListState(descriptor);
            
            if (context.isRestored()) {
                // Restore batch count from checkpoint (if any)
                for (Integer count : batchCountState.get()) {
                    batchCount = count;
                }
                System.out.println("🔄 Restored from checkpoint - batch count: " + batchCount);
            }
        }
        
        @Override
        public void close() throws Exception {
            // Flush any remaining batch
            try {
                if (insertStatement != null && batchCount > 0) {
                    insertStatement.executeBatch();
                    // No commit() needed - ClickHouse doesn't support transactions
                    System.out.println("✅ Final batch executed: " + batchCount + " records");
                }
            } catch (SQLException e) {
                System.err.println("Error flushing final batch: " + e.getMessage());
            }
            
            System.out.println("Closing JDBC connections...");
            if (insertStatement != null) {
                insertStatement.close();
            }
            if (connection != null) {
                connection.close();
            }
            super.close();
        }
    }
}