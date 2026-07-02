#!/usr/bin/env python3
import json
import os
import queue
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path


def default_app_path() -> Path:
    find = subprocess.run(
        [
            "find",
            str(Path.home() / "Library/Developer/Xcode/DerivedData"),
            "-path",
            "*/Build/Products/Debug/CodexIsland.app",
            "-type",
            "d",
            "-print",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    matches = [Path(line) for line in find.stdout.splitlines() if line.strip()]
    if not matches:
        raise FileNotFoundError("Debug CodexIsland.app not found; run make build-macos first")
    return matches[-1]


def append_jsonl(path: Path, payload: dict) -> None:
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, separators=(",", ":")) + "\n")
        handle.flush()
        os.fsync(handle.fileno())


def token_count_payload(input_tokens: int, cached_tokens: int, output_tokens: int, reasoning_tokens: int) -> dict:
    return {
        "type": "token_count",
        "info": {
            "total_token_usage": {
                "input_tokens": input_tokens,
                "cached_input_tokens": cached_tokens,
                "output_tokens": output_tokens,
                "reasoning_output_tokens": reasoning_tokens,
                "total_tokens": input_tokens + output_tokens,
            },
            "last_token_usage": {
                "input_tokens": input_tokens,
                "cached_input_tokens": cached_tokens,
                "output_tokens": output_tokens,
                "reasoning_output_tokens": reasoning_tokens,
                "total_tokens": input_tokens + output_tokens,
            },
        },
    }


def read_lines(process: subprocess.Popen[str], output: "queue.Queue[str]", lines: list[str]) -> None:
    assert process.stdout is not None
    for line in process.stdout:
        line = line.rstrip()
        lines.append(line)
        output.put(line)


def wait_for_log(lines: list[str], output: "queue.Queue[str]", predicate, label: str, timeout: float = 8.0) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate(lines):
            return
        try:
            output.get(timeout=0.1)
        except queue.Empty:
            pass
    tail = "\n".join(lines[-40:])
    raise AssertionError(f"timeout waiting for {label}\n--- log tail ---\n{tail}")


def count_runtime(lines: list[str], state: str) -> int:
    needle = f"[EventBus] runtime={state} "
    return sum(1 for line in lines if needle in line)


def count_runtime_activity(lines: list[str], state: str, activity: str) -> int:
    needle = f"[EventBus] runtime={state} activity={activity}"
    return sum(1 for line in lines if needle in line)


def token_line_seen(lines: list[str], input_tokens: int, cached_tokens: int, output_tokens: int) -> bool:
    needle = f"[Token] IN:{input_tokens} CACHE:{cached_tokens} OUT:{output_tokens}"
    return any(needle in line for line in lines)


def window_bounds() -> str:
    script = (
        "import CoreGraphics; import Foundation; "
        "let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]; "
        "let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []; "
        "for window in windows { "
        "if (window[kCGWindowOwnerName as String] as? String) == \"CodexIsland\" { "
        "print(window[kCGWindowBounds as String] ?? [:]) "
        "} }"
    )
    result = subprocess.run(["swift", "-e", script], capture_output=True, text=True, check=True)
    return result.stdout.strip()


def window_y(bounds: str) -> float:
    match = re.search(r"Y = ([0-9.]+);", bounds)
    if not match:
        raise AssertionError(f"could not parse window Y from bounds: {bounds}")
    return float(match.group(1))


def no_codex_island_processes() -> bool:
    result = subprocess.run(
        ["pgrep", "-fl", "CodexIsland|codex-watcher"],
        capture_output=True,
        text=True,
    )
    return result.returncode != 0


