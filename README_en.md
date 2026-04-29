# RTABMAP Run

## Introduction

This package provides RTABMAP SLAM launch files based on RGB-D camera for robot 2D mapping and localization.

## Features

**Supported:**
- RGB-D camera SLAM mapping mode
- Localization mode with existing map
- Depth image to point cloud conversion
- Obstacle and ground segmentation detection


## Quick Start

### Prerequisites

- ROS2 Humble
- RTABMAP ROS2 package
- RGB-D camera driver (must publish the following topics)

**Required Topics:**

| Topic | Type | Description |
|-------|------|-------------|
| `/camera/color/image_raw` | sensor_msgs/Image | RGB image |
| `/camera/color/camera_info` | sensor_msgs/CameraInfo | RGB camera info |
| `/camera/depth/image_rect_raw` | sensor_msgs/Image | Depth image |
| `/camera/depth/camera_info` | sensor_msgs/CameraInfo | Depth camera info |

**Required TF:**
- `odom` -> `base_footprint`

### Build

```bash
colcon build --packages-select rtabmap_run
source install/setup.bash
```

### Run Examples

**SLAM mapping mode:**
```bash
ros2 launch rtabmap_run rgbd_slam.launch.py
```

**Localization mode (requires existing map):**
```bash
ros2 launch rtabmap_run rgbd_slam.launch.py localization:=true
```

## Detailed Usage

### 3D LiDAR SLAM

This package also provides a 3D LiDAR-based SLAM launch file: `launch/3d_lidar_slam.launch.py`.

This launch file uses RTAB-Map point-cloud mapping capabilities and is intended for 3D mapping scenarios using LiDAR point clouds only. The current launch file internally enables simulation time by default (`use_sim_time = True`) and subscribes to the `/points` point cloud topic.

**Launch command:**

```bash
ros2 launch rtabmap_run 3d_lidar_slam.launch.py
```

**Required input topics:**

| Topic      | Type                    | Description                         |
| ---------- | ----------------------- | ----------------------------------- |
| `/points`  | sensor_msgs/PointCloud2 | 3D LiDAR point cloud input          |
| `/odom`    | nav_msgs/Odometry       | Robot odometry input used by RTAB-Map |
| `/tf`      | tf2_msgs/TFMessage      | Frame transforms                    |

**Related frames:**

- `base_link`: robot base frame
- `odom`: odometry frame
- `map`: map frame
- `lidar_odom`: ICP odometry frame (reserved in the launch file for `icp_odometry`)

**Currently launched node:**

- `rtabmap` - Main RTAB-Map mapping node

> Note: `lidar_icp_odometry` and `rtabmap_viz` are already defined in `3d_lidar_slam.launch.py`, but they are not included in the final `LaunchDescription` yet. By default, only the `rtabmap` node is launched.

**Key parameters:**

| Parameter               | Value       | Description                        |
| ----------------------- | ----------- | ---------------------------------- |
| `frame_id`              | `base_link` | Robot base frame                   |
| `odom_frame_id`         | `odom`      | Odometry frame                     |
| `map_frame_id`          | `map`       | Map frame                          |
| `subscribe_scan_cloud`  | `True`      | Subscribe to point cloud for mapping |
| `Grid/3D`               | `true`      | Enable 3D grid mapping             |
| `Grid/FromDepth`        | `false`     | Do not generate grid from depth images |
| `Grid/RangeMax`         | `20.0`      | Maximum mapping range: 20 meters   |
| `Grid/CellSize`         | `0.1`       | Grid resolution: 0.1 meter         |
| `Reg/Strategy`          | `1`         | Use ICP registration strategy      |
| `Icp/PointToPlane`      | `true`      | Enable point-to-plane ICP          |
| `Rtabmap/DetectionRate` | `10.0`      | Map update rate                    |
| `publish_tf`            | `True`      | Publish map-related TF             |

**Topic remappings:**

| Original Name | Remapped Name | Description              |
| ------------- | ------------- | ------------------------ |
| `odom`        | `/odom`       | External odometry input  |
| `scan_cloud`  | `/points`     | LiDAR point cloud input  |

**Typical use cases:**

- Mapping robots equipped with 3D LiDAR only
- Indoor/outdoor point-cloud mapping and loop closure
- Scenarios requiring 3D occupancy/grid map generation

**Launched Nodes:**
- `rtabmap` - Main SLAM/localization node
- `point_cloud_xyz` - Depth to point cloud converter
- `obstacles_detection` - Obstacle/ground segmentation

**Published Topics:**

| Topic | Type | Description |
|-------|------|-------------|
| `/map` | nav_msgs/OccupancyGrid | Occupancy grid map |
| `/camera/cloud` | sensor_msgs/PointCloud2 | Depth point cloud |
| `/camera/obstacles` | sensor_msgs/PointCloud2 | Obstacle point cloud |
| `/camera/ground` | sensor_msgs/PointCloud2 | Ground point cloud |

**Launch Parameters:**

| Parameter | Default | Description |
|-----------|---------|-------------|
| `use_sim_time` | false | Use simulation time |
| `localization` | false | Localization mode (requires existing map) |

For more details, please refer to [RTABMAP Official Documentation](http://wiki.ros.org/rtabmap_ros).

## FAQ

1. **Severe mapping drift**: Check odometry accuracy, ensure `odom` -> `base_footprint` TF is accurate
2. **No point cloud output**: Verify depth camera topics are publishing correctly, check topic names match
3. **Localization mode fails to start**: Ensure `~/.ros/rtabmap.db` map file exists

## Version & Release

| Version | Date | Description |
|---------|------|-------------|
| 0.0.1 | 2024-01 | Initial version, RGB-D SLAM support |

## Contributing

Issues and Pull Requests are welcome.

## License

Source files in this component are declared as Apache-2.0, subject to the `LICENSE` file in this directory.
