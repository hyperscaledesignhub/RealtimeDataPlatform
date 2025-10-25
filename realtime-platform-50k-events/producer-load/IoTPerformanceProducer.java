/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */
package org.apache.pulsar.testclient;

import static java.util.concurrent.TimeUnit.NANOSECONDS;
import static org.apache.commons.lang3.StringUtils.isNotBlank;
import static org.apache.pulsar.client.impl.conf.ProducerConfigurationData.DEFAULT_BATCHING_MAX_MESSAGES;
import static org.apache.pulsar.client.impl.conf.ProducerConfigurationData.DEFAULT_MAX_PENDING_MESSAGES;
import static org.apache.pulsar.client.impl.conf.ProducerConfigurationData.DEFAULT_MAX_PENDING_MESSAGES_ACROSS_PARTITIONS;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.ObjectWriter;
import com.fasterxml.jackson.datatype.jsr310.JavaTimeModule;
import com.google.common.util.concurrent.RateLimiter;
import io.netty.util.concurrent.DefaultThreadFactory;
import java.io.FileOutputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.text.DecimalFormat;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Random;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.ThreadLocalRandom;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.LongAdder;
// AVRO imports
import org.apache.avro.Schema;
import org.apache.avro.generic.GenericData;
import org.apache.avro.generic.GenericRecord;
import org.apache.pulsar.client.api.schema.GenericSchema;
import org.apache.pulsar.client.api.schema.SchemaDefinition;
import org.apache.pulsar.common.schema.SchemaInfo;
import org.apache.pulsar.common.schema.SchemaType;
import org.HdrHistogram.Histogram;
import org.HdrHistogram.HistogramLogWriter;
import org.HdrHistogram.Recorder;
import org.apache.pulsar.client.admin.PulsarAdmin;
import org.apache.pulsar.client.admin.PulsarAdminBuilder;
import org.apache.pulsar.client.admin.PulsarAdminException;
import org.apache.pulsar.client.api.ClientBuilder;
import org.apache.pulsar.client.api.CompressionType;
import org.apache.pulsar.client.api.MessageRoutingMode;
import org.apache.pulsar.client.api.Producer;
import org.apache.pulsar.client.api.ProducerAccessMode;
import org.apache.pulsar.client.api.ProducerBuilder;
import org.apache.pulsar.client.api.PulsarClient;
import org.apache.pulsar.client.api.PulsarClientException;
import org.apache.pulsar.client.api.TypedMessageBuilder;
import org.apache.pulsar.common.partition.PartitionedTopicMetadata;
import org.apache.pulsar.common.util.FutureUtil;
import org.apache.pulsar.testclient.utils.PaddingDecimalFormat;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import picocli.CommandLine;
import picocli.CommandLine.Command;
import picocli.CommandLine.Option;

/**
 * Enhanced IoT Performance Producer for Flink Benchmark
 * Generates SensorData messages compatible with Flink benchmark pipeline
 * Supports device ID range control and distributed message rate
 */
@Command(name = "iot-produce", description = "Test IoT sensor data producer performance with device ID range control.")
public class IoTPerformanceProducer extends PerformanceTopicListArguments {
    
    // IoT Sensor Data Model - OPTIMIZED INTEGER SCHEMA (NO LOCATION FIELDS)
    public static class SensorData {
        @com.fasterxml.jackson.annotation.JsonProperty("sensorId")
        private int sensorId;
        
        @com.fasterxml.jackson.annotation.JsonProperty("sensorType")
        private int sensorType;
        
        @com.fasterxml.jackson.annotation.JsonProperty("temperature")
        private double temperature;
        
        @com.fasterxml.jackson.annotation.JsonProperty("humidity")
        private double humidity;
        
        @com.fasterxml.jackson.annotation.JsonProperty("pressure")
        private double pressure;
        
        @com.fasterxml.jackson.annotation.JsonProperty("batteryLevel")
        private double batteryLevel;
        
        @com.fasterxml.jackson.annotation.JsonProperty("status")
        private int status;
        
        @com.fasterxml.jackson.annotation.JsonProperty("timestamp")
        private Instant timestamp;


        // Constructors
        public SensorData() {
        }