def main() -> int:
    app_path = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else default_app_path()
    binary = app_path / "Contents/MacOS/CodexIsland"
    if not binary.exists():
        raise FileNotFoundError(binary)

    if not no_codex_island_processes():
        raise RuntimeError("CodexIsland or codex-watcher is already running; quit it before this smoke test")

    with tempfile.TemporaryDirectory(prefix="codex-island-app-") as tmp:
        root = Path(tmp)
        codex_home = root / "codex-home"
        sessions = codex_home / "sessions"
        sessions.mkdir(parents=True)

        env = os.environ.copy()
        env["CODEX_HOME"] = str(codex_home)
        env["RUST_LOG"] = "info"
        env["NSUnbufferedIO"] = "YES"

        process = subprocess.Popen(
            [str(binary)],
            cwd=str(app_path.parent),
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )

        lines: list[str] = []
        output: "queue.Queue[str]" = queue.Queue()
        reader = threading.Thread(target=read_lines, args=(process, output, lines), daemon=True)
        reader.start()

        try:
            wait_for_log(lines, output, lambda seen: any("CodexIsland launched" in line for line in seen), "app launch")
            wait_for_log(lines, output, lambda seen: any("Connected to codex-watcher IPC" in line for line in seen), "IPC connection")
            wait_for_log(lines, output, lambda seen: any("File watcher started" in line for line in seen), "file watcher")

            bounds = window_bounds()
            if "Width" not in bounds or "Height" not in bounds:
                raise AssertionError(f"CodexIsland window not visible: {bounds}")
            if window_y(bounds) < 6:
                raise AssertionError(f"CodexIsland window is still too close to the screen top: {bounds}")

            session_dir = sessions / "2026" / "06" / "28"
            session_dir.mkdir(parents=True)
            rollout = session_dir / "rollout-app-smoke.jsonl"
            rollout.touch()
            time.sleep(0.3)

            append_jsonl(rollout, {"type": "session_init", "payload": {"session_id": "app-smoke-session", "model": "test"}})
            append_jsonl(rollout, {"type": "event_msg", "payload": {"type": "user_message"}})
            wait_for_log(
                lines,
                output,
                lambda seen: count_runtime_activity(seen, "running", "reasoning") >= 1,
                "running reasoning",
            )

            append_jsonl(
                rollout,
                {
                    "type": "event_msg",
                    "payload": token_count_payload(120, 40, 12, 0),
                },
            )
            wait_for_log(
                lines,
                output,
                lambda seen: count_runtime_activity(seen, "running", "agent_message") >= 1
                and token_line_seen(seen, 120, 40, 12),
                "running reply and first token snapshot",
            )
            idle_count_before_stream_timeout = count_runtime(lines, "idle")
            wait_for_log(
                lines,
                output,
                lambda seen: count_runtime(seen, "idle") > idle_count_before_stream_timeout,
                "stream timeout to idle",
                timeout=6.0,
            )

            append_jsonl(rollout, {"type": "event_msg", "payload": {"type": "user_message"}})
            wait_for_log(
                lines,
                output,
                lambda seen: count_runtime_activity(seen, "running", "reasoning") >= 2,
                "second running reasoning",
            )
            append_jsonl(
                rollout,
                {
                    "type": "event_msg",
                    "payload": {
                        "type": "awaiting_approval",
                        "tool": "shell",
                        "command": "echo app-smoke",
                    },
                },
            )
            wait_for_log(
                lines,
                output,
                lambda seen: count_runtime(seen, "waiting_for_input") >= 1,
                "waiting for input",
            )

            append_jsonl(rollout, {"type": "event_msg", "payload": {"type": "tool_approval", "approved": True}})
            wait_for_log(
                lines,
                output,
                lambda seen: count_runtime(seen, "running") >= 3,
                "approval returns to running",
            )

            append_jsonl(
                rollout,
                {
                    "type": "event_msg",
                    "payload": token_count_payload(220, 120, 30, 2),
                },
            )
            wait_for_log(
                lines,
                output,
                lambda seen: count_runtime_activity(seen, "running", "agent_message") >= 2
                and token_line_seen(seen, 220, 120, 30),
                "second running reply and token snapshot",
            )

            append_jsonl(rollout, {"type": "event_msg", "payload": {"type": "assistant_message_stop"}})
            wait_for_log(lines, output, lambda seen: count_runtime(seen, "idle") >= 2, "assistant stop to idle")

            append_jsonl(rollout, {"type": "event_msg", "payload": {"type": "turn_error", "message": "private text"}})
            wait_for_log(lines, output, lambda seen: count_runtime(seen, "error") >= 1, "error")
            wait_for_log(lines, output, lambda seen: count_runtime(seen, "idle") >= 3, "error timeout to idle", timeout=5.0)

            append_jsonl(
                rollout,
                {
                    "type": "event_msg",
                    "payload": {
                        "type": "awaiting_approval",
                        "tool": "shell",
                        "command": "echo denied",
                    },
                },
            )
            wait_for_log(
                lines,
                output,
                lambda seen: count_runtime(seen, "waiting_for_input") >= 2,
                "second waiting for input",
            )

            append_jsonl(rollout, {"type": "event_msg", "payload": {"type": "tool_approval", "approved": False}})
            wait_for_log(lines, output, lambda seen: count_runtime(seen, "idle") >= 4, "denied approval to idle")

            subprocess.run(["osascript", "-e", 'tell application "CodexIsland" to quit'], check=False)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.terminate()
                process.wait(timeout=3)

            time.sleep(1.0)
            if not no_codex_island_processes():
                raise AssertionError("CodexIsland or codex-watcher still running after quit")

            print("App runtime smoke test passed")
            print(f"Window bounds: {bounds}")
            print(
                "Runtime states: "
                f"running={count_runtime(lines, 'running')}, "
                f"waiting_for_input={count_runtime(lines, 'waiting_for_input')}, "
                f"error={count_runtime(lines, 'error')}, "
                f"idle={count_runtime(lines, 'idle')}"
            )
            print("Tokens: IN:120 CACHE:40 OUT:12; IN:220 CACHE:120 OUT:30")
            return 0
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=3)
                except subprocess.TimeoutExpired:
                    process.kill()
            shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
