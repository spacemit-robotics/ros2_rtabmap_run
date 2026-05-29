#!/usr/bin/env bash
#
# Copyright (C) 2026 SpacemiT (Hangzhou) Technology Co. Ltd.
# SPDX-License-Identifier: Apache-2.0
#

set -euo pipefail

module_dir="${SROBOTIS_ROOT:-$(pwd)}/middleware/ros2/slam/rtabmap_run"
artifact_dir="${SROBOTIS_TEST_ARTIFACT_DIR:-${module_dir}/test-artifacts/rtabmap-rgbd-rosbag-slam}"
log_dir="${artifact_dir}/logs"
log_file="${log_dir}/rtabmap_rgbd_rosbag_slam.log"
ros_log_dir="${artifact_dir}/ros_logs"

mkdir -p "${log_dir}" "${ros_log_dir}"
: >"${log_file}"

log() {
  echo "[rtabmap-rgbd-rosbag-slam] $*" | tee -a "${log_file}"
}

run_logged() {
  log "\$ $*"
  "$@" >>"${log_file}" 2>&1
}

cleanup() {
  set +e
  if [[ -n "${bag_pid:-}" ]]; then
    kill -- "-${bag_pid}" >/dev/null 2>&1 || kill "${bag_pid}" >/dev/null 2>&1 || true
    wait "${bag_pid}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${launch_pid:-}" ]]; then
    kill -- "-${launch_pid}" >/dev/null 2>&1 || kill "${launch_pid}" >/dev/null 2>&1 || true
    wait "${launch_pid}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

source_ros_setup() {
  set +u
  local root="${SROBOTIS_ROOT:-$(pwd)}"
  local setup_file
  for setup_file in \
    "/opt/ros/${ROS_DISTRO:-humble}/setup.bash" \
    "${SROBOTIS_OUTPUT_STAGING:-}/local_setup.bash" \
    "${SROBOTIS_OUTPUT_STAGING:-}/setup.bash" \
    "${root}/install/local_setup.bash" \
    "${root}/install/setup.bash" \
    "${root}/install/rtabmap_run/local_setup.bash" \
    "${root}/install/rtabmap_run/setup.bash"; do
    if [[ -f "${setup_file}" ]]; then
      # shellcheck disable=SC1090
      source "${setup_file}"
    fi
  done
  set -u
}

source_ros_setup

export ROS_LOG_DIR="${ros_log_dir}"
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-44}"
export PYTHONUNBUFFERED=1

bag_dir="${module_dir}/tests/rgbd_test_data"
if [[ ! -f "${bag_dir}/metadata.yaml" ]]; then
  log "ERROR: missing rosbag metadata: ${bag_dir}/metadata.yaml"
  exit 1
fi

if ! command -v ros2 >/dev/null 2>&1; then
  log "ERROR: ros2 command not found"
  exit 1
fi

run_logged ros2 pkg prefix rtabmap_run
run_logged ros2 pkg prefix rtabmap_slam
run_logged ros2 pkg prefix rtabmap_util

log "Starting rgbd_slam.launch.py with simulated time"
setsid ros2 launch rtabmap_run rgbd_slam.launch.py use_sim_time:=true >>"${log_file}" 2>&1 &
launch_pid=$!

sleep 4
if ! kill -0 "${launch_pid}" >/dev/null 2>&1; then
  log "ERROR: launch process exited before bag replay"
  exit 1
fi

log "Starting rosbag replay from ${bag_dir} with /clock"
setsid ros2 bag play "${bag_dir}" --clock --rate 1.0 >>"${log_file}" 2>&1 &
bag_pid=$!

log "Waiting for non-empty /map and /camera/cloud outputs"
python3 - <<'PY' 2>&1 | tee -a "${log_file}"
import math
import os
import sys
import time

import rclpy
from nav_msgs.msg import OccupancyGrid
from sensor_msgs.msg import PointCloud2

map_observations = []
cloud_observations = []

def on_map(msg: OccupancyGrid) -> None:
    width = msg.info.width
    height = msg.info.height
    known = sum(1 for value in msg.data if value >= 0)
    print(f"observed /map: width={width} height={height} known_cells={known}", flush=True)
    if width > 0 and height > 0 and known > 0 and math.isfinite(msg.info.resolution):
        map_observations.append((width, height, known))

def on_cloud(msg: PointCloud2) -> None:
    print(f"observed /camera/cloud: width={msg.width} height={msg.height} point_step={msg.point_step}", flush=True)
    if msg.width > 0 and msg.height > 0 and msg.point_step > 0:
        cloud_observations.append((msg.width, msg.height, msg.point_step))

rclpy.init()
node = rclpy.create_node("rtabmap_run_ci_rgbd_assertion")
node.create_subscription(OccupancyGrid, "/map", on_map, 10)
node.create_subscription(PointCloud2, "/camera/cloud", on_cloud, 10)
end_time = time.monotonic() + float(os.environ.get("RTABMAP_OUTPUT_TIMEOUT", "120"))
try:
    while time.monotonic() < end_time and (not map_observations or not cloud_observations):
        rclpy.spin_once(node, timeout_sec=0.2)
finally:
    node.destroy_node()
    rclpy.shutdown()

if not map_observations:
    print("ERROR: did not receive a non-empty /map occupancy grid", file=sys.stderr)
    sys.exit(1)
if not cloud_observations:
    print("ERROR: did not receive a non-empty /camera/cloud point cloud", file=sys.stderr)
    sys.exit(1)

map_width, map_height, known = map_observations[0]
cloud_width, cloud_height, point_step = cloud_observations[0]
print(
    "PASS: received non-empty /map "
    f"width={map_width} height={map_height} known_cells={known}; "
    "received /camera/cloud "
    f"width={cloud_width} height={cloud_height} point_step={point_step}"
)
PY
assertion_status=${PIPESTATUS[0]}
if [[ ${assertion_status} -ne 0 ]]; then
  log "ERROR: RGBD output assertion failed (python exit ${assertion_status})"
  exit "${assertion_status}"
fi

log "RTABMAP RGBD ROSBAG SLAM TEST PASSED."