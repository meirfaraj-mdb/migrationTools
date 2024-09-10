from flask import Flask, Response
import requests
import time

app = Flask(__name__)

# Constants
BYTES_PER_GB = 1024 ** 3
MONGOSYNC_URL = 'http://localhost:27183/api/v1/progress'

# Global variable to store start time
start_time = time.time()

def get_mongosync_data():
    try:
        response = requests.get(MONGOSYNC_URL, timeout=5)
        response.raise_for_status()
        return response.json()
    except (requests.RequestException, ValueError) as e:
        app.logger.error(f"Error fetching mongosync data: {e}")
        return None

def calculate_metrics(current_data):
    global start_time
    current_time = time.time()
    elapsed = current_time - start_time

    current_copied = current_data['progress']['collectionCopy']['estimatedCopiedBytes']
    total_bytes = current_data['progress']['collectionCopy']['estimatedTotalBytes']

    remaining = max(0, total_bytes - current_copied)  # Ensure non-negative

    progress_percentage = (current_copied / total_bytes) * 100 if total_bytes > 0 else 0
    progress_size_gb = current_copied / BYTES_PER_GB
    remain_gb = remaining / BYTES_PER_GB

    # Improved ETA calculation
    if elapsed > 0 and current_copied > 0:
        rate = current_copied / elapsed
        eta_seconds = remaining / rate if rate > 0 else 0
    else:
        eta_seconds = 0

    return {
        'progress_percentage': progress_percentage,
        'progress_size_gb': progress_size_gb,
        'remaining_size_gb': remain_gb,
        'lag_time_seconds': current_data['progress']['lagTimeSeconds'],
        'total_events_applied': current_data['progress']['totalEventsApplied'],
        'eta_seconds': max(0, eta_seconds),  # Ensure non-negative
        'state': current_data['progress']['state'],
        'can_commit': int(current_data['progress']['canCommit']),
        'can_write': int(current_data['progress']['canWrite']),
        'source': current_data['progress']['directionMapping']['Source'],
        'destination': current_data['progress']['directionMapping']['Destination']
    }

@app.route('/metrics')
def metrics():
    current_data = get_mongosync_data()
    if not current_data:
        return Response("Error fetching data", status=500)

    metric_data = calculate_metrics(current_data)

    metrics = [
        f'mongosync_progress_percentage {metric_data["progress_percentage"]:.2f}',
        f'mongosync_progress_size_gb {metric_data["progress_size_gb"]:.2f}',
        f'mongosync_remaining_size_gb {metric_data["remaining_size_gb"]:.2f}',
        f'mongosync_lag_time_seconds {metric_data["lag_time_seconds"]}',
        f'mongosync_total_events_applied {metric_data["total_events_applied"]}',
        f'mongosync_eta_seconds {metric_data["eta_seconds"]:.2f}',
        f'mongosync_info{{state="{metric_data["state"]}", source="{metric_data["source"]}", destination="{metric_data["destination"]}"}} 1',
        f'mongosync_can_commit {metric_data["can_commit"]}',
        f'mongosync_can_write {metric_data["can_write"]}'
    ]

    return Response('\n'.join(metrics), mimetype='text/plain')

if __name__ == '__main__':
    app.run(host="0.0.0.0", port=8001)