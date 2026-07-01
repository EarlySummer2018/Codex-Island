mod ipc;
mod parser;
mod token_usage;
mod watcher;

use anyhow::Result;
use std::path::PathBuf;
use tokio::sync::mpsc;
use tokio::time::{interval, Duration};
use tracing::{info, warn};
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::from_default_env().add_directive("codex_watcher=debug".parse()?),
        )
        .init();

    info!("Codex Island Watcher starting...");

    let codex_home = std::env::var("CODEX_HOME").unwrap_or_else(|_| {
        let home = std::env::var("HOME").expect("HOME not set");
        format!("{home}/.codex")
    });
    let sessions_dir = format!("{codex_home}/sessions");
    info!("Watching sessions directory: {sessions_dir}");

    match std::fs::read_dir(&sessions_dir) {
        Ok(_) => info!("Sessions directory accessible"),
        Err(error) => warn!("Cannot access sessions directory: {error}"),
    }

    let socket_path = std::env::var("CODEX_ISLAND_SOCKET")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/tmp/codex-island.sock"));
    let ipc_server = ipc::unix_socket::IpcServer::start(socket_path.clone()).await?;

    let (event_tx, mut event_rx) = mpsc::channel::<parser::RawEvent>(1024);
    watcher::start_all_watchers(&sessions_dir, event_tx).await;
    let mut token_usage_aggregators =
        parser::global_token_usage::TokenUsageAggregators::load_from_sessions_dir(&sessions_dir);
    let global_token_snapshot = token_usage_aggregators.global.snapshot();
    let daily_token_snapshot = token_usage_aggregators.daily.snapshot();
    info!("GlobalTokenUsageSnapshot: {:?}", global_token_snapshot);
    ipc_server.publish(&global_token_snapshot);
    info!("DailyTokenUsageSnapshot: {:?}", daily_token_snapshot);
    ipc_server.publish(&daily_token_snapshot);

    let mut token_parser = parser::token_parser::TokenParser::new();
    let mut state_parser = parser::state_parser::StateParser::new();
    let mut timeout_interval = interval(Duration::from_secs(1));

    loop {
        tokio::select! {
            _ = tokio::signal::ctrl_c() => {
                info!("Shutting down");
                ipc::unix_socket::cleanup_socket(&socket_path).await?;
                break;
            }
            _ = timeout_interval.tick() => {
                for state_event in state_parser.check_timeouts() {
                    info!("SessionStateEvent: {:?}", state_event);
                    ipc_server.publish(&state_event);
                }
            }
            maybe_event = event_rx.recv() => {
                let Some(event) = maybe_event else {
                    warn!("Raw event channel closed");
                    break;
                };

                info!("Raw event: {:?}", event);
                if let Some(state_event) = state_parser.process_event(&event) {
                    info!("SessionStateEvent: {:?}", state_event);
                    ipc_server.publish(&state_event);
                }
                if let Some(snapshot) = token_parser.process_event(&event) {
                    info!("TokenSnapshot: {:?}", snapshot);
                    ipc_server.publish(&snapshot);
                    let (global_token_snapshot, daily_token_snapshot) =
                        token_usage_aggregators.update_from_snapshot(&snapshot);
                    if let Some(global_token_snapshot) = global_token_snapshot {
                        info!("GlobalTokenUsageSnapshot: {:?}", global_token_snapshot);
                        ipc_server.publish(&global_token_snapshot);
                    }
                    if let Some(daily_token_snapshot) = daily_token_snapshot {
                        info!("DailyTokenUsageSnapshot: {:?}", daily_token_snapshot);
                        ipc_server.publish(&daily_token_snapshot);
                    }
                }
                ipc_server.publish(&event);
            }
        }
    }

    Ok(())
}