        // Getters and Setters
        public int getSensorId() {
            return sensorId;
        }

        public void setSensorId(int sensorId) {
            this.sensorId = sensorId;
        }

        public int getSensorType() {
            return sensorType;
        }

        public void setSensorType(int sensorType) {
            this.sensorType = sensorType;
        }

        public double getTemperature() {
            return temperature;
        }

        public void setTemperature(double temperature) {
            this.temperature = temperature;
        }

        public double getHumidity() {
            return humidity;
        }

        public void setHumidity(double humidity) {
            this.humidity = humidity;
        }

        public double getPressure() {
            return pressure;
        }

        public void setPressure(double pressure) {
            this.pressure = pressure;
        }

        public double getBatteryLevel() {
            return batteryLevel;
        }

        public void setBatteryLevel(double batteryLevel) {
            this.batteryLevel = batteryLevel;
        }

        public int getStatus() {
            return status;
        }

        public void setStatus(int status) {
            this.status = status;
        }

        public Instant getTimestamp() {
            return timestamp;
        }

        public void setTimestamp(Instant timestamp) {
            this.timestamp = timestamp;
        }
    }

    private static final LongAdder messagesSent = new LongAdder();
    private static final LongAdder messagesFailed = new LongAdder();
    private static final LongAdder bytesSent = new LongAdder();
    private static final LongAdder totalMessagesSent = new LongAdder();
    private static final LongAdder totalBytesSent = new LongAdder();
    private static final Recorder recorder = new Recorder(TimeUnit.SECONDS.toMicros(120000), 5);
    private static final Recorder cumulativeRecorder = new Recorder(TimeUnit.SECONDS.toMicros(120000), 5);

    // Device ID Range Control
    @Option(names = { "--device-id-min" }, description = "Minimum device ID in range")
    public int deviceIdMin = 1;

    @Option(names = { "--device-id-max" }, description = "Maximum device ID in range")
    public int deviceIdMax = 1000;

    @Option(names = { "--device-prefix" }, description = "Device ID prefix")
    public String devicePrefix = "dev";

    // IoT-specific configuration
    @Option(names = { "--num-customers" }, description = "Number of customer IDs to generate")
    public int numCustomers = 1000;

    @Option(names = { "--num-sites" }, description = "Number of site IDs to generate")
    public int numSites = 100;

    @Option(names = { "--device-types" }, description = "Comma-separated list of device types")
    public String deviceTypes = "temperature_sensor,humidity_sensor,pressure_sensor,"
            + "motion_sensor,light_sensor,co2_sensor,noise_sensor,multisensor";

    // Standard performance options (inherited from PerformanceTopicListArguments)
    @Option(names = { "-threads", "--num-test-threads" }, description = "Number of test threads",
            converter = PositiveNumberParameterConvert.class
    )
    public int numTestThreads = 1;

    @Option(names = { "-r", "--rate" }, description = "Publish rate msg/s across topics")
    public int msgRate = 100;

    @Option(names = { "-n", "--num-producers" }, description = "Number of producers (per topic)",
            converter = PositiveNumberParameterConvert.class
    )
    public int numProducers = 1;

    @Option(names = { "-m", "--num-messages" }, 
            description = "Number of messages to publish in total. If <= 0, it will keep publishing")
    public long numMessages = 0;

    @Option(names = { "-time", "--test-duration" }, 
            description = "Test duration in secs. If <= 0, it will keep publishing")
    public long testTime = 0;

    @Option(names = { "-z", "--compression" }, description = "Compress messages payload")
    public CompressionType compression = CompressionType.LZ4;

    @Option(names = { "-b", "--batch-time-window" }, description = "Batch messages in 'x' ms window (Default: 1ms)")
    public double batchTimeMillis = 1.0;

    @Option(names = { "-db", "--disable-batching" }, description = "Disable batching if true")
    public boolean disableBatching;

    @Option(names = { "-bm", "--batch-max-messages" }, description = "Maximum number of messages per batch")
    public int batchMaxMessages = DEFAULT_BATCHING_MAX_MESSAGES;

    @Option(names = { "-bb", "--batch-max-bytes" }, description = "Maximum number of bytes per batch")
    public int batchMaxBytes = 4 * 1024 * 1024;

