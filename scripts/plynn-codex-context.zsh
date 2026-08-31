# Optional Codex CLI bridge for Plynn.
# Source this file from ~/.zshrc, then launch sessions with `plynn_codex`.

_plynn_codex_context_path() {
    print -r -- "${PLYNN_CONTEXT_PATH:-$HOME/Library/Application Support/Plynn/codex-workspace}"
}

_plynn_codex_publish() {
    local context_path="$(_plynn_codex_context_path)"
    local context_dir="${context_path:h}"
    local temporary_path="${context_path}.tmp.$$"
    mkdir -p -- "$context_dir" || return 1
    (umask 077; print -r -- "$PWD" >| "$temporary_path") || return 1
    mv -f -- "$temporary_path" "$context_path"
}

plynn_codex() {
    local status
    _plynn_codex_publish || return 1
    command codex "$@"
    status=$?
    rm -f -- "$(_plynn_codex_context_path)"
    return $status
}
