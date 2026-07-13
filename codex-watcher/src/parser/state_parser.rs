use crate::parser::RawEvent;
use crate::token_usage::token_count_value;
use crate::watcher::jsonl_watcher::RawJsonlLine;
use crate::watcher::ws_client::WsStateEvent;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;
use tokio::time::{Duration, Instant};
use tracing::info;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum SessionState {
    NotLoaded,
    Idle,
    Running,
    WaitingForInput,
    ReadyForReview,
    Error,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ActivityKind {
    None,
    Reasoning,
    CommandExecution,
    FileChange,
    WebSearch,
    AgentMessage,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum TurnState {
    InProgress,
    Completed,
    Interrupted,
    Failed,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum StateSource {
    AppServer,
    Jsonl,
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

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SessionStateEvent {
    pub session_id: String,
    pub state: SessionState,
    pub activity_kind: ActivityKind,
    pub turn_state: Option<TurnState>,
    pub source: StateSource,
    pub timestamp: DateTime<Utc>,
    pub await_reason: Option<AwaitReason>,
}

#[derive(Debug, Clone)]
struct SessionTracker {
    state: SessionState,
    activity_kind: ActivityKind,
    turn_state: Option<TurnState>,
    await_reason: Option<AwaitReason>,
    last_token_time: Option<Instant>,
    last_output_tokens: u64,
    error_since: Option<Instant>,
    running_timeout: Duration,
    error_timeout: Duration,
    fallback_file_change_pin_until: Option<Instant>,
    fallback_file_change_pin_duration: Duration,
    runtime_locked_to_ws: bool,
    activity_locked_to_ws: bool,
}

impl Default for SessionTracker {
    fn default() -> Self {
        Self {
            state: SessionState::NotLoaded,
            activity_kind: ActivityKind::None,
            turn_state: None,
            await_reason: None,
            last_token_time: None,
            last_output_tokens: 0,
            error_since: None,
            running_timeout: Duration::from_secs(4),
            error_timeout: Duration::from_secs(3),
            fallback_file_change_pin_until: None,
            fallback_file_change_pin_duration: Duration::from_secs(3),
            runtime_locked_to_ws: false,
            activity_locked_to_ws: false,
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
            "task_started" | "user_message" | "reasoning" => {
                self.apply_jsonl_running(&session_id, ActivityKind::Reasoning)
            }
            "agent_message" => self.apply_jsonl_running(&session_id, ActivityKind::AgentMessage),
            "tool_call" => self.apply_jsonl_running(
                &session_id,
                tool_name_to_activity(string_payload(&line.parsed, "tool").as_deref()),
            ),
            "web_search" => self.apply_jsonl_running(&session_id, ActivityKind::WebSearch),
            "patch_apply_end" => self.apply_jsonl_running(&session_id, ActivityKind::FileChange),
            "token_count" => self.process_token_count(&session_id, &line.parsed),
            "assistant_message_stop" | "task_complete" => {
                self.update_tracker(&session_id, StateSource::Jsonl, |tracker| {
                    if tracker.runtime_locked_to_ws {
                        return;
                    }
                    tracker.state = SessionState::Idle;
                    tracker.activity_kind = ActivityKind::None;
                    tracker.turn_state = Some(TurnState::Completed);
                })
            }
            "awaiting_approval" => {
                let tool =
                    string_payload(&line.parsed, "tool").unwrap_or_else(|| "unknown".to_string());
                let command = string_payload(&line.parsed, "command");
                let activity_kind = tool_name_to_activity(Some(tool.as_str()));
                self.update_tracker(&session_id, StateSource::Jsonl, |tracker| {
                    if tracker.runtime_locked_to_ws {
                        return;
                    }
                    if !tracker.activity_locked_to_ws {
                        tracker.activity_kind = activity_kind;
                    }
                    tracker.state = SessionState::WaitingForInput;
                    tracker.turn_state = Some(TurnState::InProgress);
                    tracker.await_reason = Some(AwaitReason::ToolApproval { tool, command });
                })
            }
            "tool_approval" => {
                let approved = bool_payload(&line.parsed, "approved").unwrap_or(false);
                self.update_tracker(&session_id, StateSource::Jsonl, |tracker| {
                    if tracker.runtime_locked_to_ws {
                        return;
                    }
                    tracker.await_reason = None;
                    if approved {
                        tracker.state = SessionState::Running;
                        if !tracker.activity_locked_to_ws {
                            if tracker.activity_kind == ActivityKind::None {
                                tracker.activity_kind = ActivityKind::CommandExecution;
                            }
                        }
                        tracker.turn_state = Some(TurnState::InProgress);
                    } else {
                        tracker.state = SessionState::Idle;
                        tracker.activity_kind = ActivityKind::None;
                        tracker.turn_state = Some(TurnState::Interrupted);
                    }
                })
            }
            "error" | "turn_error" | "stream_error" => {
                Some(self.set_error(&session_id, StateSource::Jsonl))
            }
            _ => None,
        }
    }

    pub fn process_ws(&mut self, ws_event: &WsStateEvent) -> Option<SessionStateEvent> {
        let session_id = ws_session_id(&ws_event.params);

        match ws_event.method.as_str() {
            "thread/status/changed" => {
                let runtime_state = runtime_state_from_ws_status(
                    ws_event.params.get("status").unwrap_or(&Value::Null),
                );
                self.update_tracker(&session_id, StateSource::AppServer, |tracker| {
                    tracker.runtime_locked_to_ws = true;
                    tracker.state = runtime_state.clone();
                    if matches!(
                        runtime_state,
                        SessionState::Idle | SessionState::NotLoaded | SessionState::ReadyForReview
                    ) {
                        tracker.turn_state = None;
                    }
                })
            }
            "turn/started" | "turn/start" => {
                self.update_tracker(&session_id, StateSource::AppServer, |tracker| {
                    tracker.runtime_locked_to_ws = true;
                    tracker.state = SessionState::Running;
                    tracker.turn_state = Some(TurnState::InProgress);
                    if !tracker.activity_locked_to_ws && tracker.activity_kind == ActivityKind::None
                    {
                        tracker.activity_kind = ActivityKind::Reasoning;
                    }
                })
            }
            "turn/completed" => {
                let turn_state = ws_turn_state(&ws_event.params).unwrap_or(TurnState::Completed);
                self.update_tracker(&session_id, StateSource::AppServer, |tracker| {
                    tracker.runtime_locked_to_ws = true;
                    tracker.turn_state = Some(turn_state.clone());
                    tracker.await_reason = None;

                    match turn_state {
                        TurnState::Failed => {
                            tracker.state = SessionState::Error;
                            tracker.activity_kind = ActivityKind::None;
                        }
                        TurnState::Completed | TurnState::Interrupted => {
                            tracker.state = SessionState::Idle;
                            tracker.activity_kind = ActivityKind::None;
                        }
                        TurnState::InProgress => {
                            tracker.state = SessionState::Running;
                        }
                    }
                })
            }
            "turn/stop" => self.update_tracker(&session_id, StateSource::AppServer, |tracker| {
                tracker.runtime_locked_to_ws = true;
                tracker.state = SessionState::Idle;
                tracker.activity_kind = ActivityKind::None;
                tracker.turn_state = Some(TurnState::Completed);
                tracker.await_reason = None;
            }),
            "item/started" | "item/completed" => {
                let item_type = ws_item_type(&ws_event.params)?;
                let item_status = ws_item_status(&ws_event.params);
                self.update_tracker(&session_id, StateSource::AppServer, |tracker| {
                    tracker.activity_locked_to_ws = true;

                    if is_review_item(&item_type) {
                        tracker.runtime_locked_to_ws = true;
                        tracker.state = SessionState::ReadyForReview;
                        tracker.activity_kind = ActivityKind::None;
                        tracker.turn_state = Some(TurnState::Completed);
                        tracker.await_reason = None;
                        return;
                    }

                    let activity_kind = item_type_to_activity_kind(&item_type);
                    if activity_kind == ActivityKind::None {
                        return;
                    }

                    match item_status.as_deref() {
                        Some("declined") => {
                            tracker.runtime_locked_to_ws = true;
                            tracker.state = SessionState::Idle;
                            tracker.activity_kind = ActivityKind::None;
                            tracker.turn_state = Some(TurnState::Interrupted);
                            tracker.await_reason = None;
                        }
                        Some("failed") => {
                            tracker.runtime_locked_to_ws = true;
                            tracker.state = SessionState::Error;
                            tracker.activity_kind = ActivityKind::None;
                            tracker.turn_state = Some(TurnState::Failed);
                            tracker.await_reason = None;
                        }
                        Some("completed") if ws_event.method == "item/completed" => {
                            tracker.await_reason = None;
                            if tracker.state == SessionState::WaitingForInput {
                                tracker.state = SessionState::Running;
                            }
                            tracker.activity_kind = ActivityKind::None;
                        }
                        _ => {
                            tracker.state = SessionState::Running;
                            tracker.turn_state = Some(TurnState::InProgress);
                            tracker.activity_kind = activity_kind;
                        }
                    }
                })
            }
            "item/commandExecution/requestApproval" | "tool/approval/request" => {
                let command =
                    ws_first_string(&ws_event.params, &["command", "title", "message", "text"]);
                self.update_tracker(&session_id, StateSource::AppServer, |tracker| {
                    tracker.runtime_locked_to_ws = true;
                    tracker.activity_locked_to_ws = true;
                    tracker.state = SessionState::WaitingForInput;
                    tracker.activity_kind = ActivityKind::CommandExecution;
                    tracker.turn_state = Some(TurnState::InProgress);
                    tracker.await_reason = Some(AwaitReason::ToolApproval {
                        tool: "command_execution".to_string(),
                        command,
                    });
                })
            }
            "item/fileChange/requestApproval" => {
                let command = ws_first_string(
                    &ws_event.params,
                    &["reason", "message", "text", "grantRoot"],
                );
                self.update_tracker(&session_id, StateSource::AppServer, |tracker| {
                    tracker.runtime_locked_to_ws = true;
                    tracker.activity_locked_to_ws = true;
                    tracker.state = SessionState::WaitingForInput;
                    tracker.activity_kind = ActivityKind::FileChange;
                    tracker.turn_state = Some(TurnState::InProgress);
                    tracker.await_reason = Some(AwaitReason::ToolApproval {
                        tool: "file_change".to_string(),
                        command,
                    });
                })
            }
            "item/tool/requestUserInput" | "item/requestUserInput" => {
                let text =
                    ws_first_string(&ws_event.params, &["prompt", "message", "text", "title"]);
                self.update_tracker(&session_id, StateSource::AppServer, |tracker| {
                    tracker.runtime_locked_to_ws = true;
                    tracker.state = SessionState::WaitingForInput;
                    tracker.turn_state = Some(TurnState::InProgress);
                    tracker.await_reason = Some(AwaitReason::Question { text });
                })
            }
            _ => None,
        }
    }

    pub fn set_error(&mut self, session_id: &str, source: StateSource) -> SessionStateEvent {
        self.update_tracker(session_id, source, |tracker| {
            if source == StateSource::AppServer {
                tracker.runtime_locked_to_ws = true;
            }
            tracker.state = SessionState::Error;
            tracker.activity_kind = ActivityKind::None;
            tracker.turn_state = Some(TurnState::Failed);
            tracker.await_reason = None;
        })
        .expect("error transition should always emit an event")
    }

    pub fn check_timeouts(&mut self) -> Vec<SessionStateEvent> {
        let now = Instant::now();
        let mut session_ids = Vec::new();
        let mut error_session_ids = Vec::new();

        for (session_id, tracker) in &self.trackers {
            if tracker.state == SessionState::Running
                && !tracker.runtime_locked_to_ws
                && tracker.activity_kind == ActivityKind::AgentMessage
            {
                if let Some(last_token_time) = tracker.last_token_time {
                    if now.duration_since(last_token_time) >= tracker.running_timeout {
                        session_ids.push(session_id.clone());
                    }
                }
            }

            if tracker.state == SessionState::Error {
                if let Some(error_since) = tracker.error_since {
                    if now.duration_since(error_since) >= tracker.error_timeout {
                        error_session_ids.push(session_id.clone());
                    }
                }
            }
        }

        let mut events = Vec::new();

        for session_id in session_ids {
            if let Some(event) = self.update_tracker(&session_id, StateSource::Jsonl, |tracker| {
                tracker.state = SessionState::Idle;
                tracker.activity_kind = ActivityKind::None;
                tracker.turn_state = Some(TurnState::Completed);
            }) {
                info!("[{session_id}] running timeout -> idle");
                events.push(event);
            }
        }

        for session_id in error_session_ids {
            let source = self
                .trackers
                .get(&session_id)
                .map(|tracker| {
                    if tracker.runtime_locked_to_ws {
                        StateSource::AppServer
                    } else {
                        StateSource::Jsonl
                    }
                })
                .unwrap_or(StateSource::Jsonl);
            if let Some(event) = self.update_tracker(&session_id, source, |tracker| {
                tracker.state = SessionState::Idle;
                tracker.activity_kind = ActivityKind::None;
                tracker.turn_state = None;
            }) {
                info!("[{session_id}] error timeout -> idle");
                events.push(event);
            }
        }

        events
    }

    fn apply_jsonl_running(
        &mut self,
        session_id: &str,
        activity_kind: ActivityKind,
    ) -> Option<SessionStateEvent> {
        self.update_tracker(session_id, StateSource::Jsonl, |tracker| {
            if !tracker.runtime_locked_to_ws {
                tracker.state = SessionState::Running;
                tracker.turn_state = Some(TurnState::InProgress);
            }
            if !tracker.activity_locked_to_ws
                && fallback_activity_can_override(tracker, activity_kind.clone())
            {
                tracker.activity_kind = activity_kind;
                if tracker.activity_kind == ActivityKind::FileChange {
                    tracker.fallback_file_change_pin_until =
                        Some(Instant::now() + tracker.fallback_file_change_pin_duration);
                }
            }
        })
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

        self.update_tracker(session_id, StateSource::Jsonl, |tracker| {
            if matches!(
                tracker.state,
                SessionState::WaitingForInput | SessionState::ReadyForReview | SessionState::Error
            ) {
                return;
            }

            if !tracker.runtime_locked_to_ws {
                tracker.state = SessionState::Running;
                tracker.turn_state = Some(TurnState::InProgress);
            }

            if !tracker.activity_locked_to_ws
                && fallback_activity_can_override(tracker, ActivityKind::AgentMessage)
            {
                tracker.activity_kind = ActivityKind::AgentMessage;
            }
        })
    }

    fn update_tracker<F>(
        &mut self,
        session_id: &str,
        source: StateSource,
        update: F,
    ) -> Option<SessionStateEvent>
    where
        F: FnOnce(&mut SessionTracker),
    {
        let tracker = self.trackers.entry(session_id.to_string()).or_default();
        let previous = (
            tracker.state.clone(),
            tracker.activity_kind.clone(),
            tracker.turn_state.clone(),
            tracker.await_reason.clone(),
        );

        update(tracker);
        normalize_tracker(tracker);

        let current = (
            tracker.state.clone(),
            tracker.activity_kind.clone(),
            tracker.turn_state.clone(),
            tracker.await_reason.clone(),
        );

        if previous == current {
            return None;
        }

        info!(
            "[{session_id}] state={:?} activity={:?} turn={:?} source={:?}",
            tracker.state, tracker.activity_kind, tracker.turn_state, source
        );

        Some(SessionStateEvent {
            session_id: session_id.to_string(),
            state: tracker.state.clone(),
            activity_kind: tracker.activity_kind.clone(),
            turn_state: tracker.turn_state.clone(),
            source,
            timestamp: Utc::now(),
            await_reason: tracker.await_reason.clone(),
        })
    }
}

fn normalize_tracker(tracker: &mut SessionTracker) {
    if let Some(pin_until) = tracker.fallback_file_change_pin_until {
        if Instant::now() >= pin_until {
            tracker.fallback_file_change_pin_until = None;
        }
    }

    match tracker.state {
        SessionState::NotLoaded
        | SessionState::Idle
        | SessionState::ReadyForReview
        | SessionState::Error => {
            tracker.activity_kind = ActivityKind::None;
            tracker.fallback_file_change_pin_until = None;
        }
        SessionState::Running | SessionState::WaitingForInput => {}
    }

    if tracker.state != SessionState::WaitingForInput {
        tracker.await_reason = None;
    }

    if tracker.state == SessionState::Error {
        tracker.error_since.get_or_insert_with(Instant::now);
    } else {
        tracker.error_since = None;
    }
}

fn fallback_activity_can_override(tracker: &SessionTracker, next: ActivityKind) -> bool {
    if tracker.activity_kind != ActivityKind::FileChange {
        return true;
    }

    let pinned = tracker
        .fallback_file_change_pin_until
        .map(|pin_until| Instant::now() < pin_until)
        .unwrap_or(false);

    if !pinned {
        return true;
    }

    matches!(next, ActivityKind::FileChange)
}

fn runtime_state_from_ws_status(status: &Value) -> SessionState {
    match status.get("type").and_then(|value| value.as_str()) {
        Some("notLoaded") | Some("not_loaded") => SessionState::NotLoaded,
        Some("idle") => SessionState::Idle,
        Some("systemError") | Some("system_error") => SessionState::Error,
        Some("active") => {
            if has_string_value_in_array(status.get("activeFlags"), "waitingOnApproval")
                || has_string_value_in_array(status.get("activeFlags"), "waitingOnUserInput")
            {
                SessionState::WaitingForInput
            } else {
                SessionState::Running
            }
        }
        _ => SessionState::Running,
    }
}

fn has_string_value_in_array(value: Option<&Value>, needle: &str) -> bool {
    value
        .and_then(|value| value.as_array())
        .map(|values| values.iter().any(|value| value.as_str() == Some(needle)))
        .unwrap_or(false)
}

fn is_review_item(item_type: &str) -> bool {
    matches!(item_type, "enteredReviewMode" | "exitedReviewMode")
}

fn item_type_to_activity_kind(item_type: &str) -> ActivityKind {
    match item_type {
        "reasoning" => ActivityKind::Reasoning,
        "commandExecution" | "toolCall" | "mcpToolCall" | "dynamicToolCall" | "customToolCall" => {
            ActivityKind::CommandExecution
        }
        "fileChange" => ActivityKind::FileChange,
        "webSearch" => ActivityKind::WebSearch,
        "agentMessage" => ActivityKind::AgentMessage,
        _ => ActivityKind::None,
    }
}

fn tool_name_to_activity(tool: Option<&str>) -> ActivityKind {
    let Some(tool) = tool else {
        return ActivityKind::CommandExecution;
    };

    if tool.contains("apply_patch") || tool.contains("patch") {
        ActivityKind::FileChange
    } else if tool.contains("web_search") {
        ActivityKind::WebSearch
    } else {
        ActivityKind::CommandExecution
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

    if let Some(value) = params
        .get("turn")
        .and_then(|turn| turn.get("threadId").or_else(|| turn.get("thread_id")))
        .and_then(|value| value.as_str())
    {
        return value.to_string();
    }

    "ws".to_string()
}

fn ws_item_type(params: &Value) -> Option<String> {
    params
        .get("item")
        .and_then(|item| item.get("type"))
        .or_else(|| params.get("type"))
        .and_then(|value| value.as_str())
        .map(ToOwned::to_owned)
}

fn ws_item_status(params: &Value) -> Option<String> {
    params
        .get("item")
        .and_then(|item| item.get("status"))
        .or_else(|| params.get("status"))
        .and_then(|value| value.as_str())
        .map(ToOwned::to_owned)
}

fn ws_turn_state(params: &Value) -> Option<TurnState> {
    let status = params
        .get("turn")
        .and_then(|turn| turn.get("status"))
        .or_else(|| params.get("status"))
        .and_then(|value| value.as_str())?;

    match status {
        "inProgress" | "in_progress" => Some(TurnState::InProgress),
        "completed" => Some(TurnState::Completed),
        "interrupted" => Some(TurnState::Interrupted),
        "failed" => Some(TurnState::Failed),
        _ => None,
    }
}

fn ws_first_string(params: &Value, keys: &[&str]) -> Option<String> {
    for key in keys {
        if let Some(value) = params.get(key).and_then(|value| value.as_str()) {
            return Some(value.to_string());
        }
        if let Some(value) = params
            .get("item")
            .and_then(|item| item.get(key))
            .and_then(|value| value.as_str())
        {
            return Some(value.to_string());
        }
    }

    None
}

#[cfg(test)]
mod tests {
    use super::{ActivityKind, AwaitReason, SessionState, StateParser, StateSource, TurnState};
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

    fn task_started() -> RawJsonlLine {
        jsonl(json!({ "type": "task_started" }))
    }

    #[test]
    fn user_message_moves_to_running_reasoning() {
        let mut parser = StateParser::new();
        let event = parser
            .process_jsonl(&jsonl(json!({ "type": "user_message" })))
            .unwrap();

        assert_eq!(event.state, SessionState::Running);
        assert_eq!(event.activity_kind, ActivityKind::Reasoning);
        assert_eq!(event.turn_state, Some(TurnState::InProgress));
        assert_eq!(event.source, StateSource::Jsonl);
    }

    #[test]
    fn token_count_promotes_reasoning_to_agent_message() {
        let mut parser = StateParser::new();
        parser.process_jsonl(&task_started()).unwrap();

        let event = parser.process_jsonl(&token_count(10)).unwrap();

        assert_eq!(event.state, SessionState::Running);
        assert_eq!(event.activity_kind, ActivityKind::AgentMessage);
    }

    #[test]
    fn apply_patch_maps_to_file_change_activity() {
        let mut parser = StateParser::new();
        let event = parser
            .process_jsonl(&jsonl(json!({
                "type": "tool_call",
                "tool": "apply_patch"
            })))
            .unwrap();

        assert_eq!(event.state, SessionState::Running);
        assert_eq!(event.activity_kind, ActivityKind::FileChange);
    }

    #[test]
    fn file_change_pin_blocks_reasoning_regression_temporarily() {
        let mut parser = StateParser::new();
        parser
            .process_jsonl(&jsonl(json!({
                "type": "tool_call",
                "tool": "apply_patch"
            })))
            .unwrap();

        let reasoning = parser.process_jsonl(&jsonl(json!({ "type": "reasoning" })));
        assert!(reasoning.is_none());
        assert_eq!(
            parser.trackers.get("sess-1").unwrap().activity_kind,
            ActivityKind::FileChange
        );
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

        assert_eq!(event.state, SessionState::WaitingForInput);
        assert_eq!(event.activity_kind, ActivityKind::CommandExecution);
        assert_eq!(
            event.await_reason,
            Some(AwaitReason::ToolApproval {
                tool: "shell".to_string(),
                command: Some("cargo test".to_string()),
            })
        );
    }

    #[test]
    fn approval_result_moves_to_running_or_idle() {
        let mut parser = StateParser::new();
        parser.process_jsonl(&jsonl(json!({
            "type": "awaiting_approval",
            "tool": "apply_patch"
        })));

        let approved = parser
            .process_jsonl(&jsonl(json!({ "type": "tool_approval", "approved": true })))
            .unwrap();
        assert_eq!(approved.state, SessionState::Running);
        assert_eq!(approved.activity_kind, ActivityKind::FileChange);

        parser.process_jsonl(&jsonl(json!({
            "type": "awaiting_approval",
            "tool": "shell"
        })));
        let denied = parser
            .process_jsonl(&jsonl(
                json!({ "type": "tool_approval", "approved": false }),
            ))
            .unwrap();
        assert_eq!(denied.state, SessionState::Idle);
        assert_eq!(denied.turn_state, Some(TurnState::Interrupted));
    }

    #[test]
    fn token_count_after_approval_promotes_to_agent_message() {
        let mut parser = StateParser::new();
        parser.process_jsonl(&jsonl(json!({
            "type": "awaiting_approval",
            "tool": "shell",
            "command": "echo app-smoke"
        })));
        parser
            .process_jsonl(&jsonl(json!({
                "type": "tool_approval",
                "approved": true
            })))
            .unwrap();

        let event = parser.process_jsonl(&token_count(30)).unwrap();

        assert_eq!(event.state, SessionState::Running);
        assert_eq!(event.activity_kind, ActivityKind::AgentMessage);
    }

    #[test]
    fn websocket_thread_status_waiting_takes_priority() {
        let mut parser = StateParser::new();
        let event = parser
            .process_ws(&WsStateEvent {
                method: "thread/status/changed".to_string(),
                params: json!({
                    "threadId": "thread-1",
                    "status": {
                        "type": "active",
                        "activeFlags": ["waitingOnApproval"]
                    }
                }),
            })
            .unwrap();

        assert_eq!(event.state, SessionState::WaitingForInput);
        assert_eq!(event.activity_kind, ActivityKind::None);
        assert_eq!(event.source, StateSource::AppServer);
    }

    #[test]
    fn websocket_review_state_is_supported() {
        let mut parser = StateParser::new();
        let event = parser
            .process_ws(&WsStateEvent {
                method: "item/started".to_string(),
                params: json!({
                    "threadId": "thread-1",
                    "item": {
                        "type": "enteredReviewMode"
                    }
                }),
            })
            .unwrap();

        assert_eq!(event.state, SessionState::ReadyForReview);
    }

    #[test]
    fn websocket_waiting_on_user_input_flag_is_supported() {
        let mut parser = StateParser::new();
        let event = parser
            .process_ws(&WsStateEvent {
                method: "thread/status/changed".to_string(),
                params: json!({
                    "threadId": "thread-1",
                    "status": {
                        "type": "active",
                        "activeFlags": ["waitingOnUserInput"]
                    }
                }),
            })
            .unwrap();

        assert_eq!(event.state, SessionState::WaitingForInput);
    }

    #[test]
    fn websocket_tool_request_user_input_is_supported() {
        let mut parser = StateParser::new();
        let event = parser
            .process_ws(&WsStateEvent {
                method: "item/tool/requestUserInput".to_string(),
                params: json!({
                    "threadId": "thread-1",
                    "item": {
                        "prompt": "Need more detail"
                    }
                }),
            })
            .unwrap();

        assert_eq!(event.state, SessionState::WaitingForInput);
        assert_eq!(
            event.await_reason,
            Some(AwaitReason::Question {
                text: Some("Need more detail".to_string()),
            })
        );
    }

    #[test]
    fn websocket_item_started_updates_activity() {
        let mut parser = StateParser::new();
        parser
            .process_ws(&WsStateEvent {
                method: "turn/started".to_string(),
                params: json!({ "threadId": "thread-1" }),
            })
            .unwrap();

        let event = parser
            .process_ws(&WsStateEvent {
                method: "item/started".to_string(),
                params: json!({
                    "threadId": "thread-1",
                    "item": {
                        "type": "fileChange",
                        "status": "inProgress"
                    }
                }),
            })
            .unwrap();

        assert_eq!(event.state, SessionState::Running);
        assert_eq!(event.activity_kind, ActivityKind::FileChange);
    }

    #[test]
    fn websocket_turn_failed_moves_to_error() {
        let mut parser = StateParser::new();
        let event = parser
            .process_ws(&WsStateEvent {
                method: "turn/completed".to_string(),
                params: json!({
                    "threadId": "thread-1",
                    "status": "failed"
                }),
            })
            .unwrap();

        assert_eq!(event.state, SessionState::Error);
        assert_eq!(event.turn_state, Some(TurnState::Failed));
    }

    #[test]
    fn app_server_runtime_beats_jsonl_runtime_fallback() {
        let mut parser = StateParser::new();
        parser
            .process_ws(&WsStateEvent {
                method: "thread/status/changed".to_string(),
                params: json!({
                    "threadId": "sess-1",
                    "status": { "type": "idle" }
                }),
            })
            .unwrap();

        let event = parser.process_jsonl(&task_started());
        assert!(event.is_none());
        assert_eq!(
            parser.trackers.get("sess-1").unwrap().state,
            SessionState::Idle
        );
    }

    #[test]
    fn running_timeout_returns_to_idle() {
        let mut parser = StateParser::new();
        parser.process_jsonl(&task_started()).unwrap();
        parser.process_jsonl(&token_count(10)).unwrap();

        parser.trackers.get_mut("sess-1").unwrap().running_timeout = Duration::from_millis(1);

        thread::sleep(std::time::Duration::from_millis(5));
        let events = parser.check_timeouts();

        assert_eq!(events.len(), 1);
        assert_eq!(events[0].state, SessionState::Idle);
    }

    #[test]
    fn error_timeout_returns_to_idle() {
        let mut parser = StateParser::new();
        parser.set_error("sess-1", StateSource::Jsonl);
        parser.trackers.get_mut("sess-1").unwrap().error_timeout = Duration::from_millis(1);

        thread::sleep(std::time::Duration::from_millis(5));
        let events = parser.check_timeouts();

        assert_eq!(events.len(), 1);
        assert_eq!(events[0].state, SessionState::Idle);
    }
}
