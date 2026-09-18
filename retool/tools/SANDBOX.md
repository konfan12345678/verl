# SandboxFusion 部署

ReTool 的工具名是 **`code_interpreter`**。verl 当前 `main` 已经删掉内置 `verl.tools.sandbox_fusion_tools`（PR `#6302`），本目录把实现放在 `recipe/retool/sandbox_fusion_tools.py`。

## 0. 直接在 910B 训练镜像里装（内网）

训练机不能出网时，**不要**在容器里 git/pip/huggingface。在能上网的机器跑 `offline/download_on_jumphost.sh`，把 `$HOME/retool-offline-payload` 和本 kit 一起拷进去，再 `bash offline/install_on_intranet.sh`。

说明与直链：[`../offline/OFFLINE.md`](../offline/OFFLINE.md)、[`../offline/URLS.md`](../offline/URLS.md)

## 1. 宿主机官方 Docker（容器外才用）

```bash
bash tools/deploy_sandbox_fusion.sh docker
```

等价于：

```bash
docker pull volcengine/sandbox-fusion:server-20250609
docker run -d --name sandbox-fusion --restart unless-stopped \
  --privileged -p 8080:8080 volcengine/sandbox-fusion:server-20250609
```

冒烟：

```bash
curl http://127.0.0.1:8080/run_code \
  -H 'Content-Type: application/json' \
  --data-raw '{"code":"print(1+1)","language":"python"}'
```

训练进程用：

```bash
export SANDBOX_FUSION_URL=http://127.0.0.1:8080/run_code
```

如果 GRPO 跑在 **NPU 容器** 里、沙箱跑在宿主机，把 `127.0.0.1` 换成宿主机可达地址（`--network host` 时仍可用 `127.0.0.1`）。

## 2. 源码安装（昇腾文档同款）

见 [SandboxFusion](https://github.com/bytedance/SandboxFusion) 与 [Get Started](https://bytedance.github.io/SandboxFusion/docs/docs/get-started/)。

```bash
bash tools/deploy_sandbox_fusion.sh source
```

步骤摘要：

1. `git clone -b main https://github.com/bytedance/SandboxFusion.git`
2. `conda create -n sandbox python=3.11 && conda activate sandbox`
3. `pip install poetry && poetry install`
4. `mkdir -p docs/build && cd runtime/python && bash install-python-runtime.sh`
5. `make run-online` → 监听 8080

## 3. 接到 verl 多轮 rollout

配置文件：`recipe/retool/sandbox_fusion_tool_config.yaml`

- `class_name`: `recipe.retool.retool.CustomSandboxFusionTool`
- 工具 schema 名必须是 **`code_interpreter`**（和 SFT 轨迹、DAPO `tools_kwargs` 一致）
- `SANDBOX_FUSION_URL` 环境变量会覆盖 yaml 里的 URL

Hydra：

```text
actor_rollout_ref.rollout.multi_turn.enable=True
actor_rollout_ref.rollout.multi_turn.tool_config_path=<kit>/recipe/retool/sandbox_fusion_tool_config.yaml
actor_rollout_ref.rollout.multi_turn.format=hermes
actor_rollout_ref.rollout.multi_turn.max_user_turns=16
actor_rollout_ref.rollout.multi_turn.max_assistant_turns=16
actor_rollout_ref.rollout.multi_turn.max_tool_response_length=4096
actor_rollout_ref.rollout.agent.default_agent_loop=tool_agent
```

默认 `max_tool_response_length=256` 对代码 stdout **太短**，脚本里已改成 4096。

## 4. 备选：Daytona

需要云端 API key，不是 910B 默认路径。

- 实现：`recipe/retool/daytona_sandbox_tool.py`
- 配置：`recipe/retool/daytona_tool_config.yaml`
- 安装：`pip install daytona`，设置 `DAYTONA_API_KEY`

把 GRPO 脚本的 `tool_config_path` 换成 daytona yaml 即可，工具名仍是 `code_interpreter`。
