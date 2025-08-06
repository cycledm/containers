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

# 创建目标目录
mkdir -p ~/.config/containers/systemd

# 复制 quadlet 文件
echo "复制 quadlet 文件到 ~/.config/containers/systemd/"
for file in "${quadlet_files[@]}"; do
  echo "  复制: $(basename "$file")"
  cp "$file" ~/.config/containers/systemd/
done

echo "启用用户 linger (允许用户服务在注销后继续运行)..."
loginctl enable-linger

echo "重新加载 systemd 用户守护进程..."
systemctl --user daemon-reload

echo "部署完成! 已复制 ${#quadlet_files[@]} 个文件"
echo "复制的文件:"
for file in "${quadlet_files[@]}"; do
  echo "  - $(basename "$file")"
done
