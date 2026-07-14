pub mod global_token_usage;
pub mod state_parser;
pub mod token_parser;

use crate::watcher::jsonl_watcher::RawJsonlLine;
use crate::watcher::ws_client::{WsLifecycle, WsStateEvent};
use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
#[serde(tag = "source", rename_all = "snake_case")]
pub enum RawEvent {
    JsonlLine(RawJsonlLine),
    WsMessage(WsStateEvent),
    WsLifecycle { lifecycle: WsLifecycle },
}

#[cfg(test)]
mod tests {
    use super::RawEvent;
    use crate::watcher::ws_client::WsLifecycle;

    #[test]
    fn websocket_lifecycle_serializes_as_internal_raw_event() {
        let value = serde_json::to_value(RawEvent::WsLifecycle {
            lifecycle: WsLifecycle::Disconnected,
        })
        .unwrap();

        assert_eq!(value["source"], "ws_lifecycle");
        assert_eq!(value["lifecycle"], "disconnected");
    }
}
