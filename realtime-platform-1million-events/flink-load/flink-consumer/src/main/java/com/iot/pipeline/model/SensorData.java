package com.iot.pipeline.model;

import java.io.Serializable;
import java.time.Instant;

public class SensorData implements Serializable {
    private int sensorId;
    private int sensorType;
    private int location;
    private double temperature;
    private double humidity;
    private double pressure;
    private double batteryLevel;
    private int status;
    private Instant timestamp;

    public SensorData() {}

    public SensorData(int sensorId, int sensorType, int location, 
                     double temperature, double humidity, double pressure, 
                     double batteryLevel, int status) {
        this.sensorId = sensorId;
        this.sensorType = sensorType;
        this.location = location;
        this.temperature = temperature;
        this.humidity = humidity;
        this.pressure = pressure;
        this.batteryLevel = batteryLevel;
        this.status = status;
        this.timestamp = Instant.now();
    }

    // Getters
    public int getSensorId() { return sensorId; }
    public int getSensorType() { return sensorType; }
    public int getLocation() { return location; }
    public double getTemperature() { return temperature; }
    public double getHumidity() { return humidity; }
    public double getPressure() { return pressure; }
    public double getBatteryLevel() { return batteryLevel; }
    public int getStatus() { return status; }
    public Instant getTimestamp() { return timestamp; }

    // Setters
    public void setSensorId(int sensorId) { this.sensorId = sensorId; }
    public void setSensorType(int sensorType) { this.sensorType = sensorType; }
    public void setLocation(int location) { this.location = location; }
    public void setTemperature(double temperature) { this.temperature = temperature; }
    public void setHumidity(double humidity) { this.humidity = humidity; }
    public void setPressure(double pressure) { this.pressure = pressure; }
    public void setBatteryLevel(double batteryLevel) { this.batteryLevel = batteryLevel; }
    public void setStatus(int status) { this.status = status; }
    public void setTimestamp(Instant timestamp) { this.timestamp = timestamp; }

    // Helper methods for status checking
    public boolean isActive() { return status == 1; } // 1 = online/active
    public boolean isOffline() { return status == 2; } // 2 = offline
    public boolean isMaintenance() { return status == 3; } // 3 = maintenance
    public boolean isError() { return status == 4; } // 4 = error

    @Override
    public String toString() {
        return String.format("SensorData{sensorId=%d, sensorType=%d, location=%d, temperature=%.2f, humidity=%.2f, pressure=%.2f, batteryLevel=%.2f, status=%d, timestamp=%s}",
                sensorId, sensorType, location, temperature, humidity, pressure, batteryLevel, status, timestamp);
    }
}