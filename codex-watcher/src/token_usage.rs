use serde_json::Value;

pub(crate) fn token_count_value(payload: &Value, internal_key: &str) -> Option<u64> {
    let usage_key = match internal_key {
        "reasoning_tokens" => "reasoning_output_tokens",
        key => key,
    };

    number_field(payload, internal_key)
        .or_else(|| number_field(payload, usage_key))
        .or_else(|| total_usage(payload).and_then(|usage| number_field(usage, usage_key)))
        .or_else(|| total_usage(payload).and_then(|usage| number_field(usage, internal_key)))
}

pub(crate) fn context_used_tokens(payload: &Value) -> Option<u64> {
    number_field(payload, "context_used")
        .or_else(|| last_usage(payload).and_then(|usage| number_field(usage, "total_tokens")))
}

pub(crate) fn model_context_window(payload: &Value) -> Option<u64> {
    number_field(payload, "context_window")
        .or_else(|| number_field(payload, "model_context_window"))
}

fn total_usage(payload: &Value) -> Option<&Value> {
    payload
        .get("info")
        .and_then(|info| info.get("total_token_usage"))
}

fn last_usage(payload: &Value) -> Option<&Value> {
    payload
        .get("info")
        .and_then(|info| info.get("last_token_usage"))
}

fn number_field(value: &Value, key: &str) -> Option<u64> {
    value.get(key).and_then(|value| value.as_u64())
}

#[cfg(test)]
mod tests {
    use super::{context_used_tokens, model_context_window, token_count_value};
    use serde_json::json;

    #[test]
    fn reads_direct_token_count_fields() {
        let payload = json!({
            "input_tokens": 10,
            "cached_input_tokens": 5,
            "output_tokens": 2,
            "reasoning_tokens": 1,
        });

        assert_eq!(token_count_value(&payload, "input_tokens"), Some(10));
        assert_eq!(token_count_value(&payload, "cached_input_tokens"), Some(5));
        assert_eq!(token_count_value(&payload, "output_tokens"), Some(2));
        assert_eq!(token_count_value(&payload, "reasoning_tokens"), Some(1));
    }

    #[test]
    fn reads_real_codex_total_token_usage_fields() {
        let payload = json!({
            "info": {
                "total_token_usage": {
                    "input_tokens": 120,
                    "cached_input_tokens": 40,
                    "output_tokens": 12,
                    "reasoning_output_tokens": 3,
                    "total_tokens": 132
                },
                "last_token_usage": {
                    "input_tokens": 50,
                    "cached_input_tokens": 20,
                    "output_tokens": 5,
                    "reasoning_output_tokens": 1,
                    "total_tokens": 55
                }
            },
            "rate_limits": {
                "primary": {}
            }
        });

        assert_eq!(token_count_value(&payload, "input_tokens"), Some(120));
        assert_eq!(token_count_value(&payload, "cached_input_tokens"), Some(40));
        assert_eq!(token_count_value(&payload, "output_tokens"), Some(12));
        assert_eq!(token_count_value(&payload, "reasoning_tokens"), Some(3));
    }

    #[test]
    fn reads_context_fields_from_real_codex_token_payload() {
        let payload = json!({
            "info": {
                "last_token_usage": {
                    "total_tokens": 154630
                }
            },
            "model_context_window": 258400
        });

        assert_eq!(context_used_tokens(&payload), Some(154630));
        assert_eq!(model_context_window(&payload), Some(258400));
    }
}
