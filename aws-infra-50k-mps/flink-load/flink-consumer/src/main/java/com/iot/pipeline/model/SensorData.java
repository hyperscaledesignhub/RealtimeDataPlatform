package com.iot.pipeline.model;

import java.io.Serializable;
import java.time.Instant;

public class SensorData implements Serializable {
    private String sensorId;
    private String sensorType;
    private String location;
    private double temperature;
    private double humidity;
    private double pressure;
    private double batteryLevel;
    private String status;
    private Instant timestamp;
    private MetaData metadata;

    public static class MetaData implements Serializable {
        private String manufacturer;
        private String model;
        private String firmwareVersion;
        private double latitude;
        private double longitude;

        public MetaData() {}

        public MetaData(String manufacturer, String model, String firmwareVersion, 
                       double latitude, double longitude) {
            this.manufacturer = manufacturer;
            this.model = model;
            this.firmwareVersion = firmwareVersion;
            this.latitude = latitude;
            this.longitude = longitude;
        }

        public String getManufacturer() { return manufacturer; }
        public void setManufacturer(String manufacturer) { this.manufacturer = manufacturer; }
        public String getModel() { return model; }
        public void setModel(String model) { this.model = model; }
        public String getFirmwareVersion() { return firmwareVersion; }
        public void setFirmwareVersion(String firmwareVersion) { this.firmwareVersion = firmwareVersion; }
        public double getLatitude() { return latitude; }
        public void setLatitude(double latitude) { this.latitude = latitude; }
        public double getLongitude() { return longitude; }
        public void setLongitude(double longitude) { this.longitude = longitude; }
    }

    public SensorData() {}

    public SensorData(String sensorId, String sensorType, String location, 
                     double temperature, double humidity, double pressure, 
                     double batteryLevel, String status, MetaData metadata) {
        this.sensorId = sensorId;
        this.sensorType = sensorType;
        this.location = location;
        this.temperature = temperature;
        this.humidity = humidity;
        this.pressure = pressure;
        this.batteryLevel = batteryLevel;
        this.status = status;
        this.timestamp = Instant.now();
        this.metadata = metadata;
    }

    public String getSensorId() { return sensorId; }
    public void setSensorId(String sensorId) { this.sensorId = sensorId; }
    public String getSensorType() { return sensorType; }
    public void setSensorType(String sensorType) { this.sensorType = sensorType; }
    public String getLocation() { return location; }
    public void setLocation(String location) { this.location = location; }
    public double getTemperature() { return temperature; }
    public void setTemperature(double temperature) { this.temperature = temperature; }
    public double getHumidity() { return humidity; }
    public void setHumidity(double humidity) { this.humidity = humidity; }
    public double getPressure() { return pressure; }
    public void setPressure(double pressure) { this.pressure = pressure; }
    public double getBatteryLevel() { return batteryLevel; }
    public void setBatteryLevel(double batteryLevel) { this.batteryLevel = batteryLevel; }
    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }
    public Instant getTimestamp() { return timestamp; }
    public void setTimestamp(Instant timestamp) { this.timestamp = timestamp; }
    public MetaData getMetadata() { return metadata; }
    public void setMetadata(MetaData metadata) { this.metadata = metadata; }
}