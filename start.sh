#!/bin/bash
echo "=== 正在启动智能体环境 ==="
if ! pgrep -x "ollama" > /dev/null; then
    echo "启动 Ollama 服务..."
        ollama serve > /tmp/ollama.log 2>&1 &
            sleep 2
            else
                echo "Ollama 已在运行中。"
                fi
                echo "检查并确保 gemma2:2b 型就绪..."
                ollama list | grep -q "gemma2:2b" || ollama pull gemma2:2b
                echo "启动前端服务 (http://localhost:3000)..."
                cd frontend
                npm run dev
