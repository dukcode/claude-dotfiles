#!/usr/bin/env bash

input=$(cat)

# Parse all fields from JSON in a single jq call
IFS=$'\t' read -r model used_pct cost duration_ms lines_added lines_removed cwd < <(
  echo "$input" | jq -r '[
    .model.display_name // "Unknown",
    .context_window.used_percentage // "",
    .cost.total_cost_usd // "",
    .cost.total_duration_ms // "",
    .cost.total_lines_added // "",
    .cost.total_lines_removed // "",
    .workspace.current_dir // .cwd // ""
  ] | @tsv'
)

# Shorten path: replace $HOME with ~, abbreviate intermediate components
shorten_path() {
  local path="$1"
  local home="$HOME"
  # Replace home prefix with ~
  path="${path/#$home/~}"
  # Abbreviate all components except the first (~/ or /) and the last one
  echo "$path" | awk -F'/' '{
    if (NF <= 3) { print $0; next }
    out = $1
    for (i=2; i<NF; i++) {
      if ($i != "") out = out "/" substr($i, 1, 1)
      else out = out "/"
    }
    out = out "/" $NF
    print out
  }'
}

# ANSI color codes
RESET=$'\033[0m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
BOLD=$'\033[1m'
GOLD=$'\033[38;5;214m'
CYAN=$'\033[36m'
DIM=$'\033[2m'

# Build progress bar (15 chars wide, "ctx" centered inside)
build_progress_bar() {
  local pct="$1"
  local template="▬▬▬▬▬▬ctx▬▬▬▬▬▬"
  local width=15
  local filled=$(echo "$pct $width" | awk '{printf "%d", ($1 / 100 * $2)}')

  # Choose color based on usage (awk instead of bc)
  local color
  if awk "BEGIN{exit !($pct < 50)}"; then
    color="$GREEN"
  elif awk "BEGIN{exit !($pct < 80)}"; then
    color="$YELLOW"
  else
    color="$RED"
  fi

  # Substring slicing instead of per-character loop
  local filled_part="${template:0:$filled}"
  local empty_part="${template:$filled}"
  printf "%s%s" "${color}${BOLD}${filled_part}${RESET}" "${DIM}${empty_part}${RESET}"
}

# Format duration from milliseconds (single awk call)
format_duration() {
  awk "BEGIN{
    s=int($1/1000); h=int(s/3600); m=int((s%3600)/60); s=s%60
    if(h>0) printf \"%dh %dm %ds\",h,m,s
    else if(m>0) printf \"%dm %ds\",m,s
    else printf \"%ds\",s
  }"
}

# Format cost
format_cost() {
  local c="$1"
  printf "\$%.2f" "$c"
}

# Color model name
model_color=""
case "$model" in
  *Opus*)   model_color="$GOLD" ;;
  *Sonnet*) model_color="$CYAN" ;;
esac

# Build shortened pwd
short_pwd=""
if [ -n "$cwd" ]; then
  short_pwd=$(shorten_path "$cwd")
fi

# Build output parts
parts=""
if [ -n "$short_pwd" ]; then
  parts="${DIM}${short_pwd}${RESET} "
fi
parts="${parts}${BOLD}${model_color}[${model}]${RESET}"

if [ -n "$used_pct" ]; then
  bar=$(build_progress_bar "$used_pct")
  pct_int=$(echo "$used_pct" | awk '{printf "%d", $1}')
  parts="${parts} ${bar} ${pct_int}%"
fi

if [ -n "$duration_ms" ]; then
  formatted_duration=$(format_duration "$duration_ms")
  parts="${parts} | ${formatted_duration}"
fi

if [ -n "$lines_added" ] || [ -n "$lines_removed" ]; then
  added_str=""
  removed_str=""
  if [ -n "$lines_added" ] && [ "$lines_added" != "0" ]; then
    added_str="${GREEN}+${lines_added}${RESET}"
  fi
  if [ -n "$lines_removed" ] && [ "$lines_removed" != "0" ]; then
    removed_str="${RED}-${lines_removed}${RESET}"
  fi

  if [ -n "$added_str" ] && [ -n "$removed_str" ]; then
    parts="${parts} | ${added_str} ${removed_str}"
  elif [ -n "$added_str" ]; then
    parts="${parts} | ${added_str}"
  elif [ -n "$removed_str" ]; then
    parts="${parts} | ${removed_str}"
  fi
fi

printf "%s\n" "$parts"