    @Option(names = { "--warmup-time" }, description = "Warm-up time in seconds (Default: 1 sec)")
    public double warmupTimeSeconds = 1.0;

    @Option(names = { "-o", "--max-outstanding" }, description = "Max number of outstanding messages")
    public int maxOutstanding = DEFAULT_MAX_PENDING_MESSAGES;

    @Option(names = { "-p", "--max-outstanding-across-partitions" }, 
            description = "Max number of outstanding messages across partitions")
    public int maxPendingMessagesAcrossPartitions = DEFAULT_MAX_PENDING_MESSAGES_ACROSS_PARTITIONS;

    @Option(names = { "-np", "--partitions" }, 
            description = "Create partitioned topics with the given number of partitions, "
                    + "set 0 to not try to create the topic")
    public Integer partitions = null;

    @Option(names = { "-au", "--admin-url" }, description = "Pulsar Admin URL", descriptionKey = "webServiceUrl")
    public String adminURL;

    @Option(names = { "-pn", "--producer-name" }, description = "Producer Name")
    public String producerName = null;

    @Option(names = { "--separator" }, description = "Separator between the topic and topic number")
    public String separator = "-";

    @Option(names = { "--send-timeout" }, 
            description = "Set the sendTimeout value default 0 to keep compatibility with previous version of pulsar-perf")
    public int sendTimeout = 0;

    @Option(names = { "-ch", "--chunking" }, 
            description = "Should split the message and publish in chunks if message size is larger than allowed max size")
    private boolean chunkingAllowed = false;

    @Option(names = { "-set", "--set-event-time" }, description = "Set the eventTime on messages")
    public boolean setEventTime = false;

    @Option(names = { "-ef", "--exit-on-failure" }, description = "Exit from the process on publish failure (default: disable)")
    public boolean exitOnFailure = false;

    @Option(names = { "-mk", "--message-key-generation-mode" }, 
            description = "The generation mode of message key, valid options are: [autoIncrement, random]", 
            descriptionKey = "messageKeyGenerationMode")
    public String messageKeyGenerationMode = null;

    @Option(names = { "-am", "--access-mode" }, description = "Producer access mode")
    public ProducerAccessMode producerAccessMode = ProducerAccessMode.Shared;

    @Option(names = { "--histogram-file" }, description = "HdrHistogram output file")
    public String histogramFile = null;

    // AVRO Schema Options
    @Option(names = { "--use-avro" }, description = "Use AVRO schema instead of JSON")
    public boolean useAvroSchema = false;

    @Option(names = { "--schema-file" }, description = "Path to AVRO schema file (default: built-in SensorData schema)")
    public String schemaFilePath = null;

    @Option(names = { "--schema-registry-url" }, description = "Schema registry URL for AVRO schema management")
    public String schemaRegistryUrl = null;

    // Device type array
    private String[] deviceTypeArray;
    private ObjectMapper objectMapper;
    private Schema avroSchema;
    private org.apache.pulsar.client.api.schema.GenericSchema<org.apache.pulsar.client.api.schema.GenericRecord> genericSchema;

