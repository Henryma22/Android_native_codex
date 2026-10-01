#!/system/bin/sh

# Deterministic protocol fixture for lifecycle acceptance.
#
# It completes initialize and thread/start (or thread/resume), then exits
# cleanly. It never contacts a model and is not a Codex runtime.

extract_numeric_id() {
  printf '%s\n' "$1" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p' | head -n 1
}

emit_initialize_result() {
  printf '{"jsonrpc":"2.0","id":%s,"result":{"serverInfo":{"name":"codex-natural-exit-fixture","version":"1"}}}\n' "$1"
}

emit_thread_result() {
  printf '{"jsonrpc":"2.0","id":%s,"result":{"thread":{"id":"natural-exit-thread"}}}\n' "$1"
}

while IFS= read -r line; do
  case "$line" in
    *'"method":"initialize"'*)
      emit_initialize_result "$(extract_numeric_id "$line")"
      ;;
    *'"method":"thread/start"'*)
      emit_thread_result "$(extract_numeric_id "$line")"
      exit 0
      ;;
    *'"method":"thread/resume"'*)
      emit_thread_result "$(extract_numeric_id "$line")"
      exit 0
      ;;
  esac
done
