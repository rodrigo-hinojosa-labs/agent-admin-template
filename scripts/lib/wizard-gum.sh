#!/usr/bin/env bash
# wizard helpers backed by gum. Requires $GUM to be set to the gum binary path.

# ask PROMPT DEFAULT → user input or default
ask() {
  local prompt="$1" default="$2" result
  if [ -n "$default" ]; then
    result=$("$GUM" input --prompt "$prompt: " --value "$default" --placeholder "$default" 2>/dev/null) || result="$default"
  else
    result=$("$GUM" input --prompt "$prompt: " --placeholder "..." 2>/dev/null) || result=""
  fi
  # Empty input with a default means "accept default"
  echo "${result:-$default}"
}

# ask_required PROMPT → repeats until non-empty
ask_required() {
  local prompt="$1" result=""
  while [ -z "$result" ]; do
    result=$("$GUM" input --prompt "$prompt: " 2>/dev/null) || result=""
  done
  echo "$result"
}

# ask_yn PROMPT DEFAULT(y|n) → "true" or "false"
ask_yn() {
  local prompt="$1" default="$2"
  local default_flag
  if [ "$default" = "y" ]; then
    default_flag="--default=yes"
  else
    default_flag="--default=no"
  fi
  if "$GUM" confirm "$prompt" $default_flag 2>/dev/null; then
    echo "true"
  else
    echo "false"
  fi
}

# ask_secret PROMPT → reads without echoing
ask_secret() {
  local prompt="$1"
  "$GUM" input --password --prompt "$prompt: " 2>/dev/null || echo ""
}

# ask_choice PROMPT DEFAULT OPTIONS(space-separated) → chosen option
ask_choice() {
  local prompt="$1" default="$2" options="$3"
  # gum choose takes each option as a separate arg. Use --selected for default.
  local args=(--header "$prompt" --selected "$default")
  local opt
  for opt in $options; do
    args+=("$opt")
  done
  local result
  result=$("$GUM" choose "${args[@]}" 2>/dev/null) || result="$default"
  echo "${result:-$default}"
}
