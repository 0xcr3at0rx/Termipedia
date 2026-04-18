#!/bin/sh
set -eu

# Configuration
WIKI_LANG="${WIKI_LANG:-en}"
API="https://${WIKI_LANG}.wikipedia.org/w/api.php"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# Detect terminal capabilities and user preferences for color
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    BOLD=$(printf '\033[1m')
    GREEN=$(printf '\033[32m')
    YELLOW=$(printf '\033[33m') 
    CYAN=$(printf '\033[36m')
    BLUE=$(printf '\033[34m')
    RESET=$(printf '\033[0m')
    DIM=$(printf '\033[2m')
else
    BOLD="" GREEN="" YELLOW="" CYAN="" BLUE="" RESET="" DIM=""
fi

usage() {
    cat <<EOF
Search and view Wikipedia articles directly in your shell.

Usage: 
  $(basename "$0") [OPTIONS] <query>

Options:
  -l <lang>    Specify language (e.g., en, es, fr, de, jp)
  -h, --help   Show this help menu

Examples:
  $(basename "$0") linux                # Standard search (English)
  $(basename "$0") -l es "Astronáutica" # Search in Spanish
  $(basename "$0") "quantum mechanics"  # Multi-word query
  WIKI_LANG=fr $(basename "$0") paris   # Environment variable language
  NO_COLOR=1 $(basename "$0") zig       # Plain-text mode

EOF
}

check_deps() {
    for dep in curl jq fzf; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            echo "Missing dependency: $dep$"
            exit 1
        fi
    done
}

get_width() { stty size 2>/dev/null | awk '{print $2}' || echo 80; }

render() {
    W_VAL=$(awk -v c="$(get_width)" 'BEGIN { print int(c * 0.95) }')
    (
      printf "${CYAN}${BOLD} %s${RESET}\n${DIM} ─────────────────────────────────────────${RESET}\n" "$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
      printf "%s\n" "$2" | awk -v g="$GREEN" -v y="$YELLOW" -v c="$CYAN" -v b="$BOLD" -v r="$RESET" -v w="$W_VAL" -v d="$DIM" '
      BEGIN { e = 1; skip = 0; current_lvl = "  " }
      
      # Transform Wikipedia Markdown-style headers (== Header ==) into styled terminal lines
      function h(l) {
          if (l ~ /^===== /) { gsub(/^===== /, "", l); gsub(/ =====$/, "", l); return "    " c b "▪ " toupper(l) r }
          if (l ~ /^==== /) { gsub(/^==== /, "", l); gsub(/ ====$/, "", l); return "    " c b "▪ " toupper(l) r }
          if (l ~ /^=== /)  { gsub(/^=== /, "", l);  gsub(/ ===$/, "", l);  return "  " y b "▸ " toupper(l) r }
          if (l ~ /^== /)   { gsub(/^== /, "", l);   gsub(/ ==$/, "", l);   return "\n" g b "── " toupper(l) r }
          return l
      }

      # Word-wrap function to maintain indentation and fit terminal width
      function wr(s, indent) {
          gsub(/[[:space:]]+/, " ", s); sub(/^[[:space:]]+/, "", s);
          if (s == "") return;
          wd = w - length(indent); n = split(s, wrds, " "); ln = indent
          for (i = 1; i <= n; i++) {
              # If adding next word exceeds width, print line and start new one with indent
              if (length(ln wrds[i]) > wd) { print ln; ln = indent wrds[i] " " }
              else { ln = ln wrds[i] " " }
          }
          print ln
      }

      {
          # skip technical/meta sections at the end of articles
          if ($0 ~ /^==+ (See also|Notes|References|External links|Further reading|Bibliography|Sources|Notes et références|Véase también|Referenzen)/) { skip = 1; next }
          if (skip && $0 ~ /^==+ /) { skip = 0 }
          if (skip) next
          
          # Handle paragraph spacing
          if ($0 ~ /^[[:space:]]*$/) { if (!e) { print ""; e = 1 }; next }
          e = 0; 
          
          # Check for headers and update current indentation level
          if ($0 ~ /^==+ /) { 
              print h($0); 
              current_lvl = ($0 ~ /^====/) ? "      " : (($0 ~ /^===/) ? "    " : "  ");
              next 
          }

          # Clean up citations [12] and fix spacing artifacts around punctuation
          gsub(/\[[0-9]+\]|\[[a-zA-Z ]+\]/, "", $0);
          gsub(/ ,/, ",", $0);
          gsub(/->/, "", $0);
          
          wr($0, current_lvl)
      }'
    ) | less -R
}