    @Override
    public void run() throws Exception {
        // Validate device ID range
        if (deviceIdMin >= deviceIdMax) {
            throw new IllegalArgumentException("device-id-min must be less than device-id-max");
        }

        // Parse device types
        deviceTypeArray = deviceTypes.split(",");
        objectMapper = new ObjectMapper().registerModule(new JavaTimeModule());

        // Initialize AVRO schema if requested
        if (useAvroSchema) {
            initializeAvroSchema();
        }

        // Print startup info
        System.out.println("🔧 IoT Performance Producer Configuration:");
        System.out.println("   📡 Service URL: " + serviceURL);
        System.out.println("   📊 Message Rate: " + msgRate + " msg/s");
        System.out.println("   🔢 Device ID Range: " + deviceIdMin + " to " + deviceIdMax);
        System.out.println("   🏷️  Device Prefix: " + devicePrefix);
        System.out.println("   📱 Device Types: " + deviceTypes);
        System.out.println("   👥 Customers: " + numCustomers + ", Sites: " + numSites);
        System.out.println("   📈 Test Duration: " + testTime + "s, Messages: " + numMessages);
        System.out.println("   📊 Stats Interval: " + statsIntervalSeconds + "s");
        System.out.println("   📋 Schema Type: " + (useAvroSchema ? "AVRO" : "JSON"));
        if (useAvroSchema) {
            System.out.println("   📄 Schema File: " + (schemaFilePath != null ? schemaFilePath : "built-in SensorData.avsc"));
            System.out.println("   🏢 Schema Registry: " + (schemaRegistryUrl != null ? schemaRegistryUrl : "none"));
        }
        System.out.println("");

        // Dump config variables
        PerfClientUtils.printJVMInformation(log);
        ObjectMapper m = new ObjectMapper();
        ObjectWriter w = m.writerWithDefaultPrettyPrinter();
        log.info("Starting IoT Performance Producer with config: {}", w.writeValueAsString(this));

        long start = System.nanoTime();

        ExecutorService executor = Executors
                .newCachedThreadPool(new DefaultThreadFactory("pulsar-iot-perf-producer-exec"));
        Thread shutdownHookThread = PerfClientUtils.addShutdownHook(() -> {
            executorShutdownNow(executor);
            printAggregatedThroughput(start);
            printAggregatedStats();
        });

        // Create partitioned topics if needed
        if (this.partitions != null) {
            final PulsarAdminBuilder adminBuilder = PerfClientUtils
                    .createAdminBuilderFromArguments(this, this.adminURL);

            try (PulsarAdmin adminClient = adminBuilder.build()) {
                for (String topic : this.topics) {
                    log.info("Creating partitioned topic {} with {} partitions", topic, this.partitions);
                    try {
                        adminClient.topics().createPartitionedTopic(topic, this.partitions);
                    } catch (PulsarAdminException.ConflictException alreadyExists) {
                        if (log.isDebugEnabled()) {
                            log.debug("Topic {} already exists: {}", topic, alreadyExists);
                        }
                        PartitionedTopicMetadata partitionedTopicMetadata = adminClient.topics()
                                .getPartitionedTopicMetadata(topic);
                        if (partitionedTopicMetadata.partitions != this.partitions) {
                            log.error("Topic {} already exists but it has a wrong number of partitions: {}, expecting {}",
                                    topic, partitionedTopicMetadata.partitions, this.partitions);
                            PerfClientUtils.exit(1);
                        }
                    }
                }
            }
        }

        CountDownLatch doneLatch = new CountDownLatch(this.numTestThreads);

        final long numMessagesPerThread = this.numMessages / this.numTestThreads;
        final int msgRatePerThread = this.msgRate / this.numTestThreads;

        for (int i = 0; i < this.numTestThreads; i++) {
            final int threadIdx = i;
            executor.submit(() -> {
                log.info("Started IoT performance test thread {}", threadIdx);
                runIoTProducer(
                        threadIdx,
                        this,
                        numMessagesPerThread,
                        msgRatePerThread,
                        doneLatch
                );
            });
        }

        // Print report stats
        long oldTime = System.nanoTime();

        Histogram reportHistogram = null;
        HistogramLogWriter histogramLogWriter = null;

        if (this.histogramFile != null) {
            String statsFileName = this.histogramFile;
            log.info("Dumping latency stats to {}", statsFileName);

            PrintStream histogramLog = new PrintStream(new FileOutputStream(statsFileName), false);
            histogramLogWriter = new HistogramLogWriter(histogramLog);

            // Some log header bits
            histogramLogWriter.outputLogFormatVersion();
            histogramLogWriter.outputLegend();
        }

        while (!Thread.currentThread().isInterrupted()) {
            try {
                Thread.sleep(10000);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                break;
            }

            if (doneLatch.getCount() <= 0) {
                break;
            }

            long now = System.nanoTime();
            double elapsed = (now - oldTime) / 1e9;
            long total = totalMessagesSent.sum();
            double rate = messagesSent.sumThenReset() / elapsed;
            double failureRate = messagesFailed.sumThenReset() / elapsed;
            double throughput = bytesSent.sumThenReset() / elapsed / 1024 / 1024 * 8;

            reportHistogram = recorder.getIntervalHistogram(reportHistogram);

            log.info(
                    "Throughput produced: {} msg --- {} msg/s --- {} Mbit/s  --- failure {} msg/s "
                            + "--- Latency: mean: {} ms - med: {} - 95pct: {} - 99pct: {} - 99.9pct: {} - 99.99pct: {} - Max: {}",
                    INTFORMAT.format(total),
                    THROUGHPUTFORMAT.format(rate), THROUGHPUTFORMAT.format(throughput),
                    THROUGHPUTFORMAT.format(failureRate),
                    DEC.format(reportHistogram.getMean() / 1000.0),
                    DEC.format(reportHistogram.getValueAtPercentile(50) / 1000.0),
                    DEC.format(reportHistogram.getValueAtPercentile(95) / 1000.0),
                    DEC.format(reportHistogram.getValueAtPercentile(99) / 1000.0),
                    DEC.format(reportHistogram.getValueAtPercentile(99.9) / 1000.0),
                    DEC.format(reportHistogram.getValueAtPercentile(99.99) / 1000.0),
                    DEC.format(reportHistogram.getMaxValue() / 1000.0));

            if (histogramLogWriter != null) {
                histogramLogWriter.outputIntervalHistogram(reportHistogram);
            }

            reportHistogram.reset();
            oldTime = now;
        }

        PerfClientUtils.removeAndRunShutdownHook(shutdownHookThread);
    }

