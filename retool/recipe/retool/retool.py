# Copyright 2024 Bytedance Ltd. and/or its affiliates
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
#
# Vendored from verl-project/verl-recipe `retool/retool.py` and adapted for
# current verl main:
# - SandboxFusionTool lives in this kit (removed from verl in #6302)
# - execute() returns ToolResponse so ToolAgentLoop can read `.text`

import logging
import re
from typing import Any

import datasets

from recipe.retool.retool_dataset_utils import map_fn, map_fn2
from recipe.retool.sandbox_fusion_tools import SandboxFusionTool
from verl.tools.base_tool import OpenAIFunctionToolSchema
from verl.tools.schemas import ToolResponse
from verl.utils.dataset import RLHFDataset
from verl.utils.reward_score import math_dapo
from verl.utils.rollout_trace import rollout_trace_op

logger = logging.getLogger(__name__)


class CustomSandboxFusionTool(SandboxFusionTool):
    def __init__(self, config: dict, tool_schema: OpenAIFunctionToolSchema):
        super().__init__(config, tool_schema)
        self.code_pattern = re.compile(r"```python(.*?)```", re.DOTALL)

    @rollout_trace_op
    async def execute(self, instance_id: str, parameters: dict[str, Any], **kwargs) -> tuple[ToolResponse, float, dict]:
        code = parameters["code"]
        matches = self.code_pattern.findall(code)
        if matches:
            code = matches[0].strip()

        # Some SFT trajectories do not print the last expression.
        lines = code.split("\n")
        for i, line in reversed(list(enumerate(lines))):
            if line == "":
                continue
            if not lines[i].startswith("print"):
                lines[i] = f"print({line})"
            break
        code = "\n".join(lines)

        patched = dict(parameters)
        patched["code"] = code
        response, reward, metrics = await super().execute(instance_id, patched, **kwargs)
        if not isinstance(response, ToolResponse):
            response = ToolResponse(text=None if response is None else str(response))
        if reward is None:
            reward = 0.0
        if metrics is None:
            metrics = {}
        return response, reward, metrics


class CustomRLHFDataset(RLHFDataset):
    """Load DAPO-Math-17k plus AIME 2024/2025 and tag `agent_name=tool_agent`."""

    def _read_files_and_tokenize(self):
        dataframes = []
        for parquet_file in self.data_files:
            dataframe = datasets.load_dataset(parquet_file)["train"]
            data_source = "/".join(str(parquet_file).rstrip("/").split("/")[-2:])
            if data_source in ["Maxwell-Jia/AIME_2024", "yentinglin/aime_2025"]:
                dataframe = dataframe.map(
                    map_fn, fn_kwargs={"data_source": data_source}, remove_columns=dataframe.column_names
                )
            else:
                dataframe = dataframe.map(map_fn2, num_proc=16)
            dataframes.append(dataframe)
        self.dataframe: datasets.Dataset = datasets.concatenate_datasets(dataframes)
        print(f"dataset len: {len(self.dataframe)}")


def compute_score(data_source, solution_str, ground_truth, extra_info, **kwargs):
    result = math_dapo.compute_score(solution_str, ground_truth, strict_box_verify=True)

    # Encourage the policy to actually call the interpreter.
    num_turns = extra_info["num_turns"]
    if result["score"] < 0:
        tool_call_reward = (num_turns - 2) / 2 * 0.1
        result["score"] = min(-0.6, result["score"] + tool_call_reward)

    if result["pred"] is None:
        result["pred"] = ""

    return result
