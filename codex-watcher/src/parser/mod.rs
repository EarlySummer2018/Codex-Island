pub mod global_token_usage;
pub mod state_parser;
pub mod token_parser;

use crate::watcher::jsonl_watcher::RawJsonlLine;
use crate::watcher::ws_client::WsStateEvent;
use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
#[serde(tag = "source", rename_all = "snake_case")]
pub enum RawEvent {
    JsonlLine(RawJsonlLine),
    WsMessage(WsStateEvent),
}