if [ $# -gt 0 ]; then
    case "$1" in
        -l) 
            if [ -n "${2:-}" ]; then
                WIKI_LANG="$2"
                API="https://${WIKI_LANG}.wikipedia.org/w/api.php"
                shift 2
            fi
            ;;
        -h|--help) usage; exit 0 ;;
    esac
fi

[ $# -eq 0 ] && { usage; exit 0; }
check_deps
QUERY="$*"

SEARCH_URL="$API?action=query&list=search&srsearch=$(printf '%s' "$QUERY" | jq -sRr @uri)&srlimit=40&format=json"
SEARCH_RAW=$(curl -fsSL -A "$UA" "$SEARCH_URL")
TITLES=$(echo "$SEARCH_RAW" | jq -r '.query.search[].title' 2>/dev/null)

# Verify that the search returned valid results before launching fzf
if [ -z "$TITLES" ] || [ "$TITLES" = "null" ]; then
    echo "[!] No results found for '${QUERY}'."
    exit 1
fi


SELECTED=$(echo "$TITLES" | fzf --prompt="${BLUE}${BOLD}Wiki (${WIKI_LANG}) ❯ ${RESET}" \
          --layout=reverse --border=rounded --no-info \
          --preview-window="right:65%:wrap:border-left" \
          --preview "
            # Slight delay to prevent flickering and API spam while scrolling
            sleep 0.1;
            _T_ENC=\$(printf {} | jq -sRr @uri);
            _URL=\"$API?action=query&titles=\$_T_ENC&prop=extracts&explaintext=1&format=json&redirects=1\";
            printf \"${YELLOW}${BOLD}SUMMARY${RESET}\n${DIM}──────────────────────────────────────────${RESET}\n\n\";
            curl -sL --connect-timeout 2 \"\$_URL\" | \
            jq -r '.query.pages | to_entries[0].value.extract // \"\"' | \
            awk -v pw=\"\${FZF_PREVIEW_COLUMNS:-50}\" -v d=\"${DIM}\" -v r=\"${RESET}\" '
                BEGIN { l_count = 0; max_lines = 7; exit_now = 0; buffer = \"\" }
                {
                    if (exit_now) next;
                    # Stop processing if we hit the first real section header
                    if (\$0 ~ /^==/) { exit_now = 1; next }
                    
                    # Intensive cleaning for the preview summary
                    gsub(/\[[^]]*\]/, \"\", \$0);
                    while(gsub(/\\([^()]*\\)/, \"\", \$0)); # Remove pronunciation/dates
                    gsub(/->/, \"\", \$0);
                    gsub(/ ,/, \",\", \$0);
                    
                    # Consolidate multiline summaries into a single paragraph for wrapping
                    gsub(/[[:space:]]+/, \" \", \$0);
                    buffer = buffer \" \" \$0
                }
                END {
                    sub(/^[[:space:]]+/, \"\", buffer);
                    n = split(buffer, words, \" \"); line = \"  \"
                    for (i = 1; i <= n; i++) {
                        if (length(line words[i]) > (pw - 6)) {
                            print line; l_count++; line = \"  \" words[i] \" \"
                            if (l_count >= max_lines) break
                        } else { line = line words[i] \" \" }
                    }
                    if (l_count < max_lines && line != \"  \") { print line; l_count++ }
                    if (l_count > 0) print \"\n${DIM}  (Enter for full article)${RESET}\"
                }'
          ")

if [ -n "$SELECTED" ]; then
    T_ENC=$(printf '%s' "$SELECTED" | jq -sRr @uri)
    URL="$API?action=query&titles=$T_ENC&prop=extracts&explaintext=1&format=json&redirects=1"
    RAW=$(curl -fsSL -A "$UA" "$URL")
    EXTRACT=$(echo "$RAW" | jq -r '.query.pages | to_entries[0].value.extract // ""' 2>/dev/null)
    [ -n "$EXTRACT" ] && render "$SELECTED" "$EXTRACT"
fi
