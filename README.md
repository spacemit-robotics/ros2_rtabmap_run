# RTABMAP Run

## 项目简介

本包提供基于 RGB-D 相机的 RTABMAP SLAM 启动文件，用于实现机器人的 2D 建图与定位功能。

## 功能特性

**支持：**
- RGB-D 相机 SLAM 建图模式
- 基于已有地图的定位模式
- 深度图像转点云
- 障碍物与地面分割检测


## 快速开始

### 环境准备

- ROS2 Humble
- RTABMAP ROS2 包
- RGB-D 相机驱动（需发布以下话题）

**必需话题：**

| 话题 | 类型 | 说明 |
|------|------|------|
| `/camera/color/image_raw` | sensor_msgs/Image | RGB 图像 |
| `/camera/color/camera_info` | sensor_msgs/CameraInfo | RGB 相机参数 |
| `/camera/depth/image_rect_raw` | sensor_msgs/Image | 深度图像 |
| `/camera/depth/camera_info` | sensor_msgs/CameraInfo | 深度相机参数 |

**必需 TF：**
- `odom` -> `base_footprint`

### 构建编译

```bash
colcon build --packages-select rtabmap_run
source install/setup.bash
```

### 运行示例

**SLAM 建图模式：**
```bash
ros2 launch rtabmap_run rgbd_slam.launch.py
```

**定位模式（需已有地图）：**
```bash
ros2 launch rtabmap_run rgbd_slam.launch.py localization:=true
```

## 详细使用

### 3D 激光雷达 SLAM

本包同时提供基于 3D 激光点云的 SLAM 启动文件：`launch/3d_lidar_slam.launch.py`。

该启动文件基于 RTAB-Map 的点云建图能力，适用于仅使用激光雷达点云进行三维建图的场景。当前启动文件内部默认启用仿真时间（`use_sim_time = True`），并订阅 `/points` 点云话题。

**启动方式：**

```bash
ros2 launch rtabmap_run 3d_lidar_slam.launch.py
```

**输入话题要求：**

| 话题       | 类型                     | 说明                              |
| ---------- | ------------------------ | --------------------------------- |
| `/points`  | sensor_msgs/PointCloud2  | 3D 激光雷达点云输入               |
| `/odom`    | nav_msgs/Odometry        | 机器人里程计输入，供 RTAB-Map 建图使用 |
| `/tf`      | tf2_msgs/TFMessage       | 坐标变换                          |

**涉及坐标系：**

- `base_link`：机器人基座坐标系
- `odom`：里程计坐标系
- `map`：地图坐标系
- `lidar_odom`：ICP 里程计坐标系（在启动文件中预留给 `icp_odometry` 节点）

**当前启动的节点：**

- `rtabmap` - RTAB-Map 主建图节点

> 说明：当前 `3d_lidar_slam.launch.py` 文件中已定义 `lidar_icp_odometry` 和 `rtabmap_viz` 节点，但在最终 `LaunchDescription` 中暂未启用，默认仅启动 `rtabmap` 节点。

**核心参数说明：**

| 参数                    | 值          | 说明                 |
| ----------------------- | ----------- | -------------------- |
| `frame_id`              | `base_link` | 机器人主体坐标系     |
| `odom_frame_id`         | `odom`      | 里程计坐标系         |
| `map_frame_id`          | `map`       | 地图坐标系           |
| `subscribe_scan_cloud`  | `True`      | 订阅点云进行建图     |
| `Grid/3D`               | `true`      | 启用三维栅格地图     |
| `Grid/FromDepth`        | `false`     | 不使用深度图生成栅格 |
| `Grid/RangeMax`         | `20.0`      | 最大建图距离 20 米   |
| `Grid/CellSize`         | `0.1`       | 栅格分辨率 0.1 米    |
| `Reg/Strategy`          | `1`         | 使用 ICP 配准策略    |
| `Icp/PointToPlane`      | `true`      | 启用点到平面 ICP     |
| `Rtabmap/DetectionRate` | `10.0`      | 地图更新频率         |
| `publish_tf`            | `True`      | 发布地图相关 TF      |

**话题重映射：**

| 原始名称     | 重映射后名称 | 说明             |
| ------------ | ------------ | ---------------- |
| `odom`       | `/odom`      | 外部里程计输入   |
| `scan_cloud` | `/points`    | 激光雷达点云输入 |

**适用场景：**

- 仅具备 3D 激光雷达传感器的机器人建图
- 室内外点云建图与回环检测
- 需要构建 3D Occupancy/Grid 地图的场景

**启动节点：**
- `rtabmap` - SLAM/定位主节点
- `point_cloud_xyz` - 深度图转点云
- `obstacles_detection` - 障碍物/地面分割

**发布话题：**

| 话题 | 类型 | 说明 |
|------|------|------|
| `/map` | nav_msgs/OccupancyGrid | 栅格地图 |
| `/camera/cloud` | sensor_msgs/PointCloud2 | 深度点云 |
| `/camera/obstacles` | sensor_msgs/PointCloud2 | 障碍物点云 |
| `/camera/ground` | sensor_msgs/PointCloud2 | 地面点云 |

**启动参数：**

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `use_sim_time` | false | 使用仿真时间 |
| `localization` | false | 定位模式（需已有地图） |

更多详情请参考 [RTABMAP 官方文档](http://wiki.ros.org/rtabmap_ros)。

## 常见问题

1. **建图漂移严重**：检查里程计精度，确保 `odom` -> `base_footprint` TF 准确
2. **点云无输出**：确认深度相机话题正常发布，检查话题名称是否匹配
3. **定位模式启动失败**：确保 `~/.ros/rtabmap.db` 地图文件存在

## 版本与发布

| 版本 | 日期 | 说明 |
|------|------|------|
| 0.0.1 | 2024-01 | 初始版本，支持 RGB-D SLAM |

## 贡献方式

欢迎提交 Issue 和 Pull Request。

## License

本组件源码文件头声明为 Apache-2.0，最终以本目录 `LICENSE` 文件为准。