    public IoTPerformanceProducer() {
        super("iot-produce");
    }

    /**
     * Initialize AVRO schema from file or use built-in schema
     */
    private void initializeAvroSchema() throws Exception {
        try {
            if (schemaFilePath != null) {
                // Load schema from file
                avroSchema = new Schema.Parser().parse(new java.io.File(schemaFilePath));
                log.info("Loaded AVRO schema from file: {}", schemaFilePath);
            } else {
                // Use built-in schema from resources
                try (java.io.InputStream schemaStream = getClass().getResourceAsStream("/avro/SensorData.avsc")) {
                    if (schemaStream == null) {
                        throw new RuntimeException("Built-in AVRO schema file not found: /avro/SensorData.avsc");
                    }
                    avroSchema = new Schema.Parser().parse(schemaStream);
                    log.info("Loaded built-in AVRO schema: SensorData.avsc");
                }
            }

            // Create generic schema for Pulsar
            SchemaInfo schemaInfo = SchemaInfo.builder()
                    .schema(avroSchema.toString().getBytes(StandardCharsets.UTF_8))
                    .type(SchemaType.AVRO)
                    .name("SensorData")
                    .build();
            genericSchema = org.apache.pulsar.client.api.Schema.generic(schemaInfo);

            log.info("AVRO schema initialized successfully");
        } catch (Exception e) {
            log.error("Failed to initialize AVRO schema", e);
            throw new RuntimeException("AVRO schema initialization failed", e);
        }
    }

    private static void executorShutdownNow(ExecutorService executor) {
        executor.shutdownNow();
        try {
            if (!executor.awaitTermination(10, TimeUnit.SECONDS)) {
                log.warn("Failed to terminate executor within timeout. The following are stack"
                        + " traces of still running threads.");
            }
        } catch (InterruptedException e) {
            log.warn("Shutdown of thread pool was interrupted");
            Thread.currentThread().interrupt();
        }
    }

