package com.iot.pipeline.model;

import com.fasterxml.jackson.annotation.JsonProperty;
import java.io.Serializable;
import java.time.Instant;

/**
 * Sensor Data Model matching benchmark.sensors_local schema
 * All fields map to ClickHouse columns
 */
public class SensorData implements Serializable {
    // Device identifiers
    @JsonProperty("device_id")
    private String deviceId;
    
    @JsonProperty("device_type")
    private String deviceType;
    
    @JsonProperty("customer_id")
    private String customerId;
    
    @JsonProperty("site_id")
    private String siteId;
    
    // Location data
    private double latitude;
    private double longitude;
    private float altitude;
    
    // Timestamp (will be converted to DateTime64(3) in ClickHouse)
    private Instant time;
    
    // Sensor readings
    private float temperature;
    private float humidity;
    private float pressure;
    
    @JsonProperty("co2_level")
    private float co2Level;
    
    @JsonProperty("noise_level")
    private float noiseLevel;
    
    @JsonProperty("light_level")
    private float lightLevel;
    
    @JsonProperty("motion_detected")
    private int motionDetected;  // 0 or 1
    
    // Device metrics
    @JsonProperty("battery_level")
    private float batteryLevel;
    
    @JsonProperty("signal_strength")
    private float signalStrength;
    
    @JsonProperty("memory_usage")
    private float memoryUsage;
    
    @JsonProperty("cpu_usage")
    private float cpuUsage;
    
    // Status and alerts (1=online, 2=offline, 3=maintenance, 4=error)
    private int status;
    
    @JsonProperty("error_count")
    private long errorCount;
    
    // Network metrics
    @JsonProperty("packets_sent")
    private long packetsSent;
    
    @JsonProperty("packets_received")
    private long packetsReceived;
    
    @JsonProperty("bytes_sent")
    private long bytesSent;
    
    @JsonProperty("bytes_received")
    private long bytesReceived;

    // Default constructor for Jackson
    public SensorData() {}

    // Getters and Setters
    public String getDeviceId() { return deviceId; }
    public void setDeviceId(String deviceId) { this.deviceId = deviceId; }
    
    public String getDeviceType() { return deviceType; }
    public void setDeviceType(String deviceType) { this.deviceType = deviceType; }
    
    public String getCustomerId() { return customerId; }
    public void setCustomerId(String customerId) { this.customerId = customerId; }
    
    public String getSiteId() { return siteId; }
    public void setSiteId(String siteId) { this.siteId = siteId; }
    
    public double getLatitude() { return latitude; }
    public void setLatitude(double latitude) { this.latitude = latitude; }
    
    public double getLongitude() { return longitude; }
    public void setLongitude(double longitude) { this.longitude = longitude; }
    
    public float getAltitude() { return altitude; }
    public void setAltitude(float altitude) { this.altitude = altitude; }
    
    public Instant getTime() { return time; }
    public void setTime(Instant time) { this.time = time; }
    
    public float getTemperature() { return temperature; }
    public void setTemperature(float temperature) { this.temperature = temperature; }
    
    public float getHumidity() { return humidity; }
    public void setHumidity(float humidity) { this.humidity = humidity; }
    
    public float getPressure() { return pressure; }
    public void setPressure(float pressure) { this.pressure = pressure; }
    
    public float getCo2Level() { return co2Level; }
    public void setCo2Level(float co2Level) { this.co2Level = co2Level; }
    
    public float getNoiseLevel() { return noiseLevel; }
    public void setNoiseLevel(float noiseLevel) { this.noiseLevel = noiseLevel; }
    
    public float getLightLevel() { return lightLevel; }
    public void setLightLevel(float lightLevel) { this.lightLevel = lightLevel; }
    
    public int getMotionDetected() { return motionDetected; }
    public void setMotionDetected(int motionDetected) { this.motionDetected = motionDetected; }
    
    public float getBatteryLevel() { return batteryLevel; }
    public void setBatteryLevel(float batteryLevel) { this.batteryLevel = batteryLevel; }
    
    public float getSignalStrength() { return signalStrength; }
    public void setSignalStrength(float signalStrength) { this.signalStrength = signalStrength; }
    
    public float getMemoryUsage() { return memoryUsage; }
    public void setMemoryUsage(float memoryUsage) { this.memoryUsage = memoryUsage; }
    
    public float getCpuUsage() { return cpuUsage; }
    public void setCpuUsage(float cpuUsage) { this.cpuUsage = cpuUsage; }
    
    public int getStatus() { return status; }
    public void setStatus(int status) { this.status = status; }
    
    public long getErrorCount() { return errorCount; }
    public void setErrorCount(long errorCount) { this.errorCount = errorCount; }
    
    public long getPacketsSent() { return packetsSent; }
    public void setPacketsSent(long packetsSent) { this.packetsSent = packetsSent; }
    
    public long getPacketsReceived() { return packetsReceived; }
    public void setPacketsReceived(long packetsReceived) { this.packetsReceived = packetsReceived; }
    
    public long getBytesSent() { return bytesSent; }
    public void setBytesSent(long bytesSent) { this.bytesSent = bytesSent; }
    
    public long getBytesReceived() { return bytesReceived; }
    public void setBytesReceived(long bytesReceived) { this.bytesReceived = bytesReceived; }
}

