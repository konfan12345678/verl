#!/usr/bin/env python3
"""Stdlib HTTP server that speaks SandboxFusion /run_code JSON.

Used on air-gapped 910B boxes so ReTool GRPO does not need conda/poetry.
Executes user code with a separate interpreter (portable CPython + numpy/sympy).
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any


def _run_python(python_bin: str, code: str, stdin: str | None, timeout: float) -> dict[str, Any]:
    fd, path = tempfile.mkstemp(prefix="retool_code_", suffix=".py")
    os.close(fd)
    try:
        with open(path, "w", encoding="utf-8") as f:
            f.write(code)
        started = time.time()
        try:
            proc = subprocess.run(
                [python_bin, path],
                input=stdin if stdin is not None else "",
                capture_output=True,
                text=True,
                timeout=timeout,
                env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"},
            )
            return {
                "status": "Finished",
                "execution_time": time.time() - started,
                "return_code": proc.returncode,
                "stdout": proc.stdout,
                "stderr": proc.stderr,
            }
        except subprocess.TimeoutExpired as exc:
            return {
                "status": "TimeLimitExceeded",
                "execution_time": time.time() - started,
                "return_code": None,
                "stdout": (exc.stdout or b"").decode() if isinstance(exc.stdout, bytes) else (exc.stdout or ""),
                "stderr": (exc.stderr or b"").decode() if isinstance(exc.stderr, bytes) else (exc.stderr or "timeout"),
            }
    finally:
        try:
            os.remove(path)
        except OSError:
            pass


class Handler(BaseHTTPRequestHandler):
    python_bin = sys.executable

    def log_message(self, fmt: str, *args: Any) -> None:
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def _send_json(self, payload: dict[str, Any], status: int = 200) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        path = self.path.split("?", 1)[0]
        if path in ("/v1/ping", "/ping", "/"):
            self._send_json({"status": "ok"})
            return
        self._send_json({"detail": "not found"}, 404)

    def do_POST(self) -> None:  # noqa: N802
        path = self.path.split("?", 1)[0]
        if path.rstrip("/") != "/run_code":
            self._send_json({"detail": "not found"}, 404)
            return
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        try:
            req = json.loads(raw.decode("utf-8") or "{}")
        except json.JSONDecodeError as e:
            self._send_json({"status": "Failed", "message": str(e), "compile_result": None, "run_result": None}, 400)
            return

        language = (req.get("language") or "python").lower()
        if language not in ("python", "py"):
            self._send_json(
                {
                    "status": "Failed",
                    "message": f"unsupported language: {language} (offline server is python-only)",
                    "compile_result": None,
                    "run_result": None,
                    "executor_pod_name": None,
                    "files": {},
                }
            )
            return

        timeout = float(req.get("run_timeout") or req.get("timeout") or 30)
        run_result = _run_python(self.python_bin, req.get("code") or "", req.get("stdin"), timeout)
        ok = run_result.get("status") == "Finished" and run_result.get("return_code") == 0
        self._send_json(
            {
                "status": "Success" if ok else "Failed",
                "message": "" if ok else (run_result.get("stderr") or run_result.get("status") or "failed"),
                "compile_result": None,
                "run_result": run_result,
                "executor_pod_name": None,
                "files": {},
            }
        )


def main() -> None:
    parser = argparse.ArgumentParser(description="Offline SandboxFusion-compatible /run_code server")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8080)
    parser.add_argument(
        "--python",
        default=os.environ.get("SANDBOX_RUNTIME_PYTHON") or sys.executable,
        help="Interpreter used to execute model-generated code",
    )
    args = parser.parse_args()
    Handler.python_bin = args.python
    if not os.path.isfile(args.python) or not os.access(args.python, os.X_OK):
        raise SystemExit(f"runtime python not executable: {args.python}")
    httpd = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"run_code listening on http://{args.host}:{args.port}/run_code", flush=True)
    print(f"runtime python: {args.python}", flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
