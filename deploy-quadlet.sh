#!/bin/bash

# 解析命令行参数
while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--name)
      SERVICE_NAME="$2"
      shift 2
      ;;
    -?|-h|--help)
      echo "用法: $0 -n|--name <service_name>"
      echo "将指定服务的 quadlet 文件部署到 systemd 用户配置目录"
      echo ""
      echo "参数:"
      echo "  -n, --name        指定要部署的服务名称"
      echo "  -?, -h, --help    显示此帮助信息"
      echo ""
      echo "可用的服务:"
      for dir in */; do
        if [[ -d "$dir" ]]; then
          # 检查目录中是否有 quadlet 文件
          if find "$dir" -maxdepth 1 -name "*.container" -o -name "*.network" -o -name "*.volume" -o -name "*.kube" | grep -q .; then
            echo "  - ${dir%/}"
          fi
        fi
      done
      exit 0
      ;;
    *)
      echo "错误: 未知参数 '$1'"
      echo "使用 $0 --help 查看用法"
      exit 1
      ;;
  esac
done

# 检查是否提供了服务名称
if [[ -z "$SERVICE_NAME" ]]; then
  echo "错误: 必须提供服务名称"
  echo "使用 $0 --help 查看用法"
  exit 1
fi

# 检查服务目录是否存在
if [[ ! -d "$SERVICE_NAME" ]]; then
  echo "错误: 服务目录 '$SERVICE_NAME' 不存在"
  echo "可用的服务:"
  for dir in */; do
    if [[ -d "$dir" ]]; then
      # 检查目录中是否有 quadlet 文件
      if find "$dir" -maxdepth 1 -name "*.container" -o -name "*.network" -o -name "*.volume" -o -name "*.kube" | grep -q .; then
        echo "  - ${dir%/}"
      fi
    fi
  done
  exit 1
fi

# 检查目录中是否有 quadlet 文件
quadlet_files=($(ls "$SERVICE_NAME"/*.{container,network,volume,kube} 2>/dev/null))
if [[ ${#quadlet_files[@]} -eq 0 ]]; then
  echo "错误: 在 '$SERVICE_NAME' 目录中未找到 quadlet 文件 (.container, .network, .volume, .kube)"
  exit 1
fi

echo "正在部署服务: $SERVICE_NAME"

# 停止相关服务
echo "停止相关服务..."
for file in "${quadlet_files[@]}"; do
  filename=$(basename "$file")
  service_name="${filename%.*}"
  if [[ "$filename" == *.container ]]; then
    echo "  停止服务: $service_name"
    systemctl --user stop "$service_name" 2>/dev/null || true
  fi
done

# 清理未使用的网络
echo "清理未使用的网络..."
podman network prune -f 2>/dev/null || true

# 创建目标目录
mkdir -p ~/.config/containers/systemd

# 复制 quadlet 文件
echo "复制 quadlet 文件到 ~/.config/containers/systemd/"
for file in "${quadlet_files[@]}"; do
  echo "  复制: $(basename "$file")"
  cp "$file" ~/.config/containers/systemd/
done

# echo "启用用户级服务持久化..."
# loginctl enable-linger $USER 2>/dev/null

# 检查是否需要跳过用户级服务持久化
# 当系统是WSL，版本小于2.6.0，且UID为1000时，跳过持久化
# 参考: https://github.com/microsoft/WSL/issues/10205
should_skip_linger=false

# 检查是否在WSL环境中
if grep -qi microsoft /proc/version 2>/dev/null || [ -f /proc/sys/fs/binfmt_misc/WSLInterop ]; then
  # 获取当前用户UID
  current_uid=$(id -u)

  # 检查UID是否为1000
  if [ "$current_uid" -eq 1000 ]; then
    # 获取WSL版本
    if command -v wsl.exe >/dev/null 2>&1; then
      # WSL输出是UTF-16编码，需要转换并提取版本号
      wsl_version=$(wsl.exe --version 2>/dev/null | iconv -f UTF-16LE -t UTF-8 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
      if [ -n "$wsl_version" ]; then
        # 提取主要版本号 (例如: 2.5.9.0 -> 2.5.9)
        major_version=$(echo "$wsl_version" | cut -d. -f1-3)
        # 将版本号转换为数字进行比较 (例如: 2.5.9 -> 20509)
        version_num=$(echo "$major_version" | awk -F. '{printf "%d%02d%02d", $1, $2, $3}')
        if [ "$version_num" -lt 20600 ]; then
          should_skip_linger=true
          echo "检测到WSL版本 $major_version < 2.6.0，且UID为1000，跳过用户级服务持久化"
        fi
      fi
    fi
  fi
fi

if [ "$should_skip_linger" = false ]; then
  echo "启用用户级服务持久化..."
  loginctl enable-linger $USER 2>/dev/null || true
fi

echo "重新加载 systemd 用户守护进程..."
systemctl --user daemon-reload 2>/dev/null

echo "启用 Podman 自动更新服务..."
systemctl --user enable --now podman-auto-update 2>/dev/null || true
systemctl --user enable --now podman-auto-update.timer 2>/dev/null || true

echo "部署完成! 已复制 ${#quadlet_files[@]} 个文件"
echo "复制的文件:"
for file in "${quadlet_files[@]}"; do
  echo "  - $(basename "$file")"
done
