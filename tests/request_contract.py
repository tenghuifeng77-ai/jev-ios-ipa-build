"""Exercise the real Swift HTTP client against a local API contract fixture.

No provider key or external model call is used. The fixture rejects the
unsupported fields shown in the user's actual API error, including nulls.
"""
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import sys
import threading
import time


def main():
    root = Path(__file__).resolve().parents[1]
    source = Path(sys.argv[1]).resolve()
    scratch = Path(sys.argv[2]).resolve()
    scratch.mkdir(parents=True, exist_ok=True)
    executable = scratch / "request-check"
    subprocess.run([
        "swiftc", "-swift-version", "5", "-parse-as-library",
        "-o", str(executable), str(root / "tests/RequestCheck/main.swift"),
        *(str(path) for path in sorted((source / "Shared").glob("*.swift"))),
    ], check=True)
    observations = []

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_POST(self):
            scenario = self.path.split("/")[1]
            body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            problems = []
            if scenario.startswith("sol-"):
                unsupported = [key for key in ("max_tokens", "temperature", "top_p", "top_logprobs", "logprobs") if key in body]
                if unsupported:
                    problems.append("Unsupported fields must be absent: " + ", ".join(unsupported))
                expected_effort = {"sol-high": "high", "sol-low": "low"}.get(scenario, "medium")
                expected_limit = 8192 if scenario == "sol-high" else 4096
                if body.get("reasoning_effort") != expected_effort:
                    problems.append("Reasoning effort was lost or changed")
                if body.get("max_completion_tokens") != expected_limit:
                    problems.append("Completion budget missing or changed")
                if body.get("model") != "gpt-6.1-sol":
                    problems.append("Requested model was changed")
            elif scenario in ("legacy-glm", "legacy-custom", "anthropic"):
                expected_limit, expected_temp = (120, 0.5) if scenario == "legacy-custom" else (400, 0.9)
                if body.get("max_tokens") != expected_limit or body.get("temperature") != expected_temp:
                    problems.append("Existing provider request changed")
                if "max_completion_tokens" in body or "reasoning_effort" in body:
                    problems.append("Sol-only fields leaked into existing provider request")
            else:
                problems.append("Unknown test scenario")
            if not isinstance(body.get("messages"), list) or not body["messages"]:
                problems.append("Message input missing")
            anthropic = scenario == "anthropic"
            expected_path = f"/{scenario}/v1/messages" if anthropic else f"/{scenario}/chat/completions"
            if self.path != expected_path:
                problems.append("Wrong API endpoint")
            if anthropic:
                if self.headers.get("x-api-key") != "local-test-key" or self.headers.get("anthropic-version") != "2023-06-01":
                    problems.append("Anthropic authentication headers changed")
            elif self.headers.get("Authorization") != "Bearer local-test-key":
                problems.append("Bearer authentication header changed")
            observations.append({"scenario": scenario, "problems": problems, "body": body})
            if problems:
                status = 400
                response = {"error": {"message": "; ".join(problems), "type": "invalid_request_error"}}
            else:
                if scenario == "sol-delayed":
                    time.sleep(36)
                status = 200
                if anthropic:
                    response = {"id": "msg_local", "type": "message", "role": "assistant", "model": body["model"], "content": [{"type": "text", "text": "收到"}], "stop_reason": "end_turn", "usage": {"input_tokens": 5, "output_tokens": 2}}
                else:
                    response = {"id": "chatcmpl-local", "object": "chat.completion", "created": 0, "model": body["model"], "choices": [{"index": 0, "message": {"role": "assistant", "content": "收到"}, "finish_reason": "stop"}], "usage": {"prompt_tokens": 5, "completion_tokens": 2, "total_tokens": 7}}
            encoded = json.dumps(response, ensure_ascii=False).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(encoded)))
            self.end_headers()
            try:
                self.wfile.write(encoded)
            except (BrokenPipeError, ConnectionResetError):
                pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        result = subprocess.run([str(executable), f"http://127.0.0.1:{server.server_port}"], timeout=180)
    finally:
        server.shutdown()
        server.server_close()
        logs = root / "logs"
        logs.mkdir(exist_ok=True)
        (logs / "request-contract-results.json").write_text(json.dumps(observations, ensure_ascii=False, indent=2), encoding="utf-8")
    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
