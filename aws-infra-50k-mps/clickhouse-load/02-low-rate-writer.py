#!/usr/bin/env python3
"""
Low-Rate Data Writer for ClickHouse
Generates ~10-50 records/sec for testing with minimal resources
"""

import os
import sys
import subprocess
import time
import logging
import threading
from queue import Queue
from datetime import datetime
import random
import signal

# Install required dependencies
def install_dependencies():
    """Install required Python packages"""
    required_packages = ['requests']
    
    for package in required_packages:
        try:
            __import__(package)
            print(f"✅ {package} already installed")
        except ImportError:
            print(f"📦 Installing {package}...")
            subprocess.check_call([sys.executable, '-m', 'pip', 'install', package])
            print(f"✅ {package} installed successfully")

# Install dependencies first
install_dependencies()

import requests

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

class LowRateWriter:
    def __init__(self):
        """Initialize low-rate writer"""
        self.host = os.getenv('CLICKHOUSE_HOST', 'chi-iot-cluster-repl-iot-cluster-0-0-0.clickhouse.svc.cluster.local')
        self.port = int(os.getenv('CLICKHOUSE_PORT', '8123'))
        self.database = os.getenv('CLICKHOUSE_DB', 'benchmark')
        self.user = os.getenv('CLICKHOUSE_USER', 'default')
        self.password = os.getenv('CLICKHOUSE_PASSWORD', '')
        
        # Low rate configuration (10-50 records/sec total)
        self.target_rate = 25  # records per second (total for both tables)
        self.batch_size = 5    # smaller batches for low rate
        
        self.base_url = f"http://{self.host}:{self.port}"
        self.auth_params = {
            'user': self.user,
            'password': self.password,
            'database': self.database
        }
        
        # Generate sample device pool (matching latest-0 cardinality)
        self.devices = [f"device_{i:05d}" for i in range(1, 1001)]  # 1000 devices
        self.hostnames = [f"server_{i:04d}" for i in range(1, 501)]  # 500 hosts
        self.device_types = ['temperature', 'humidity', 'pressure', 'motion', 'air_quality', 'light', 'sound', 'vibration']
        self.customers = [f"customer_{i:04d}" for i in range(1, 101)]  # 100 customers
        self.sites = [f"site_{i:03d}" for i in range(1, 51)]  # 50 sites
        self.regions = ['us-east-1', 'us-west-2', 'eu-west-1', 'eu-central-1', 'ap-south-1']
        self.datacenters = [f"dc-{i:02d}" for i in range(1, 21)]  # 20 datacenters
        self.racks = [f"rack-{i:02d}" for i in range(1, 51)]  # 50 racks
        self.os_types = ['linux', 'ubuntu', 'centos', 'debian', 'rhel']
        self.architectures = ['x86_64', 'arm64', 'aarch64']
        self.teams = [f"team-{i:02d}" for i in range(1, 21)]  # 20 teams
        self.services = ['web-server', 'api-gateway', 'database', 'cache', 'queue-worker', 'auth-service', 'data-processor']
        self.service_versions = ['v1.0', 'v1.1', 'v2.0', 'v2.1', 'v3.0']
        self.service_envs = ['prod', 'staging', 'dev', 'test']
        
        # Metrics
        self.write_queue = Queue(maxsize=100)
        self.total_records = 0
        self.cpu_records = 0
        self.sensor_records = 0
        self.start_time = time.time()
        self.running = True
        
        # Signal handling for graceful shutdown
        signal.signal(signal.SIGTERM, self.handle_shutdown)
        signal.signal(signal.SIGINT, self.handle_shutdown)
        
        logger.info(f"🚀 Low-Rate Writer initialized")
        logger.info(f"📊 Target rate: {self.target_rate} records/sec")
        logger.info(f"🎯 ClickHouse: {self.host}:{self.port}")
        
    def handle_shutdown(self, signum, frame):
        """Handle shutdown gracefully"""
        logger.info("🛑 Shutdown signal received, stopping...")
        self.running = False
        
    def generate_cpu_record(self, timestamp):
        """Generate a CPU metrics record matching latest-0 schema"""
        hostname = random.choice(self.hostnames)
        
        # Generate CPU usage percentages
        usage_user = random.uniform(5, 80)
        usage_system = random.uniform(1, 20)
        usage_nice = random.uniform(0, 5)
        usage_iowait = random.uniform(0, 10)
        usage_irq = random.uniform(0, 2)
        usage_softirq = random.uniform(0, 3)
        usage_steal = random.uniform(0, 1)
        usage_guest = 0.0
        usage_guest_nice = 0.0
        
        # Calculate idle to make total = 100
        total_used = usage_user + usage_system + usage_nice + usage_iowait + usage_irq + usage_softirq + usage_steal
        usage_idle = max(0, 100 - total_used)
        
        return {
            'hostname': hostname,
            'region': random.choice(self.regions),
            'datacenter': random.choice(self.datacenters),
            'rack': random.choice(self.racks),
            'os': random.choice(self.os_types),
            'arch': random.choice(self.architectures),
            'team': random.choice(self.teams),
            'service': random.choice(self.services),
            'service_version': random.choice(self.service_versions),
            'service_environment': random.choice(self.service_envs),
            'time': timestamp.strftime('%Y-%m-%d %H:%M:%S.%f')[:-3],
            'usage_user': round(usage_user, 2),
            'usage_system': round(usage_system, 2),
            'usage_idle': round(usage_idle, 2),
            'usage_nice': round(usage_nice, 2),
            'usage_iowait': round(usage_iowait, 2),
            'usage_irq': round(usage_irq, 2),
            'usage_softirq': round(usage_softirq, 2),
            'usage_steal': round(usage_steal, 2),
            'usage_guest': usage_guest,
            'usage_guest_nice': usage_guest_nice,
            'load1': round(random.uniform(0, 8), 2),
            'load5': round(random.uniform(0, 6), 2),
            'load15': round(random.uniform(0, 4), 2),
            'n_cpus': random.choice([2, 4, 8, 16, 32]),
            'n_users': random.randint(1, 50),
            'n_processes': random.randint(50, 500),
            'uptime_seconds': random.randint(3600, 7776000),
            'context_switches': random.randint(1000, 50000),
            'interrupts': random.randint(500, 25000),
            'software_interrupts': random.randint(100, 5000)
        }
    
    def generate_sensor_record(self, timestamp):
        """Generate an IoT sensor record"""
        device_id = random.choice(self.devices)
        
        return {
            'device_id': device_id,
            'device_type': random.choice(self.device_types),
            'customer_id': random.choice(self.customers),
            'site_id': random.choice(self.sites),
            'latitude': round(random.uniform(-90, 90), 6),
            'longitude': round(random.uniform(-180, 180), 6),
            'altitude': round(random.uniform(0, 2000), 1),
            'time': timestamp.strftime('%Y-%m-%d %H:%M:%S.%f')[:-3],
            'temperature': round(random.uniform(15, 35), 2),
            'humidity': round(random.uniform(30, 80), 2),
            'pressure': round(random.uniform(980, 1030), 2),
            'co2_level': round(random.uniform(400, 1500), 1),
            'noise_level': round(random.uniform(30, 80), 1),
            'light_level': round(random.uniform(0, 800), 1),
            'motion_detected': random.choice([0, 1]),
            'battery_level': round(random.uniform(20, 100), 2),
            'signal_strength': round(random.uniform(-90, -30), 1),
            'memory_usage': round(random.uniform(20, 80), 2),
            'cpu_usage': round(random.uniform(5, 70), 2),
            'status': random.choice([1, 2, 3, 4]),
            'error_count': random.randint(0, 5),
            'packets_sent': random.randint(1000, 50000),
            'packets_received': random.randint(900, 48000),
            'bytes_sent': random.randint(50000, 2000000),
            'bytes_received': random.randint(45000, 1900000)
        }
    
    def insert_batch(self, table, records):
        """Insert batch of records into ClickHouse"""
        try:
            if not records:
                return True
                
            lines = []
            for record in records:
                values = [str(v) for v in record.values()]
                lines.append('\t'.join(values))
            
            data = '\n'.join(lines)
            
            headers = {'Content-Type': 'text/tab-separated-values'}
            params = self.auth_params.copy()
            params['query'] = f'INSERT INTO {self.database}.{table} FORMAT TSV'
            
            response = requests.post(
                self.base_url,
                params=params,
                headers=headers,
                data=data,
                timeout=10
            )
            response.raise_for_status()
            return True
            
        except Exception as e:
            logger.error(f"❌ Failed to insert batch into {table}: {e}")
            return False
    
    def data_generator_thread(self):
        """Generate data at low rate"""
        logger.info("🔄 Starting data generation thread...")
        
        while self.running:
            try:
                current_time = datetime.now()
                
                # Generate small batches for both tables
                cpu_batch = [self.generate_cpu_record(current_time) for _ in range(self.batch_size)]
                sensor_batch = [self.generate_sensor_record(current_time) for _ in range(self.batch_size)]
                
                # Put into queue
                self.write_queue.put(('cpu_local', cpu_batch))
                self.write_queue.put(('sensors_local', sensor_batch))
                
                # Calculate delay for target rate
                # 2 batches * batch_size records per iteration
                total_records = 2 * self.batch_size
                delay = total_records / self.target_rate
                time.sleep(delay)
                
            except Exception as e:
                logger.error(f"❌ Error in data generation: {e}")
                time.sleep(1)
    
    def writer_thread(self):
        """Write data from queue to ClickHouse"""
        logger.info("✍️ Starting writer thread...")
        
        while self.running:
            try:
                table, records = self.write_queue.get(timeout=5)
                
                if self.insert_batch(table, records):
                    self.total_records += len(records)
                    
                    if table == 'cpu_local':
                        self.cpu_records += len(records)
                    else:
                        self.sensor_records += len(records)
                    
                    # Log progress every 100 records
                    if self.total_records % 100 == 0:
                        elapsed = time.time() - self.start_time
                        rate = self.total_records / elapsed
                        logger.info(f"📊 Progress: {self.total_records:,} total records, "
                                  f"Rate: {rate:.1f}/sec, CPU: {self.cpu_records}, "
                                  f"Sensors: {self.sensor_records}")
                
                self.write_queue.task_done()
                
            except Exception as e:
                if self.running:
                    logger.error(f"❌ Error in writer thread: {e}")
                    time.sleep(0.5)
    
    def metrics_thread(self):
        """Report metrics periodically"""
        logger.info("📈 Starting metrics thread...")
        
        while self.running:
            try:
                time.sleep(30)  # Report every 30 seconds
                
                if self.total_records > 0:
                    elapsed = time.time() - self.start_time
                    rate = self.total_records / elapsed
                    cpu_rate = self.cpu_records / elapsed
                    sensor_rate = self.sensor_records / elapsed
                    
                    logger.info("=" * 60)
                    logger.info(f"📊 METRICS SUMMARY (after {elapsed:.0f}s)")
                    logger.info(f"   Total Records: {self.total_records:,}")
                    logger.info(f"   Overall Rate: {rate:.2f} rec/sec")
                    logger.info(f"   CPU Records: {self.cpu_records:,} ({cpu_rate:.2f}/sec)")
                    logger.info(f"   Sensor Records: {self.sensor_records:,} ({sensor_rate:.2f}/sec)")
                    logger.info(f"   Queue Size: {self.write_queue.qsize()}")
                    logger.info("=" * 60)
                    
            except Exception as e:
                logger.error(f"❌ Error in metrics thread: {e}")
    
    def run(self):
        """Run the low-rate writer"""
        logger.info("🚀 Starting Low-Rate Writer...")
        
        # Start threads
        threads = [
            threading.Thread(target=self.data_generator_thread, daemon=True),
            threading.Thread(target=self.writer_thread, daemon=True),
            threading.Thread(target=self.metrics_thread, daemon=True)
        ]
        
        for thread in threads:
            thread.start()
        
        logger.info("✅ All threads started successfully")
        
        # Keep main thread alive
        try:
            while self.running:
                time.sleep(1)
        except KeyboardInterrupt:
            logger.info("🛑 Keyboard interrupt received")
        finally:
            self.running = False
            logger.info("⏳ Waiting for threads to finish...")
            time.sleep(2)
            
            # Final stats
            elapsed = time.time() - self.start_time
            rate = self.total_records / elapsed if elapsed > 0 else 0
            logger.info("=" * 60)
            logger.info("📊 FINAL STATISTICS")
            logger.info(f"   Total Records: {self.total_records:,}")
            logger.info(f"   Total Time: {elapsed:.0f}s")
            logger.info(f"   Average Rate: {rate:.2f} rec/sec")
            logger.info(f"   CPU Records: {self.cpu_records:,}")
            logger.info(f"   Sensor Records: {self.sensor_records:,}")
            logger.info("=" * 60)
            logger.info("✅ Writer stopped successfully")

if __name__ == '__main__':
    writer = LowRateWriter()
    writer.run()

