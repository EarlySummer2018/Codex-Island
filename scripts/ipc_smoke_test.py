#!/usr/bin/env python3
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Optional


def wait_for_socket(path: Path, timeout: float = 6.0) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if path.exists():
            return
        time.sleep(0.05)
    raise RuntimeError(f"socket not created: {path}")


def connect_socket(path: Path, timeout: float = 6.0) -> socket.socket:
    deadline = time.time() + timeout
    last_error: Exception | None = None
    while time.time() < deadline:
        try:
            client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            client.connect(str(path))
            client.settimeout(0.25)
            return client
        except OSError as error:
            last_error = error
            time.sleep(0.05)
    raise RuntimeError(f"could not connect to {path}: {last_error}")


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


def wait_for(client: socket.socket, messages: list[dict], predicate, timeout: float = 8.0) -> None:
    deadline = time.time() + timeout
    buffer = b""

    while time.time() < deadline:
        try:
            chunk = client.recv(4096)
        except socket.timeout:
            chunk = b""

        if chunk:
            buffer += chunk
            while b"\n" in buffer:
                raw_line, buffer = buffer.split(b"\n", 1)
                if raw_line:
                    messages.append(json.loads(raw_line.decode("utf-8")))

        if predicate(messages):
            return

        time.sleep(0.05)

    raise AssertionError(f"missing expected IPC messages; received: {messages}")


def states(messages: list[dict]) -> list[str]:
    return [message["state"] for message in messages if "state" in message]


def global_token_messages(messages: list[dict]) -> list[dict]:
    return [message for message in messages if message.get("type") == "global_token_usage"]


def daily_token_messages(messages: list[dict]) -> list[dict]:
    return [message for message in messages if message.get("type") == "daily_token_usage"]


def state_count(messages: list[dict], state: str) -> int:
    return states(messages).count(state)


def has_state_activity(
    messages: list[dict],
    state: str,
    activity: Optional[str] = None,
    session_id: Optional[str] = None,
) -> bool:
    for message in messages:
        if message.get("state") != state:
            continue
        if activity is not None and message.get("activity_kind") != activity:
            continue
        if session_id is not None and message.get("session_id") != session_id:
            continue
        return True
    return False


