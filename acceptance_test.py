#!/usr/bin/env python3
"""Exercise the SGLang OpenAI-compatible endpoint without third-party clients."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import sys
import time
from typing import Any
import urllib.error
import urllib.request


DEFAULT_BASE_URL = os.environ.get("SGLANG_BASE_URL", "http://127.0.0.1:30000")
DEFAULT_MODEL = os.environ.get("SERVED_MODEL_NAME", "Qwen3.8-27B")


def request_json(
    base_url: str,
    path: str,
    payload: dict[str, Any] | None = None,
    timeout: float = 180.0,
) -> dict[str, Any]:
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        f"{base_url.rstrip('/')}{path}",
        data=data,
        headers={"Content-Type": "application/json"},
        method="GET" if data is None else "POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            decoded = json.load(response)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"HTTP {exc.code} from {path}: {body}") from exc
    if not isinstance(decoded, dict):
        raise RuntimeError(f"Expected a JSON object from {path}, got {type(decoded).__name__}")
    return decoded


def first_choice(response: dict[str, Any]) -> dict[str, Any]:
    choices = response.get("choices")
    if not isinstance(choices, list) or not choices or not isinstance(choices[0], dict):
        raise RuntimeError(f"Invalid completion response: {response}")
    return choices[0]


def run_case(
    name: str,
    base_url: str,
    payload: dict[str, Any],
    timeout: float,
) -> tuple[dict[str, Any], float]:
    started = time.perf_counter()
    response = request_json(base_url, "/v1/chat/completions", payload, timeout)
    elapsed = time.perf_counter() - started
    print(f"PASS {name}: {elapsed:.3f}s")
    return response, elapsed


def run_acceptance(base_url: str, model: str, timeout: float) -> dict[str, Any]:
    results: dict[str, Any] = {
        "base_url": base_url,
        "model": model,
        "tests": {},
    }

    models = request_json(base_url, "/v1/models", timeout=timeout)
    model_data = models.get("data")
    if not isinstance(model_data, list) or not model_data:
        raise RuntimeError(f"/v1/models returned no models: {models}")
    print("PASS model list")
    results["tests"]["models"] = {"status": "pass", "response": models}

    common = {
        "model": model,
        "temperature": 0,
        "max_tokens": 64,
        "chat_template_kwargs": {"enable_thinking": False},
    }

    basic, basic_elapsed = run_case(
        "chat completion",
        base_url,
        {
            **common,
            "messages": [{"role": "user", "content": "Reply with exactly: SGLang NVFP4 OK"}],
        },
        timeout,
    )
    basic_message = first_choice(basic).get("message")
    if not isinstance(basic_message, dict) or not basic_message.get("content"):
        raise RuntimeError(f"Chat completion returned no content: {basic}")
    results["tests"]["chat"] = {
        "status": "pass",
        "elapsed_s": round(basic_elapsed, 3),
        "response": basic,
    }

    tool, tool_elapsed = run_case(
        "tool call",
        base_url,
        {
            **common,
            "messages": [
                {
                    "role": "user",
                    "content": "Call get_weather exactly once with city set to Beijing.",
                }
            ],
            "tools": [
                {
                    "type": "function",
                    "function": {
                        "name": "get_weather",
                        "description": "Return weather for a city.",
                        "parameters": {
                            "type": "object",
                            "properties": {"city": {"type": "string"}},
                            "required": ["city"],
                            "additionalProperties": False,
                        },
                    },
                }
            ],
            "tool_choice": {"type": "function", "function": {"name": "get_weather"}},
        },
        timeout,
    )
    tool_choice = first_choice(tool)
    tool_message = tool_choice.get("message")
    tool_calls = tool_message.get("tool_calls") if isinstance(tool_message, dict) else None
    if tool_choice.get("finish_reason") != "tool_calls" or not isinstance(tool_calls, list) or len(tool_calls) != 1:
        raise RuntimeError(f"Expected one tool call: {tool}")
    function = tool_calls[0].get("function") if isinstance(tool_calls[0], dict) else None
    if not isinstance(function, dict) or function.get("name") != "get_weather":
        raise RuntimeError(f"Unexpected tool call: {tool}")
    arguments = function.get("arguments")
    parsed_arguments = json.loads(arguments) if isinstance(arguments, str) else arguments
    if not isinstance(parsed_arguments, dict) or parsed_arguments.get("city") != "Beijing":
        raise RuntimeError(f"Unexpected tool arguments: {arguments}")
    results["tests"]["tool_call"] = {
        "status": "pass",
        "elapsed_s": round(tool_elapsed, 3),
        "response": tool,
    }

    structured, structured_elapsed = run_case(
        "JSON Schema",
        base_url,
        {
            **common,
            "messages": [
                {
                    "role": "user",
                    "content": "Return status ok and the integer value 5090.",
                }
            ],
            "response_format": {
                "type": "json_schema",
                "json_schema": {
                    "name": "health_check",
                    "strict": True,
                    "schema": {
                        "type": "object",
                        "properties": {
                            "status": {"type": "string", "enum": ["ok"]},
                            "value": {"type": "integer", "const": 5090},
                        },
                        "required": ["status", "value"],
                        "additionalProperties": False,
                    },
                },
            },
        },
        timeout,
    )
    structured_message = first_choice(structured).get("message")
    structured_content = structured_message.get("content") if isinstance(structured_message, dict) else None
    if not isinstance(structured_content, str):
        raise RuntimeError(f"Structured output returned no text content: {structured}")
    parsed_content = json.loads(structured_content)
    if parsed_content != {"status": "ok", "value": 5090}:
        raise RuntimeError(f"Structured output violated the schema: {parsed_content}")
    results["tests"]["json_schema"] = {
        "status": "pass",
        "elapsed_s": round(structured_elapsed, 3),
        "response": structured,
    }

    results["status"] = "pass"
    return results


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default=DEFAULT_BASE_URL)
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--timeout", type=float, default=180.0)
    parser.add_argument("--output", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        results = run_acceptance(args.base_url, args.model, args.timeout)
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1

    rendered = json.dumps(results, ensure_ascii=False, indent=2)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered + "\n", encoding="utf-8")
        print(f"Wrote {args.output}")
    else:
        print(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
