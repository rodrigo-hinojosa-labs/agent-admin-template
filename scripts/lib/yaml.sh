#!/usr/bin/env bash
# YAML reader — thin wrapper around yq v4

# yaml_get FILE PATH → prints value or empty string
yaml_get() {
  local file="$1" path="$2"
  local result
  result=$(yq "$path" "$file" 2>/dev/null)
  [ "$result" = "null" ] && result=""
  echo "$result"
}

# yaml_get_bool FILE PATH → prints "true" or "false"
yaml_get_bool() {
  local file="$1" path="$2"
  local result
  result=$(yq "$path" "$file" 2>/dev/null)
  if [ "$result" = "true" ]; then
    echo "true"
  else
    echo "false"
  fi
}

# yaml_array_length FILE PATH → prints integer length
yaml_array_length() {
  local file="$1" path="$2"
  yq "$path | length" "$file" 2>/dev/null || echo 0
}

# yaml_array_item FILE PATH INDEX SUBPATH → prints value at path[index].subpath
# Returns empty string for null/missing (matches yaml_get behavior).
yaml_array_item() {
  local file="$1" path="$2" index="$3" subpath="$4"
  local result
  result=$(yq "${path}[${index}]${subpath}" "$file" 2>/dev/null)
  [ "$result" = "null" ] && result=""
  echo "$result"
}

# yaml_require_yq — fails if yq is not installed
yaml_require_yq() {
  if ! command -v yq &>/dev/null; then
    local arch yq_arch
    arch=$(uname -m 2>/dev/null || echo "")
    case "$arch" in
      x86_64|amd64)   yq_arch="amd64" ;;
      aarch64|arm64)  yq_arch="arm64" ;;
      armv7l|armv6l)  yq_arch="arm" ;;
      i386|i686)      yq_arch="386" ;;
      *)              yq_arch="amd64" ;;
    esac
    echo "ERROR: yq is required. Install with:" >&2
    echo "  macOS: brew install yq" >&2
    echo "  Linux (${arch:-unknown} → ${yq_arch}): sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${yq_arch} && sudo chmod +x /usr/local/bin/yq" >&2
    return 1
  fi
}
