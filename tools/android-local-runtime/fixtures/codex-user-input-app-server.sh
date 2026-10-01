#!/system/bin/sh

# Deterministic offline JSON-RPC fixture for Local Session user-input UI.
#
# It never contacts a provider or writes workspace files. The app starts this
# script as an explicit root-approved argv command, starts a thread, and then
# receives one item/tool/requestUserInput request after turn/start.

if [ "${1-}" = "--version" ]; then
  printf '%s\n' 'codex-user-input-fixture 1.0.0'
  exit 0
fi

extract_numeric_id() {
  printf '%s\n' "$1" | sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p' | head -n 1
}

emit_initialize_result() {
  printf '{"jsonrpc":"2.0","id":%s,"result":{"serverInfo":{"name":"codex-user-input-fixture","version":"1"}}}\n' "$1"
}

emit_thread_result() {
  printf '{"jsonrpc":"2.0","id":%s,"result":{"thread":{"id":"user-input-fixture-thread"}}}\n' "$1"
}

emit_turn_started() {
  printf '%s\n' '{"jsonrpc":"2.0","method":"turn/started","params":{"turn":{"id":"user-input-fixture-turn"}}}'
}

emit_user_input_request() {
  printf '%s\n' '{"jsonrpc":"2.0","id":"user-input-question-1","method":"item/tool/requestUserInput","params":{"questions":[{"id":"language","header":"Language","question":"Which language should the fixture use?","options":[{"label":"Dart","description":"Use the Dart fixture path."},{"label":"Kotlin","description":"Use the Kotlin fixture path."}],"isSecret":false}]}}'
}

emit_turn_completed() {
  printf '%s\n' '{"jsonrpc":"2.0","method":"item/agentMessage/delta","params":{"delta":"The fixture received the transient answer and completed the turn."}}'
  printf '%s\n' '{"jsonrpc":"2.0","method":"turn/completed","params":{"turn":{"id":"user-input-fixture-turn","status":"completed"}}}'
}

turn_request_id=''
while IFS= read -r line; do
  case "$line" in
    *'"method":"initialize"'*)
      emit_initialize_result "$(extract_numeric_id "$line")"
      ;;
    *'"method":"thread/start"'*)
      emit_thread_result "$(extract_numeric_id "$line")"
      ;;
    *'"method":"thread/resume"'*)
      emit_thread_result "$(extract_numeric_id "$line")"
      ;;
    *'"method":"turn/start"'*)
      turn_request_id="$(extract_numeric_id "$line")"
      emit_turn_started
      emit_user_input_request
      ;;
    *'"id":"user-input-question-1"'*'"answers"'*)
      emit_turn_completed
      printf '{"jsonrpc":"2.0","id":%s,"result":{"turnId":"user-input-fixture-turn"}}\n' "$turn_request_id"
      ;;
    *'"method":"turn/interrupt"'*)
      printf '%s\n' '{"jsonrpc":"2.0","method":"turn/interrupted","params":{"turn":{"id":"user-input-fixture-turn"}}}'
      ;;
    *'"method":"initialized"'*)
      ;;
  esac
done
