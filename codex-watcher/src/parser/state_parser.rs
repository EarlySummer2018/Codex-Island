use crate::parser::RawEvent;
use crate::token_usage::token_count_value;
use crate::watcher::jsonl_watcher::RawJsonlLine;
use crate::watcher::ws_client::WsStateEvent;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;
use tokio::time::{Duration, Instant};
use tracing::{debug, info};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum SessionState {
    Idle,
    Thinking,
    Streaming,
    AwaitingInput,
    Error,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum AwaitReason {
    ToolApproval {
        tool: String,
        command: Option<String>,
    },
    Question {
        text: Option<String>,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SessionStateEvent {
    pub session_id: String,
    pub state: SessionState,
    pub timestamp: DateTime<Utc>,
    pub await_reason: Option<AwaitReason>,
}

#[derive(Debug, Clone)]
struct SessionTracker {
    state: SessionState,
    last_token_time: Option<Instant>,
    last_output_tokens: u64,
    error_since: Option<Instant>,
    streaming_timeout: Duration,
    error_timeout: Duration,
}

impl Default for SessionTracker {
    fn default() -> Self {
        Self {
            state: SessionState::Idle,
            last_token_time: None,
            last_output_tokens: 0,
            error_since: None,
            streaming_timeout: Duration::from_secs(4),
            error_timeout: Duration::from_secs(3),
        }
    }
}

#[derive(Debug, Default)]
pub struct StateParser {
    trackers: HashMap<String, SessionTracker>,
}

impl StateParser {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn process_event(&mut self, event: &RawEvent) -> Option<SessionStateEvent> {
        match event {
            RawEvent::JsonlLine(line) => self.process_jsonl(line),
            RawEvent::WsMessage(ws_event) => self.process_ws(ws_event),
        }
    }

    pub fn process_jsonl(&mut self, line: &RawJsonlLine) -> Option<SessionStateEvent> {
        let session_id = line.session_id.as_deref().unwrap_or("unknown").to_string();
        let payload_type = line.payload_type.as_deref()?;

        match payload_type {
            "task_started" => self.transition(&session_id, SessionState::Thinking, None),
            "user_message" => {
                if self
                    .trackers
                    .get(&session_id)
                    .map(|tracker| tracker.state == SessionState::Streaming)
                    .unwrap_or(false)
                {
                    None
                } else {
                    self.transition(&session_id, SessionState::Thinking, None)
                }
            }
            "assistant_message_start" => {
                debug!("[{session_id}] assistant_message_start");
                None
            }
            "agent_message" => {
                if self
                    .trackers
                    .get(&session_id)
                    .map(|tracker| tracker.state == SessionState::AwaitingInput)
                    .unwrap_or(false)
                {
                    None
                } else {
                    self.transition(&session_id, SessionState::Streaming, None)
                }
            }
            "token_count" => self.process_token_count(&session_id, &line.parsed),
            "assistant_message_stop" => self.transition(&session_id, SessionState::Idle, None),
            "task_complete" => self.transition(&session_id, SessionState::Idle, None),
            "awaiting_approval" => {
                let reason = AwaitReason::ToolApproval {
                    tool: string_payload(&line.parsed, "tool")
                        .unwrap_or_else(|| "unknown".to_string()),
                    command: string_payload(&line.parsed, "command"),
                };
                self.transition(&session_id, SessionState::AwaitingInput, Some(reason))
            }
            "tool_approval" => {
                if bool_payload(&line.parsed, "approved").unwrap_or(false) {
                    self.transition(&session_id, SessionState::Thinking, None)
                } else {
                    self.transition(&session_id, SessionState::Idle, None)
                }
            }
            "error" | "turn_error" | "stream_error" => Some(self.set_error(&session_id)),
            _ => None,
        }
    }

    pub fn process_ws(&mut self, ws_event: &WsStateEvent) -> Option<SessionStateEvent> {
        let session_id = ws_session_id(&ws_event.params);

        match ws_event.method.as_str() {
            "turn/start" => self.transition(&session_id, SessionState::Thinking, None),
            "turn/stop" => self.transition(&session_id, SessionState::Idle, None),
            "tool/approval/request" => {
                let reason = AwaitReason::ToolApproval {
                    tool: ws_event
                        .params
                        .get("toolName")
                        .or_else(|| ws_event.params.get("tool"))
                        .and_then(|value| value.as_str())
                        .unwrap_or("unknown")
                        .to_string(),
                    command: ws_event
                        .params
                        .get("command")
                        .and_then(|value| value.as_str())
                        .map(ToOwned::to_owned),
                };
                self.transition(&session_id, SessionState::AwaitingInput, Some(reason))
            }
            _ => None,
        }
    }

    pub fn set_error(&mut self, session_id: &str) -> SessionStateEvent {
        let tracker = self.trackers.entry(session_id.to_string()).or_default();
        tracker.error_since = Some(Instant::now());
        tracker.state = SessionState::Error;

        SessionStateEvent {
            session_id: session_id.to_string(),
            state: SessionState::Error,
            timestamp: Utc::now(),
            await_reason: None,
        }
    }

    pub fn check_timeouts(&mut self) -> Vec<SessionStateEvent> {
        let now = Instant::now();
        let mut events = Vec::new();

        for (session_id, tracker) in self.trackers.iter_mut() {
            match tracker.state {
                SessionState::Streaming => {
                    if let Some(last_token_time) = tracker.last_token_time {
                        if now.duration_since(last_token_time) >= tracker.streaming_timeout {
                            info!("[{session_id}] streaming timeout -> Idle");
                            tracker.state = SessionState::Idle;
                            events.push(SessionStateEvent {
                                session_id: session_id.clone(),
                                state: SessionState::Idle,
                                timestamp: Utc::now(),
                                await_reason: None,
                            });
                        }
                    }
                }
                SessionState::Error => {
                    if let Some(error_since) = tracker.error_since {
                        if now.duration_since(error_since) >= tracker.error_timeout {
                            info!("[{session_id}] error timeout -> Idle");
                            tracker.state = SessionState::Idle;
                            tracker.error_since = None;
                            events.push(SessionStateEvent {
                                session_id: session_id.clone(),
                                state: SessionState::Idle,
                                timestamp: Utc::now(),
                                await_reason: None,
                            });
                        }
                    }
                }
                _ => {}
            }
        }

        events
    }

    fn process_token_count(
        &mut self,
        session_id: &str,
        parsed: &Value,
    ) -> Option<SessionStateEvent> {
        let output_tokens = parsed
            .get("payload")
            .and_then(|payload| token_count_value(payload, "output_tokens"))
            .unwrap_or(0);

        let tracker = self.trackers.entry(session_id.to_string()).or_default();

        if output_tokens < tracker.last_output_tokens {
            tracker.last_output_tokens = output_tokens;
            return None;
        }

        if output_tokens == tracker.last_output_tokens {
            return None;
        }

        tracker.last_output_tokens = output_tokens;
        tracker.last_token_time = Some(Instant::now());

        if tracker.state == SessionState::AwaitingInput {
            return None;
        }

        self.transition(session_id, SessionState::Streaming, None)
    }

    fn transition(
        &mut self,
        session_id: &str,
        state: SessionState,
        await_reason: Option<AwaitReason>,
    ) -> Option<SessionStateEvent> {
        let tracker = self.trackers.entry(session_id.to_string()).or_default();

        if tracker.state == state {
            return None;
        }

        info!("[{session_id}] {:?} -> {:?}", tracker.state, state);
        tracker.state = state.clone();

        if state == SessionState::Streaming {
            tracker.last_token_time = Some(Instant::now());
        }
        if state != SessionState::Error {
            tracker.error_since = None;
        }

        Some(SessionStateEvent {
            session_id: session_id.to_string(),
            state,
            timestamp: Utc::now(),
            await_reason,
        })
    }
}

fn string_payload(parsed: &Value, key: &str) -> Option<String> {
    parsed
        .get("payload")
        .and_then(|payload| payload.get(key))
        .and_then(|value| value.as_str())
        .map(ToOwned::to_owned)
}

fn bool_payload(parsed: &Value, key: &str) -> Option<bool> {
    parsed
        .get("payload")
        .and_then(|payload| payload.get(key))
        .and_then(|value| value.as_bool())
}

fn ws_session_id(params: &Value) -> String {
    for key in [
        "session_id",
        "sessionId",
        "thread_id",
        "threadId",
        "turn_id",
        "turnId",
    ] {
        if let Some(value) = params.get(key).and_then(|value| value.as_str()) {
            return value.to_string();
        }
    }

    "ws".to_string()
}

#[cfg(test)]
mod tests {
    use super::{AwaitReason, SessionState, StateParser};
    use crate::watcher::jsonl_watcher::RawJsonlLine;
    use crate::watcher::ws_client::WsStateEvent;
    use serde_json::{json, Value};
    use std::path::PathBuf;
    use std::thread;
    use tokio::time::Duration;

    fn jsonl(payload: Value) -> RawJsonlLine {
        let payload_type = payload
            .get("type")
            .and_then(|value| value.as_str())
            .map(ToOwned::to_owned);

        RawJsonlLine {
            session_file: PathBuf::from("/tmp/rollout-test.jsonl"),
            session_id: Some("sess-1".to_string()),
            event_type: "event_msg".to_string(),
            payload_type,
            parsed: json!({
                "type": "event_msg",
                "payload": payload,
            }),
        }
    }

    fn token_count(output_tokens: u64) -> RawJsonlLine {
        jsonl(json!({
            "type": "token_count",
            "input_tokens": 100,
            "cached_input_tokens": 50,
            "output_tokens": output_tokens,
            "reasoning_tokens": 0,
        }))
    }

    fn real_codex_token_count(output_tokens: u64) -> RawJsonlLine {
        jsonl(json!({
            "type": "token_count",
            "info": {
                "total_token_usage": {
                    "input_tokens": 100,
                    "cached_input_tokens": 50,
                    "output_tokens": output_tokens,
                    "reasoning_output_tokens": 0,
                    "total_tokens": 100 + output_tokens,
                }
            }
        }))
    }

    fn task_started() -> RawJsonlLine {
        jsonl(json!({ "type": "task_started" }))
    }

    fn task_complete() -> RawJsonlLine {
        jsonl(json!({ "type": "task_complete" }))
    }

    fn agent_message() -> RawJsonlLine {
        jsonl(json!({ "type": "agent_message", "phase": "commentary" }))
    }

    #[test]
    fn user_message_moves_to_thinking() {
        let mut parser = StateParser::new();
        let event = parser
            .process_jsonl(&jsonl(json!({ "type": "user_message" })))
            .unwrap();

        assert_eq!(event.state, SessionState::Thinking);
    }

    #[test]
    fn task_started_moves_to_thinking() {
        let mut parser = StateParser::new();
        let event = parser.process_jsonl(&task_started()).unwrap();

        assert_eq!(event.state, SessionState::Thinking);
    }

    #[test]
    fn output_token_increase_moves_to_streaming() {
        let mut parser = StateParser::new();
        parser.process_jsonl(&jsonl(json!({ "type": "user_message" })));

        let event = parser.process_jsonl(&token_count(10)).unwrap();

        assert_eq!(event.state, SessionState::Streaming);
    }

    #[test]
    fn nested_output_token_increase_moves_to_streaming() {
        let mut parser = StateParser::new();
        parser.process_jsonl(&jsonl(json!({ "type": "user_message" })));

        let event = parser.process_jsonl(&real_codex_token_count(10)).unwrap();

        assert_eq!(event.state, SessionState::Streaming);
    }

    #[test]
    fn duplicate_user_message_does_not_regress_streaming_to_thinking() {
        let mut parser = StateParser::new();
        parser.process_jsonl(&jsonl(json!({ "type": "user_message" })));
        parser.process_jsonl(&token_count(10)).unwrap();

        let event = parser.process_jsonl(&jsonl(json!({ "type": "user_message" })));

        assert!(event.is_none());
        assert_eq!(
            parser.trackers.get("sess-1").unwrap().state,
            SessionState::Streaming
        );
    }

    #[test]
    fn assistant_stop_moves_to_idle() {
        let mut parser = StateParser::new();
        parser.process_jsonl(&jsonl(json!({ "type": "user_message" })));
        parser.process_jsonl(&token_count(10));

        let event = parser
            .process_jsonl(&jsonl(json!({ "type": "assistant_message_stop" })))
            .unwrap();

        assert_eq!(event.state, SessionState::Idle);
    }

    #[test]
    fn task_complete_moves_to_idle() {
        let mut parser = StateParser::new();
        parser.process_jsonl(&task_started());

        let event = parser.process_jsonl(&task_complete()).unwrap();

        assert_eq!(event.state, SessionState::Idle);
    }

    #[test]
    fn agent_message_moves_to_streaming() {
        let mut parser = StateParser::new();
        parser.process_jsonl(&task_started());

        let event = parser.process_jsonl(&agent_message()).unwrap();

        assert_eq!(event.state, SessionState::Streaming);
    }

    #[test]
    fn awaiting_approval_has_tool_reason() {
        let mut parser = StateParser::new();
        let event = parser
            .process_jsonl(&jsonl(json!({
                "type": "awaiting_approval",
                "tool": "shell",
                "command": "cargo test"
            })))
            .unwrap();

        assert_eq!(event.state, SessionState::AwaitingInput);
        assert_eq!(
            event.await_reason,
            Some(AwaitReason::ToolApproval {
                tool: "shell".to_string(),
                command: Some("cargo test".to_string()),
            })
        );
    }

    #[test]
    fn approval_result_moves_to_thinking_or_idle() {
        let mut parser = StateParser::new();
        parser.process_jsonl(&jsonl(json!({ "type": "awaiting_approval" })));

        let approved = parser
            .process_jsonl(&jsonl(json!({ "type": "tool_approval", "approved": true })))
            .unwrap();
        assert_eq!(approved.state, SessionState::Thinking);

        parser.process_jsonl(&jsonl(json!({ "type": "awaiting_approval" })));
        let denied = parser
            .process_jsonl(&jsonl(
                json!({ "type": "tool_approval", "approved": false }),
            ))
            .unwrap();
        assert_eq!(denied.state, SessionState::Idle);
    }

    #[test]
    fn error_event_moves_to_error() {
        let mut parser = StateParser::new();

        let event = parser
            .process_jsonl(&jsonl(json!({ "type": "turn_error" })))
            .unwrap();

        assert_eq!(event.state, SessionState::Error);
    }

    #[test]
    fn websocket_turn_events_drive_state() {
        let mut parser = StateParser::new();

        let start = parser
            .process_ws(&WsStateEvent {
                method: "turn/start".to_string(),
                params: json!({ "turn_id": "turn-1" }),
            })
            .unwrap();
        assert_eq!(start.state, SessionState::Thinking);

        let stop = parser
            .process_ws(&WsStateEvent {
                method: "turn/stop".to_string(),
                params: json!({ "turn_id": "turn-1" }),
            })
            .unwrap();
        assert_eq!(stop.state, SessionState::Idle);
    }

    #[test]
    fn streaming_timeout_returns_to_idle() {
        let mut parser = StateParser::new();
        parser.process_jsonl(&jsonl(json!({ "type": "user_message" })));
        parser.process_jsonl(&token_count(10));

        parser.trackers.get_mut("sess-1").unwrap().streaming_timeout = Duration::from_millis(1);

        thread::sleep(std::time::Duration::from_millis(5));
        let events = parser.check_timeouts();

        assert_eq!(events.len(), 1);
        assert_eq!(events[0].state, SessionState::Idle);
    }

    #[test]
    fn error_timeout_returns_to_idle() {
        let mut parser = StateParser::new();
        parser.set_error("sess-1");
        parser.trackers.get_mut("sess-1").unwrap().error_timeout = Duration::from_millis(1);

        thread::sleep(std::time::Duration::from_millis(5));
        let events = parser.check_timeouts();

        assert_eq!(events.len(), 1);
        assert_eq!(events[0].state, SessionState::Idle);
    }
}
