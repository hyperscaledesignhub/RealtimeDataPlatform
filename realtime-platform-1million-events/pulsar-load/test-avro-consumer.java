import org.apache.pulsar.client.api.*;
import org.apache.pulsar.client.api.schema.GenericRecord;
import org.apache.pulsar.client.api.schema.GenericSchema;
import org.apache.pulsar.common.schema.SchemaInfo;
import org.apache.pulsar.common.schema.SchemaType;

public class TestAvroConsumer {
    public static void main(String[] args) throws Exception {
        String serviceUrl = "pulsar://localhost:6650";
        String topic = "persistent://public/default/test-avro-topic";
        String subscription = "test-avro-subscription";

        // Create Pulsar client
        PulsarClient client = PulsarClient.builder()
                .serviceUrl(serviceUrl)
                .build();

        try {
            // Create consumer with AVRO schema
            Consumer<GenericRecord> consumer = client.newConsumer()
                    .topic(topic)
                    .subscriptionName(subscription)
                    .subscriptionType(SubscriptionType.Exclusive)
                    .subscribe();

            System.out.println("🚀 Started AVRO consumer for topic: " + topic);
            System.out.println("📡 Waiting for messages...");

            // Consume messages
            while (true) {
                Message<GenericRecord> msg = consumer.receive();
                try {
                    GenericRecord record = msg.getValue();
                    System.out.println("📨 Received AVRO message:");
                    System.out.println("   Sensor ID: " + record.get("sensorId"));
                    System.out.println("   Sensor Type: " + record.get("sensorType"));
                    System.out.println("   Location: " + record.get("location"));
                    System.out.println("   Temperature: " + record.get("temperature"));
                    System.out.println("   Humidity: " + record.get("humidity"));
                    System.out.println("   Pressure: " + record.get("pressure"));
                    System.out.println("   Timestamp: " + record.get("timestamp"));
                    System.out.println("   Raw record: " + record.toString());
                    System.out.println("---");
                    
                    consumer.acknowledge(msg);
                } catch (Exception e) {
                    System.err.println("❌ Error processing message: " + e.getMessage());
                    consumer.negativeAcknowledge(msg);
                }
            }
        } finally {
            client.close();
        }
    }
}
