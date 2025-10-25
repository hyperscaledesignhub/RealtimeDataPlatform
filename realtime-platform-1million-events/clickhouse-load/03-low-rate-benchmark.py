#!/usr/bin/env python3
"""
Low-Rate Query Benchmark for ClickHouse
Runs queries at ~5-20 QPS for testing with minimal resources
"""

import os
import sys
import subprocess
import time
import random
import threading
from datetime import datetime, timedelta
import signal
import statistics

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

class LowRateBenchmark:
    def __init__(self):
        """Initialize low-rate benchmark"""
        self.host = os.getenv('CLICKHOUSE_HOST', 'chi-iot-cluster-repl-iot-cluster-0-0-0.clickhouse.svc.cluster.local')
        self.port = int(os.getenv('CLICKHOUSE_PORT', '8123'))
        self.database = 'benchmark'
        
        # Low rate configuration (5-20 QPS)
        self.target_qps = 10  # queries per second
        self.workers = 2      # concurrent workers
        
        self.base_url = f"http://{self.host}:{self.port}"
        
        # Sample device/host pools (matching writer)
        self.devices = [f"device_{i:05d}" for i in range(1, 1001)]
        self.hostnames = [f"server_{i:04d}" for i in range(1, 501)]
        self.services = ['web-server', 'api-gateway', 'database', 'cache', 'queue-worker', 'auth-service', 'data-processor']
        
        # Metrics
        self.total_queries = 0
        self.successful_queries = 0
        self.failed_queries = 0
        self.latencies = []
        self.start_time = time.time()
        self.running = True
        
        # Lock for metrics
        self.metrics_lock = threading.Lock()
        
        # Signal handling
        signal.signal(signal.SIGTERM, self.handle_shutdown)
        signal.signal(signal.SIGINT, self.handle_shutdown)
        
        print(f"🚀 Low-Rate Benchmark initialized")
        print(f"📊 Target QPS: {self.target_qps}")
        print(f"👷 Workers: {self.workers}")
        print(f"🎯 ClickHouse: {self.host}:{self.port}")
        
    def handle_shutdown(self, signum, frame):
        """Handle shutdown gracefully"""
        print("\n🛑 Shutdown signal received, stopping...")
        self.running = False
    
    def get_query_templates(self):
        """Get query templates matching latest-0 schema - using local tables"""
        return [
            # Temperature analytics - single day (20%)
            ('single_day_temp', """
                SELECT 
                    avg(temperature) as avg_temp,
                    max(temperature) as max_temp,
                    count() as readings
                FROM benchmark.sensors_local
                WHERE device_id = '{device_id}'
                    AND toDate(time) = today() - {random_days}
                    AND toHour(time) IN ({random_hours})
                LIMIT 1
            """, 0.20),
            
            # Humidity analytics - single day (20%)
            ('single_day_humidity', """
                SELECT 
                    avg(humidity) as avg_humidity,
                    max(humidity) as max_humidity,
                    count() as readings
                FROM benchmark.sensors_local
                WHERE device_id = '{device_id}'
                    AND toDate(time) = today() - {random_days}
                    AND toHour(time) IN ({random_hours})
                LIMIT 1
            """, 0.20),
            
            # CPU usage analytics - single day (20%)
            ('single_day_cpu', """
                SELECT 
                    avg(usage_user) as avg_user_cpu,
                    avg(usage_system) as avg_system_cpu,
                    max(usage_user + usage_system) as max_cpu,
                    count() as readings
                FROM benchmark.cpu_local
                WHERE hostname = '{hostname}'
                    AND toDate(time) = today() - {random_days}
                    AND toHour(time) IN ({random_hours})
                LIMIT 1
            """, 0.20),
            
            # Load average analytics - single day (20%)
            ('single_day_load', """
                SELECT 
                    avg(load1) as avg_load1,
                    avg(load5) as avg_load5,
                    max(load1) as max_load1,
                    count() as readings
                FROM benchmark.cpu_local
                WHERE hostname = '{hostname}'
                    AND toDate(time) = today() - {random_days}
                    AND toHour(time) IN ({random_hours})
                LIMIT 1
            """, 0.20),
            
            # Device current status (10%)
            ('device_current_status', """
                SELECT 
                    device_id,
                    argMax(temperature, time) as current_temp,
                    argMax(humidity, time) as current_humidity,
                    max(time) as last_seen
                FROM benchmark.sensors_local
                WHERE device_id = '{device_id}'
                    AND time >= now() - INTERVAL 1 HOUR
                GROUP BY device_id
                LIMIT 1
            """, 0.10),
            
            # Host current status (10%)
            ('host_current_status', """
                SELECT 
                    hostname,
                    argMax(usage_user + usage_system, time) as current_cpu,
                    argMax(load1, time) as current_load1,
                    max(time) as last_metric
                FROM benchmark.cpu_local
                WHERE hostname = '{hostname}'
                    AND time >= now() - INTERVAL 30 MINUTE
                GROUP BY hostname
                LIMIT 1
            """, 0.10),
        ]
    
    def generate_query_params(self):
        """Generate random parameters for queries - matching latest-0"""
        # Random days (0-6 for last week)
        random_days = random.randint(0, 6)
        
        # Random hours in a day (2-5 random hours)
        num_hours = random.randint(2, 5)
        hours = random.sample(range(0, 24), num_hours)
        random_hours = ','.join(map(str, hours))
        
        return {
            'device_id': random.choice(self.devices),
            'hostname': random.choice(self.hostnames),
            'service': random.choice(self.services),
            'random_days': random_days,
            'random_hours': random_hours
        }
    
    def execute_query(self, query):
        """Execute a single query"""
        start_time = time.time()
        
        try:
            response = requests.post(
                self.base_url,
                data=query,
                params={'database': self.database},
                timeout=5
            )
            
            duration = time.time() - start_time
            
            if response.status_code == 200:
                with self.metrics_lock:
                    self.successful_queries += 1
                    self.latencies.append(duration)
                return True, duration
            else:
                with self.metrics_lock:
                    self.failed_queries += 1
                return False, duration
                
        except Exception as e:
            duration = time.time() - start_time
            with self.metrics_lock:
                self.failed_queries += 1
            print(f"❌ Query error: {e}")
            return False, duration
    
    def worker_thread(self, worker_id):
        """Worker thread to execute queries"""
        print(f"👷 Worker {worker_id} started")
        
        templates = self.get_query_templates()
        total_weight = sum(w for _, _, w in templates)
        
        while self.running:
            try:
                # Select query based on weight
                r = random.random()
                cumulative = 0
                selected_query = None
                
                for name, template, weight in templates:
                    cumulative += weight / total_weight
                    if r <= cumulative:
                        selected_query = (name, template)
                        break
                
                if selected_query:
                    query_name, query_template = selected_query
                    params = self.generate_query_params()
                    formatted_query = query_template.format(**params)
                    
                    # Execute query
                    success, duration = self.execute_query(formatted_query)
                    
                    with self.metrics_lock:
                        self.total_queries += 1
                    
                    # Rate limiting per worker
                    delay = self.workers / self.target_qps
                    time.sleep(delay)
                
            except Exception as e:
                print(f"❌ Worker {worker_id} error: {e}")
                time.sleep(1)
        
        print(f"👷 Worker {worker_id} stopped")
    
    def metrics_thread(self):
        """Report metrics periodically"""
        print("📈 Metrics thread started")
        
        while self.running:
            try:
                time.sleep(30)  # Report every 30 seconds
                
                if self.total_queries > 0:
                    elapsed = time.time() - self.start_time
                    
                    with self.metrics_lock:
                        qps = self.total_queries / elapsed
                        success_rate = (self.successful_queries / self.total_queries) * 100
                        
                        if self.latencies:
                            avg_latency = statistics.mean(self.latencies[-1000:])  # Last 1000 queries
                            p50 = statistics.median(self.latencies[-1000:])
                            p95 = sorted(self.latencies[-1000:])[int(len(self.latencies[-1000:]) * 0.95)] if len(self.latencies[-1000:]) > 0 else 0
                        else:
                            avg_latency = p50 = p95 = 0
                    
                    print("=" * 60)
                    print(f"📊 BENCHMARK METRICS (after {elapsed:.0f}s)")
                    print(f"   Total Queries: {self.total_queries:,}")
                    print(f"   Successful: {self.successful_queries:,} ({success_rate:.1f}%)")
                    print(f"   Failed: {self.failed_queries:,}")
                    print(f"   Current QPS: {qps:.2f}")
                    print(f"   Avg Latency: {avg_latency*1000:.2f}ms")
                    print(f"   P50 Latency: {p50*1000:.2f}ms")
                    print(f"   P95 Latency: {p95*1000:.2f}ms")
                    print("=" * 60)
                    
            except Exception as e:
                print(f"❌ Metrics error: {e}")
    
    def run(self, duration_seconds=None):
        """Run the benchmark"""
        print(f"🚀 Starting Low-Rate Benchmark...")
        if duration_seconds:
            print(f"⏱️  Duration: {duration_seconds}s")
        else:
            print(f"⏱️  Duration: Continuous (Ctrl+C to stop)")
        
        # Start worker threads
        workers = []
        for i in range(self.workers):
            worker = threading.Thread(target=self.worker_thread, args=(i,), daemon=True)
            worker.start()
            workers.append(worker)
        
        # Start metrics thread
        metrics = threading.Thread(target=self.metrics_thread, daemon=True)
        metrics.start()
        
        print("✅ All threads started successfully")
        
        # Run for specified duration or until interrupted
        try:
            if duration_seconds:
                time.sleep(duration_seconds)
                self.running = False
            else:
                while self.running:
                    time.sleep(1)
        except KeyboardInterrupt:
            print("\n🛑 Keyboard interrupt received")
        finally:
            self.running = False
            print("⏳ Waiting for threads to finish...")
            time.sleep(2)
            
            # Final stats
            elapsed = time.time() - self.start_time
            
            with self.metrics_lock:
                qps = self.total_queries / elapsed if elapsed > 0 else 0
                success_rate = (self.successful_queries / self.total_queries * 100) if self.total_queries > 0 else 0
                
                if self.latencies:
                    avg_latency = statistics.mean(self.latencies)
                    min_latency = min(self.latencies)
                    max_latency = max(self.latencies)
                    p50 = statistics.median(self.latencies)
                    p95 = sorted(self.latencies)[int(len(self.latencies) * 0.95)] if len(self.latencies) > 0 else 0
                    p99 = sorted(self.latencies)[int(len(self.latencies) * 0.99)] if len(self.latencies) > 0 else 0
                else:
                    avg_latency = min_latency = max_latency = p50 = p95 = p99 = 0
            
            print("\n" + "=" * 60)
            print("📊 FINAL BENCHMARK RESULTS")
            print("=" * 60)
            print(f"⏱️  Total Time: {elapsed:.0f}s")
            print(f"🔢 Total Queries: {self.total_queries:,}")
            print(f"✅ Successful: {self.successful_queries:,} ({success_rate:.1f}%)")
            print(f"❌ Failed: {self.failed_queries:,}")
            print(f"📈 Average QPS: {qps:.2f}")
            print()
            print("⚡ Latency Statistics:")
            print(f"   Average: {avg_latency*1000:.2f}ms")
            print(f"   Minimum: {min_latency*1000:.2f}ms")
            print(f"   Maximum: {max_latency*1000:.2f}ms")
            print(f"   P50: {p50*1000:.2f}ms")
            print(f"   P95: {p95*1000:.2f}ms")
            print(f"   P99: {p99*1000:.2f}ms")
            print("=" * 60)
            print("✅ Benchmark completed successfully")

if __name__ == '__main__':
    import argparse
    
    parser = argparse.ArgumentParser(description='Low-Rate ClickHouse Benchmark')
    parser.add_argument('--qps', type=int, default=10, help='Target queries per second (default: 10)')
    parser.add_argument('--workers', type=int, default=2, help='Number of worker threads (default: 2)')
    parser.add_argument('--duration', type=int, default=None, help='Duration in seconds (default: continuous)')
    
    args = parser.parse_args()
    
    benchmark = LowRateBenchmark()
    benchmark.target_qps = args.qps
    benchmark.workers = args.workers
    
    benchmark.run(duration_seconds=args.duration)

