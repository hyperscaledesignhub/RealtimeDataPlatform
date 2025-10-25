# Flink Job AVRO Integration Summary

## Overview
The Flink job in `flink-load/flink-consumer` has been successfully updated to process AVRO messages instead of JSON from Pulsar topics.

## Changes Made

### 1. **Updated pom.xml**
- Added AVRO dependency: `org.apache.avro:avro:1.12.0`
- Added AVRO Maven plugin for schema generation
- Schema source directory: `src/main/resources/avro`
- Generated sources directory: `target/generated-sources/avro`

### 2. **Added AVRO Schema**
- Copied `SensorData.avsc` from producer to `src/main/resources/avro/`
- Schema includes nested metadata structure for IoT sensor data
- Compatible with the producer's AVRO schema

### 3. **Updated JDBCFlinkConsumer.java**

#### **New Imports:**
```java
import org.apache.avro.Schema;
import org.apache.avro.generic.GenericRecord;
import org.apache.flink.api.common.serialization.DeserializationSchema;
import java.io.IOException;
import java.io.InputStream;
```

#### **New AVRO Deserialization Schema:**
```java
public static class AvroSensorDataDeserializationSchema implements DeserializationSchema<GenericRecord> {
    private transient Schema avroSchema;
    private transient org.apache.avro.io.DatumReader<GenericRecord> datumReader;
    
    // Loads schema from /avro/SensorData.avsc
    // Properly deserializes AVRO binary messages
}
```

#### **Updated Pulsar Source:**
- Changed from `PulsarSource<String>` to `PulsarSource<GenericRecord>`
- Uses `AvroSensorDataDeserializationSchema` instead of `SimpleStringSchema`
- Updated subscription name to `flink-jdbc-consumer-avro`

#### **Updated Data Processing:**
- Changed from `DataStream<String>` to `DataStream<GenericRecord>`
- Updated map function to process `GenericRecord` instead of JSON string
- Added new `SensorRecord(GenericRecord avroRecord)` constructor

#### **New SensorRecord Constructor:**
```java
public SensorRecord(GenericRecord avroRecord) {
    // Maps AVRO fields to ClickHouse schema
    // Handles nested metadata structure
    // Provides default values for fields not in AVRO schema
}
```

## Field Mapping (AVRO → ClickHouse)

### **Direct Mappings:**
- `sensorId` → `device_id`
- `sensorType` → `device_type`
- `location` → `site_id`
- `temperature` → `temperature`
- `humidity` → `humidity`
- `pressure` → `pressure`
- `batteryLevel` → `battery_level`
- `status` → `status` (converted to int)

### **Nested Metadata Mappings:**
- `metadata.latitude` → `latitude`
- `metadata.longitude` → `longitude`
- `metadata.manufacturer` → (not used in ClickHouse schema)
- `metadata.model` → (not used in ClickHouse schema)
- `metadata.firmwareVersion` → (not used in ClickHouse schema)

### **Default Values (fields not in AVRO schema):**
- `customer_id` → `"customer_0001"`
- `altitude` → `0.0`
- `co2_level` → `400.0`
- `noise_level` → `50.0`
- `light_level` → `500.0`
- `motion_detected` → `0`
- `signal_strength` → `-50.0`
- `memory_usage` → `50.0`
- `cpu_usage` → `30.0`
- `error_count` → `0`
- Network metrics → `0L`

## Configuration Changes

### **Environment Variables:**
- No changes needed - same environment variables
- `PULSAR_URL`, `PULSAR_ADMIN_URL`, `PULSAR_TOPIC`, `CLICKHOUSE_URL`

### **Logging Updates:**
- Added "Schema Type: AVRO" to startup logs
- Updated subscription name in logs
- Added AVRO schema loading confirmation

## Compatibility

### **Backward Compatibility:**
- Original JSON constructor still available
- Can switch between JSON and AVRO by changing deserialization schema
- Same ClickHouse schema and aggregation logic

### **Producer Compatibility:**
- Works with AVRO-enabled producer (`producer-perf`)
- Uses same AVRO schema definition
- Handles device ID distribution from multiple producer instances

## Deployment

### **Build Process:**
```bash
cd flink-load/flink-consumer
mvn clean package
```

### **Docker Build:**
- No changes needed to Dockerfile
- AVRO dependencies included in JAR
- Schema file included in resources

### **Kubernetes Deployment:**
- No changes needed to deployment YAML
- Same environment variables
- Compatible with existing Flink operator configuration

## Verification

### **Expected Logs:**
```
✅ Loaded AVRO schema: SensorData
Starting JDBC Flink IoT Consumer with AVRO Support and 1-Minute Aggregation...
Schema Type: AVRO
Using: Official Flink Pulsar Connector with AVRO deserialization
```

### **Data Flow:**
1. **Producer** → AVRO messages → **Pulsar Topic**
2. **Flink Job** → AVRO deserialization → **SensorRecord**
3. **Aggregation** → 1-minute windows → **ClickHouse**

## Benefits

1. **Type Safety**: AVRO provides schema validation
2. **Performance**: Binary serialization is more efficient than JSON
3. **Schema Evolution**: AVRO supports backward/forward compatibility
4. **Consistency**: Same schema used by producer and consumer
5. **Compression**: AVRO messages are smaller than JSON

## Status: ✅ COMPLETE

The Flink job is now ready to process AVRO messages from the AVRO-enabled producer instances. All changes maintain backward compatibility and existing functionality while adding AVRO support.
