#!/usr/bin/env bash
#
# Copyright (C) 2026 SpacemiT (Hangzhou) Technology Co. Ltd.
# SPDX-License-Identifier: Apache-2.0
#

set -euo pipefail

module_dir="${SROBOTIS_ROOT:-$(pwd)}/middleware/ros2/slam/rtabmap_run"
artifact_dir="${SROBOTIS_TEST_ARTIFACT_DIR:-${module_dir}/test-artifacts/rtabmap-rgbd-invalid-bag}"
log_dir="${artifact_dir}/logs"
log_file="${log_dir}/rtabmap_rgbd_invalid_bag.log"
ros_log_dir="${artifact_dir}/ros_logs"
invalid_bag_dir="${artifact_dir}/non_rgbd_bag"

mkdir -p "${log_dir}" "${ros_log_dir}"
: >"${log_file}"

log() {
  echo "[rtabmap-rgbd-invalid-bag] $*" | tee -a "${log_file}"
}

run_logged() {
  log "\$ $*"
  "$@" >>"${log_file}" 2>&1
}

cleanup() {
  set +e
  if [[ -n "${record_pid:-}" ]]; then
    kill -- "-${record_pid}" >/dev/null 2>&1 || kill "${record_pid}" >/dev/null 2>&1 || true
    wait "${record_pid}" >/dev/null 2>&1 || true
  fi
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
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-45}"
export PYTHONUNBUFFERED=1

if ! command -v ros2 >/dev/null 2>&1; then
  log "ERROR: ros2 command not found"
  exit 1
fi

rm -rf "${invalid_bag_dir}"
log "Creating valid rosbag without RGB-D topics at ${invalid_bag_dir}"
setsid ros2 bag record -o "${invalid_bag_dir}" /rtabmap_run_invalid_marker >>"${log_file}" 2>&1 &
record_pid=$!
sleep 3
run_logged ros2 topic pub --once /rtabmap_run_invalid_marker std_msgs/msg/String "{data: no_rgbd_input}"
sleep 1
kill -- "-${record_pid}" >/dev/null 2>&1 || kill "${record_pid}" >/dev/null 2>&1 || true
wait "${record_pid}" >/dev/null 2>&1 || true
unset record_pid

if [[ ! -f "${invalid_bag_dir}/metadata.yaml" ]]; then
  log "ERROR: failed to create non-RGB-D rosbag metadata"
  exit 1
fi
if ! grep -q "message_count: 1" "${invalid_bag_dir}/metadata.yaml"; then
  log "ERROR: non-RGB-D rosbag does not contain the marker message"
  exit 1
fi

run_logged ros2 pkg prefix rtabmap_run
run_logged ros2 pkg prefix rtabmap_slam

log "Starting rgbd_slam.launch.py without valid RGB-D input"
setsid ros2 launch rtabmap_run rgbd_slam.launch.py use_sim_time:=true >>"${log_file}" 2>&1 &
launch_pid=$!

sleep 4
if ! kill -0 "${launch_pid}" >/dev/null 2>&1; then
  log "ERROR: launch process exited before invalid bag replay"
  exit 1
fi

log "Starting non-RGB-D rosbag replay from ${invalid_bag_dir}"
setsid ros2 bag play "${invalid_bag_dir}" --clock --rate 1.0 >>"${log_file}" 2>&1 &
bag_pid=$!

log "Verifying no /map is produced for non-RGB-D input"
python3 - <<'PY' 2>&1 | tee -a "${log_file}"
import os
import sys
import time

import rclpy
from nav_msgs.msg import OccupancyGrid

received = []

def on_map(msg: OccupancyGrid) -> None:
    known = sum(1 for value in msg.data if value >= 0)
    print(f"unexpected /map: width={msg.info.width} height={msg.info.height} known_cells={known}", flush=True)
    if msg.info.width > 0 and msg.info.height > 0 and known > 0:
        received.append((msg.info.width, msg.info.height, known))

rclpy.init()
node = rclpy.create_node("rtabmap_run_ci_invalid_input_assertion")
node.create_subscription(OccupancyGrid, "/map", on_map, 10)
end_time = time.monotonic() + float(os.environ.get("RTABMAP_INVALID_INPUT_TIMEOUT", "20"))
try:
    while time.monotonic() < end_time and not received:
        rclpy.spin_once(node, timeout_sec=0.2)
finally:
    node.destroy_node()
    rclpy.shutdown()

if received:
    width, height, known = received[0]
    print(f"ERROR: received /map for invalid empty input width={width} height={height} known_cells={known}", file=sys.stderr)
    sys.exit(1)

print("PASS: non-RGB-D input produced no /map within timeout")
PY
assertion_status=${PIPESTATUS[0]}
if [[ ${assertion_status} -eq 0 ]]; then
  if ! wait "${bag_pid}"; then
    log "ERROR: non-RGB-D rosbag replay failed"
    exit 1
  fi
  unset bag_pid
  log "RTABMAP RGBD INVALID BAG TEST PASSED."
else
  log "ERROR: invalid bag assertion failed (python exit ${assertion_status})"
  exit 1
fi