    ProducerBuilder<?> createProducerBuilder(PulsarClient client, int producerId) {
        ProducerBuilder<?> producerBuilder;
        
        if (useAvroSchema) {
            // Create AVRO producer
            producerBuilder = client.newProducer(genericSchema) //
                    .sendTimeout(this.sendTimeout, TimeUnit.SECONDS) //
                    .compressionType(this.compression) //
                    .maxPendingMessages(this.maxOutstanding) //
                    .accessMode(this.producerAccessMode)
                    // enable round robin message routing if it is a partitioned topic
                    .messageRoutingMode(MessageRoutingMode.RoundRobinPartition);
        } else {
            // Create byte array producer (JSON)
            producerBuilder = client.newProducer() //
                    .sendTimeout(this.sendTimeout, TimeUnit.SECONDS) //
                    .compressionType(this.compression) //
                    .maxPendingMessages(this.maxOutstanding) //
                    .accessMode(this.producerAccessMode)
                    // enable round robin message routing if it is a partitioned topic
                    .messageRoutingMode(MessageRoutingMode.RoundRobinPartition);
        }
        if (this.maxPendingMessagesAcrossPartitions > 0) {
            producerBuilder.maxPendingMessagesAcrossPartitions(
                    this.maxPendingMessagesAcrossPartitions);
        }

        if (this.producerName != null) {
            String producerName = String.format("%s%s%d", this.producerName, 
                    this.separator, producerId);
            producerBuilder.producerName(producerName);
        }

        if (this.disableBatching || (this.batchTimeMillis <= 0.0 && this.batchMaxMessages <= 0)) {
            producerBuilder.enableBatching(false);
        } else {
            long batchTimeUsec = (long) (this.batchTimeMillis * 1000);
            producerBuilder.batchingMaxPublishDelay(batchTimeUsec, TimeUnit.MICROSECONDS)
                    .enableBatching(true);
        }
        if (this.batchMaxMessages > 0) {
            producerBuilder.batchingMaxMessages(this.batchMaxMessages);
        }
        if (this.batchMaxBytes > 0) {
            producerBuilder.batchingMaxBytes(this.batchMaxBytes);
        }

        // Block if queue is full else we will start seeing errors in sendAsync
        producerBuilder.blockIfQueueFull(true);

        return producerBuilder;
    }