def main() -> int:
    binary = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("codex-watcher/target/debug/codex-watcher")
    binary = binary.resolve()
    if not binary.exists():
        raise FileNotFoundError(binary)

    with tempfile.TemporaryDirectory(prefix="codex-island-ipc-") as tmp:
        root = Path(tmp)
        codex_home = root / "codex-home"
        sessions = codex_home / "sessions"
        sessions.mkdir(parents=True)
        socket_path = root / "codex-island.sock"

        environment = os.environ.copy()
        environment["CODEX_HOME"] = str(codex_home)
        environment["CODEX_ISLAND_SOCKET"] = str(socket_path)
        environment["RUST_LOG"] = "error"

        process = subprocess.Popen(
            [str(binary)],
            cwd=str(binary.parent),
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )

        try:
            wait_for_socket(socket_path)
            client = connect_socket(socket_path)
            messages: list[dict] = []
            wait_for(
                client,
                messages,
                lambda received: any(
                    message.get("total_tokens") == 0
                    and message.get("session_count") == 0
                    for message in global_token_messages(received)
                ),
            )

            session_dir = sessions / "2026" / "06" / "28"
            session_dir.mkdir(parents=True)
            rollout = session_dir / "rollout-smoke.jsonl"
            rollout.touch()
            time.sleep(0.25)

            append_jsonl(
                rollout,
                {
                    "type": "session_init",
                    "payload": {"session_id": "smoke-session", "model": "test"},
                },
            )
            append_jsonl(
                rollout,
                {
                    "type": "event_msg",
                    "payload": {"type": "user_message"},
                },
            )
            append_jsonl(
                rollout,
                {
                    "type": "event_msg",
                    "payload": token_count_payload(120, 40, 12, 0),
                },
            )

            wait_for(
                client,
                messages,
                lambda received: has_state_activity(received, "running", "reasoning")
                and any(message.get("total_output") == 12 for message in received)
                and any(
                    message.get("total_tokens") == 132
                    and message.get("session_count") == 1
                    for message in global_token_messages(received)
                )
                and any(
                    message.get("total_tokens") == 132
                    and message.get("request_count") == 1
                    for message in daily_token_messages(received)
                ),
            )
            append_jsonl(
                rollout,
                {
                    "type": "event_msg",
                    "payload": {
                        "type": "agent_message",
                        "phase": "final_answer",
                    },
                },
            )
            wait_for(
                client,
                messages,
                lambda received: has_state_activity(received, "running", "agent_message"),
            )
            wait_for(client, messages, lambda received: "idle" in states(received), timeout=9.0)

            append_jsonl(
                rollout,
                {
                    "type": "event_msg",
                    "payload": {"type": "user_message"},
                },
            )
            append_jsonl(
                rollout,
                {
                    "type": "event_msg",
                    "payload": {
                        "type": "awaiting_approval",
                        "tool": "shell",
                        "command": "echo smoke",
                    },
                },
            )
            wait_for(client, messages, lambda received: "waiting_for_input" in states(received))

            append_jsonl(
                rollout,
                {
                    "type": "event_msg",
                    "payload": {
                        "type": "tool_approval",
                        "approved": True,
                    },
                },
            )
            wait_for(
                client,
                messages,
                lambda received: has_state_activity(
                    received,
                    "running",
                    "command_execution",
                ),
            )

            append_jsonl(
                rollout,
                {
                    "type": "event_msg",
                    "payload": token_count_payload(220, 120, 30, 2),
                },
            )
            wait_for(
                client,
                messages,
                lambda received: has_state_activity(received, "running", "command_execution")
                and any(
                    message.get("total_input") == 220
                    and message.get("total_cached_input") == 120
                    and message.get("total_output") == 30
                    and message.get("delta_output") == 18
                    for message in received
                )
                and any(
                    message.get("total_input") == 220
                    and message.get("total_cached_input") == 120
                    and message.get("total_output") == 30
                    and message.get("total_reasoning") == 2
                    and message.get("total_tokens") == 250
                    and message.get("session_count") == 1
                    for message in global_token_messages(received)
                )
                and any(
                    message.get("total_tokens") == 250
                    and message.get("request_count") == 2
                    for message in daily_token_messages(received)
                ),
            )

            append_jsonl(
                rollout,
                {
                    "type": "event_msg",
                    "payload": {"type": "assistant_message_stop"},
                },
            )
            wait_for(client, messages, lambda received: state_count(received, "idle") >= 2)

            append_jsonl(
                rollout,
                {
                    "type": "event_msg",
                    "payload": {
                        "type": "turn_error",
                        "message": "private text should be sanitized",
                    },
                },
            )
            wait_for(client, messages, lambda received: "error" in states(received))
            wait_for(client, messages, lambda received: state_count(received, "idle") >= 3, timeout=5.0)

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
            wait_for(client, messages, lambda received: state_count(received, "waiting_for_input") >= 2)

            append_jsonl(
                rollout,
                {
                    "type": "event_msg",
                    "payload": {
                        "type": "tool_approval",
                        "approved": False,
                    },
                },
            )
            wait_for(client, messages, lambda received: state_count(received, "idle") >= 4)

            fallback_session_id = "019f0d79-a330-7352-97a3-9032d7b038db"
            fallback_rollout = session_dir / f"rollout-2026-06-28T17-05-03-{fallback_session_id}.jsonl"
            fallback_rollout.touch()
            time.sleep(0.25)

            append_jsonl(
                fallback_rollout,
                {
                    "type": "event_msg",
                    "payload": {"type": "task_started"},
                },
            )
            wait_for(
                client,
                messages,
                lambda received: any(
                    message.get("session_id") == fallback_session_id
                    and message.get("state") == "running"
                    and message.get("activity_kind") == "reasoning"
                    for message in received
                ),
            )

            append_jsonl(
                fallback_rollout,
                {
                    "type": "event_msg",
                    "payload": token_count_payload(80, 20, 7, 1),
                },
            )
            wait_for(
                client,
                messages,
                lambda received: any(
                    message.get("session_id") == fallback_session_id
                    and message.get("state") == "running"
                    and message.get("activity_kind") == "reasoning"
                    for message in received
                )
                and any(
                    message.get("session_id") == fallback_session_id
                    and message.get("total_output") == 7
                    for message in received
                )
                and any(
                    message.get("total_input") == 300
                    and message.get("total_cached_input") == 140
                    and message.get("total_output") == 37
                    and message.get("total_reasoning") == 3
                    and message.get("total_tokens") == 337
                    and message.get("session_count") == 2
                    for message in global_token_messages(received)
                ),
            )

            replay_client = connect_socket(socket_path)
            replay_messages: list[dict] = []
            wait_for(
                replay_client,
                replay_messages,
                lambda received: any(
                    message.get("total_tokens") == 337
                    and message.get("session_count") == 2
                    for message in global_token_messages(received)
                )
                and any(
                    message.get("session_id") == fallback_session_id
                    and message.get("total_output") == 7
                    for message in received
                )
                and any(message.get("state") == "running" for message in received),
            )
            replay_client.close()

            append_jsonl(
                fallback_rollout,
                {
                    "type": "event_msg",
                    "payload": {
                        "type": "patch_apply_end",
                        "success": True,
                        "status": "completed",
                    },
                },
            )
            append_jsonl(
                fallback_rollout,
                {
                    "type": "event_msg",
                    "payload": {
                        "type": "turn_aborted",
                        "turn_id": "smoke-turn",
                        "reason": "interrupted",
                        "message": "private abort details",
                    },
                },
            )
            wait_for(
                client,
                messages,
                lambda received: any(
                    message.get("session_id") == fallback_session_id
                    and message.get("state") == "idle"
                    and message.get("activity_kind") == "none"
                    and message.get("turn_state") == "interrupted"
                    for message in received
                ),
            )

            append_jsonl(
                fallback_rollout,
                {
                    "type": "event_msg",
                    "payload": token_count_payload(90, 20, 8, 1),
                },
            )
            wait_for(
                client,
                messages,
                lambda received: any(
                    message.get("session_id") == fallback_session_id
                    and message.get("total_output") == 8
                    for message in received
                ),
            )

            terminal_replay_client = connect_socket(socket_path)
            terminal_replay_messages: list[dict] = []
            wait_for(
                terminal_replay_client,
                terminal_replay_messages,
                lambda received: any(
                    message.get("session_id") == fallback_session_id
                    and message.get("state") == "idle"
                    and message.get("turn_state") == "interrupted"
                    for message in received
                ),
            )
            if any(
                message.get("session_id") == fallback_session_id
                and message.get("state") == "running"
                for message in terminal_replay_messages
            ):
                raise AssertionError("terminal replay retained stale running state")
            terminal_replay_client.close()

            if not any(message.get("state") == "waiting_for_input" for message in messages):
                raise AssertionError("waiting_for_input state missing")
            if any(message.get("message") for message in messages):
                raise AssertionError(f"unsanitized private error message leaked: {messages}")

            print(f"IPC smoke test passed ({len(messages)} messages, states={states(messages)})")
            return 0
        finally:
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
            shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    raise SystemExit(main())
