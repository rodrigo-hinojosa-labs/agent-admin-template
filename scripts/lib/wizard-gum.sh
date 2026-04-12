#!/usr/bin/env bash
# Wizard helpers backed by gum. Requires $GUM to be set to the gum binary path.
#
# gum renders its interactive UI to stderr and emits the captured value to
# stdout. Do NOT silence stderr here — that would hide the prompt and make
# the wizard look frozen. The `|| fallback` branches catch Ctrl+C / errors.

# ask PROMPT DEFAULT → user input or default
ask() {
  local prompt="$1" default="$2" result
  if [ -n "$default" ]; then
    result=$("$GUM" input --prompt "$prompt: " --value "$default" --placeholder "$default") || result="$default"
  else
    result=$("$GUM" input --prompt "$prompt: " --placeholder "...") || result=""
  fi
  echo "${result:-$default}"
}

# ask_required PROMPT → repeats until non-empty
ask_required() {
  local prompt="$1" result=""
  while [ -z "$result" ]; do
    result=$("$GUM" input --prompt "$prompt: ") || result=""
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
  if "$GUM" confirm "$prompt" $default_flag; then
    echo "true"
  else
    echo "false"
  fi
}

# ask_secret PROMPT → reads without echoing
ask_secret() {
  local prompt="$1"
  "$GUM" input --password --prompt "$prompt: " || echo ""
}

# ask_choice PROMPT DEFAULT OPTIONS(space-separated) → chosen option
ask_choice() {
  local prompt="$1" default="$2" options="$3"
  local args=(--header "$prompt" --selected "$default")
  local opt
  for opt in $options; do
    args+=("$opt")
  done
  local result
  result=$("$GUM" choose "${args[@]}") || result="$default"
  echo "${result:-$default}"
}