    private void runIoTProducer(int producerId,
                               IoTPerformanceProducer arguments,
                               long numMessages,
                               int msgRate,
                               CountDownLatch doneLatch) {
        PulsarClient client = null;
        boolean produceEnough = false;
        try {
            List<Future<?>> futures = new ArrayList<>();

            ClientBuilder clientBuilder = PerfClientUtils.createClientBuilderFromArguments(arguments);
            client = clientBuilder.build();

            ProducerBuilder<?> producerBuilder = createProducerBuilder(client, producerId);

            for (int i = 0; i < this.numTopics; i++) {
                String topic = this.topics.get(i);
                log.info("Adding {} publishers on topic {}", this.numProducers, topic);

                for (int j = 0; j < this.numProducers; j++) {
                    ProducerBuilder<?> prodBuilder = producerBuilder.clone().topic(topic);
                    if (this.chunkingAllowed) {
                        prodBuilder.enableChunking(true);
                        prodBuilder.enableBatching(false);
                    }
                    futures.add(prodBuilder.createAsync());
                }
            }

            final List<Producer<?>> producers = new ArrayList<>(futures.size());
            for (Future<?> future : futures) {
                producers.add((Producer<?>) future.get());
            }
            Collections.shuffle(producers);

            log.info("Created {} producers", producers.size());

            RateLimiter rateLimiter = RateLimiter.create(msgRate);

            long startTime = System.nanoTime();
            long warmupEndTime = startTime + (long) (this.warmupTimeSeconds * 1e9);
            long testEndTime = startTime + (long) (this.testTime * 1e9);
            MessageKeyGenerationMode msgKeyMode = null;
            if (isNotBlank(this.messageKeyGenerationMode)) {
                try {
                    msgKeyMode = MessageKeyGenerationMode.valueOf(this.messageKeyGenerationMode);
                } catch (IllegalArgumentException e) {
                    throw new IllegalArgumentException("messageKeyGenerationMode only support [autoIncrement, random]");
                }
            }

            // Send messages on all topics/producers
            AtomicLong totalSent = new AtomicLong(0);
            Random random = new Random();

            while (!Thread.currentThread().isInterrupted()) {
                if (produceEnough) {
                    break;
                }
                for (Producer<?> producer : producers) {
                    if (this.testTime > 0) {
                        if (System.nanoTime() > testEndTime) {
                            log.info("------------- DONE (reached the maximum duration: [{} seconds] of production) --------------", this.testTime);
                            doneLatch.countDown();
                            produceEnough = true;
                            break;
                        }
                    }

                    if (numMessages > 0) {
                        if (totalSent.get() >= numMessages) {
                            log.info("------------- DONE (reached the maximum number: {} of production) --------------", numMessages);
                            doneLatch.countDown();
                            produceEnough = true;
                            break;
                        }
                    }
                    rateLimiter.acquire();
                    final long sendTime = System.nanoTime();

                    // Generate IoT Sensor Data
                    SensorData sensorData = generateSensorData(random);
                    
                    int payloadSize;
                    TypedMessageBuilder<?> messageBuilder;
                    
                    if (useAvroSchema) {
                        // Create AVRO GenericRecord
                        org.apache.pulsar.client.api.schema.GenericRecord pulsarRecord = createPulsarGenericRecord(sensorData);
                        @SuppressWarnings("unchecked")
                        Producer<org.apache.pulsar.client.api.schema.GenericRecord> avroProducer = (Producer<org.apache.pulsar.client.api.schema.GenericRecord>) producer;
                        messageBuilder = avroProducer.newMessage().value(pulsarRecord);
                        payloadSize = pulsarRecord.toString().length(); // Approximate size
                    } else {
                        // Create JSON message
                        String jsonData = objectMapper.writeValueAsString(sensorData);
                        byte[] payloadData = jsonData.getBytes(StandardCharsets.UTF_8);
                        @SuppressWarnings("unchecked")
                        Producer<byte[]> byteProducer = (Producer<byte[]>) producer;
                        messageBuilder = byteProducer.newMessage().value(payloadData);
                        payloadSize = payloadData.length;
                    }

                    if (this.setEventTime) {
                        messageBuilder.eventTime(System.currentTimeMillis());
                    }

                    // Generate message key
                    if (msgKeyMode == MessageKeyGenerationMode.random) {
                        messageBuilder.key(String.valueOf(ThreadLocalRandom.current().nextInt()));
                    } else if (msgKeyMode == MessageKeyGenerationMode.autoIncrement) {
                        messageBuilder.key(String.valueOf(totalSent.get()));
                    } else {
                        // Default: use sensor ID as key (convert int to string)
                        messageBuilder.key(String.valueOf(sensorData.getSensorId()));
                    }

                    messageBuilder.sendAsync().thenRun(() -> {
                        bytesSent.add(payloadSize);
                        messagesSent.increment();
                        totalSent.incrementAndGet();
                        totalMessagesSent.increment();
                        totalBytesSent.add(payloadSize);

                        long now = System.nanoTime();
                        if (now > warmupEndTime) {
                            long latencyMicros = NANOSECONDS.toMicros(now - sendTime);
                            recorder.recordValue(latencyMicros);
                            cumulativeRecorder.recordValue(latencyMicros);
                        }
                    }).exceptionally(ex -> {
                        Throwable cause = FutureUtil.unwrapCompletionException(ex);
                        if (cause instanceof ArrayIndexOutOfBoundsException) {
                            return null;
                        }
                        if (cause instanceof PulsarClientException.AlreadyClosedException) {
                            return null;
                        }
                        if (PerfClientUtils.hasInterruptedException(ex)) {
                            Thread.currentThread().interrupt();
                            return null;
                        }
                        log.warn("Write message error with exception", ex);
                        messagesFailed.increment();
                        if (this.exitOnFailure) {
                            PerfClientUtils.exit(1);
                        }
                        return null;
                    });
                }
            }
        } catch (Throwable t) {
            if (PerfClientUtils.hasInterruptedException(t)) {
                Thread.currentThread().interrupt();
            } else {
                log.error("Got error", t);
            }
        } finally {
            if (!produceEnough) {
                doneLatch.countDown();
            }
            PerfClientUtils.closeClient(client);
        }
    }

    private SensorData generateSensorData(Random random) {
        SensorData data = new SensorData();

        // Sensor ID as integer (matching Flink's integer sensorId field)
        int deviceNum = deviceIdMin + random.nextInt(deviceIdMax - deviceIdMin + 1);
        data.setSensorId(deviceNum);

        // Sensor type as integer (1-8 for different sensor types)
        int sensorTypeNum = random.nextInt(8) + 1; // 1-8
        data.setSensorType(sensorTypeNum);

        // Timestamp (matching Flink's timestamp field)
        data.setTimestamp(Instant.now());

        // Sensor readings (realistic ranges) - matching Flink's expected fields
        data.setTemperature(10.0 + (random.nextDouble() * 30.0));  // 10-40°C
        data.setHumidity(20.0 + (random.nextDouble() * 60.0));     // 20-80%
        data.setPressure(980.0 + (random.nextDouble() * 50.0));    // 980-1030 hPa

        // Battery level
        data.setBatteryLevel(20.0 + (random.nextDouble() * 80.0));  // 20-100%

        // Status as integer (1=online, 2=offline, 3=maintenance, 4=error)
        int statusRoll = random.nextInt(100);
        int statusInt;
        if (statusRoll < 85) {
            statusInt = 1; // online
        } else if (statusRoll < 90) {
            statusInt = 2; // offline
        } else if (statusRoll < 95) {
            statusInt = 3; // maintenance
        } else {
            statusInt = 4; // error
        }
        data.setStatus(statusInt);

        return data;
    }


    /**
     * Create Pulsar GenericRecord from SensorData - OPTIMIZED INTEGER SCHEMA
     */
    private org.apache.pulsar.client.api.schema.GenericRecord createPulsarGenericRecord(SensorData sensorData) {
        // Build the main record with integer fields only (no location/metadata)
        org.apache.pulsar.client.api.schema.GenericRecord record = genericSchema.newRecordBuilder()
                .set("sensorId", sensorData.getSensorId())
                .set("sensorType", sensorData.getSensorType())
                .set("temperature", sensorData.getTemperature())
                .set("humidity", sensorData.getHumidity())
                .set("pressure", sensorData.getPressure())
                .set("batteryLevel", sensorData.getBatteryLevel())
                .set("status", sensorData.getStatus())
                .set("timestamp", sensorData.getTimestamp().toEpochMilli())
                .build();

        return record;
    }

    private void printAggregatedThroughput(long start) {
        double elapsed = (System.nanoTime() - start) / 1e9;
        double rate = totalMessagesSent.sum() / elapsed;
        double throughput = totalBytesSent.sum() / elapsed / 1024 / 1024 * 8;

        log.info(
            "Aggregated throughput stats --- {} records sent --- {} msg/s --- {} Mbit/s ",
            totalMessagesSent.sum(),
            TOTALFORMAT.format(rate),
            TOTALFORMAT.format(throughput));
    }

    private static void printAggregatedStats() {
        Histogram reportHistogram = cumulativeRecorder.getIntervalHistogram();

        log.info(
                "Aggregated latency stats --- Latency: mean: {} ms - med: {} - 95pct: {} - 99pct: {} - 99.9pct: {} "
                        + "- 99.99pct: {} - 99.999pct: {} - Max: {}",
                DEC.format(reportHistogram.getMean() / 1000.0),
                DEC.format(reportHistogram.getValueAtPercentile(50) / 1000.0),
                DEC.format(reportHistogram.getValueAtPercentile(95) / 1000.0),
                DEC.format(reportHistogram.getValueAtPercentile(99) / 1000.0),
                DEC.format(reportHistogram.getValueAtPercentile(99.9) / 1000.0),
                DEC.format(reportHistogram.getValueAtPercentile(99.99) / 1000.0),
                DEC.format(reportHistogram.getValueAtPercentile(99.999) / 1000.0),
                DEC.format(reportHistogram.getMaxValue() / 1000.0));
    }

    static final DecimalFormat THROUGHPUTFORMAT = new PaddingDecimalFormat("0.0", 8);
    static final DecimalFormat DEC = new PaddingDecimalFormat("0.000", 7);
    static final DecimalFormat INTFORMAT = new PaddingDecimalFormat("0", 7);
    static final DecimalFormat TOTALFORMAT = new DecimalFormat("0.000");
    private static final Logger log = LoggerFactory.getLogger(IoTPerformanceProducer.class);

    public enum MessageKeyGenerationMode {
        autoIncrement, random
    }

    public static void main(String[] args) {
        System.out.println("🚀 Starting IoT Performance Producer...");
        System.out.println("📊 Args: " + java.util.Arrays.toString(args));
        System.out.println("📈 Performance metrics will be displayed during execution...");
        CommandLine cmd = new CommandLine(new IoTPerformanceProducer());
        int exitCode = cmd.execute(args);
        System.exit(exitCode);
    }
}
