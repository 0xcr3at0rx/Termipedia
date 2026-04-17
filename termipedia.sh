#!/bin/sh
set -eu

# Configuration
WIKI_LANG="${WIKI_LANG:-en}"
API="https://${WIKI_LANG}.wikipedia.org/w/api.php"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

# Styles
B=$(printf '\033[1m') G=$(printf '\033[32m') Y=$(printf '\033[33m') 
C=$(printf '\033[36m') R=$(printf '\033[0m') D=$(printf '\033[2m')
BL=$(printf '\033[34m') M=$(printf '\033[35m') U=$(printf '\033[4m')

usage() {
    cat <<EOF
Search and view Wikipedia articles directly in your shell.

${B}Usage:${R} 
  $(basename "$0") [OPTIONS] <query>

${B}Options:${R}
  -l <lang>    Specify language (e.g., en, es, fr, de, jp)
  -h, --help   Show this help menu

${B}Examples:${R}
  $(basename "$0") linux                  ${D}# Search for Linux in English${R}
  $(basename "$0") -l fr "Napoléon"       ${D}# Search in French${R}
  WIKI_LANG=de $(basename "$0") "Physik"  ${D}# Search in German via Env Var${R}
  $(basename "$0") "quantum mechanics"    ${D}# Multi-word search${R}

EOF
}

check_deps() {
    for dep in curl jq fzf; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            echo "${R}${B}[ERROR]${R} Missing dependency: ${Y}$dep${R}"
            exit 1
        fi
    done
}

get_width() { stty size 2>/dev/null | awk '{print $2}' || echo 80; }

render() {
    W_VAL=$(awk -v c="$(get_width)" 'BEGIN { print int(c * 0.95) }')
    (
      printf "${C}${B} %s${R}\n${D} ─────────────────────────────────────────${R}\n" "$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
      printf "%s\n" "$2" | awk -v q="$QUERY" -v g="$G" -v y="$Y" -v c="$C" -v b="$B" -v r="$R" -v w="$W_VAL" -v d="$D" '
      BEGIN { e = 1; skip = 0; current_lvl = "  " }
      function h(l) {
          if (l ~ /^==== /) { gsub(/^==== | ====$/, "", l); return "    " c b "▪ " toupper(l) r }
          if (l ~ /^=== /)  { gsub(/^=== | ===$/, "", l);  return "  " y b "▸ " toupper(l) r }
          if (l ~ /^== /)   { gsub(/^== | ==$/, "", l);   return "\n" g b "── " toupper(l) r }
          return l
      }
      function wr(s, indent) {
          gsub(/[[:space:]]+/, " ", s); sub(/^[[:space:]]+/, "", s);
          if (s == "") return;
          wd = w - length(indent); n = split(s, wrds, " "); ln = indent
          for (i = 1; i <= n; i++) {
              if (length(ln wrds[i]) > wd) { print ln; ln = indent wrds[i] " " }
              else { ln = ln wrds[i] " " }
          }
          print ln
      }
      {
          if ($0 ~ /^==+ (See also|Notes|References|External links|Further reading|Bibliography|Sources|Notes et références|Véase también|Referenzen)/) { skip = 1; next }
          if (skip && $0 ~ /^==+ /) { skip = 0 }
          if (skip) next
          if ($0 ~ /^[[:space:]]*$/) { if (!e) { print ""; e = 1 }; next }
          e = 0; 
          if ($0 ~ /^==+ /) { 
              print h($0); 
              current_lvl = ($0 ~ /^====/) ? "      " : (($0 ~ /^===/) ? "    " : "  ");
              next 
          }
          gsub(/\[[0-9]+\]|\[[a-zA-Z ]+\]/, "", $0);
          gsub(/\([; ]*\)|\[[; ]*\]/, "", $0);
          wr($0, current_lvl)
      }'
    ) | less -R
}

# Handle Language and Flags
if [ $# -gt 0 ]; then
    case "$1" in
        -l) 
            if [ -n "${2:-}" ]; then
                WIKI_LANG="$2"
                API="https://${WIKI_LANG}.wikipedia.org/w/api.php"
                shift 2
            fi
            ;;
        -h|--help)
            usage; exit 0
            ;;
    esac
fi

if [ $# -eq 0 ]; then
    usage; exit 0
fi

check_deps
QUERY="$*"

SEARCH_URL="$API?action=query&list=search&srsearch=$(printf '%s' "$QUERY" | jq -sRr @uri)&srlimit=40&format=json"
SEARCH_RAW=$(curl -fsSL -A "$UA" "$SEARCH_URL")
TITLES=$(echo "$SEARCH_RAW" | jq -r '.query.search[].title' 2>/dev/null)

if [ -z "$TITLES" ] || [ "$TITLES" = "null" ] || [ "$TITLES" = "" ]; then
    echo "${Y}${B}[!]${R} No results found for '${QUERY}' in (${WIKI_LANG})."
    exit 1
fi

SELECTED=$(echo "$TITLES" | fzf --prompt="${BL}${B}Wiki (${WIKI_LANG}) ❯ ${R}" \
          --layout=reverse --border=rounded --no-info \
          --preview-window="right:65%:wrap:border-left" \
          --preview "
            _T_ENC=\$(printf {} | jq -sRr @uri);
            _URL=\"$API?action=query&titles=\$_T_ENC&prop=extracts&explaintext=1&format=json&redirects=1\";
            printf \"${Y}${B}SUMMARY${R}\n${D}──────────────────────────────────────────${R}\n\n\";
            curl -sL --connect-timeout 2 \"\$_URL\" | \
            jq -r '.query.pages | to_entries[0].value.extract // \"\"' | \
            awk -v pw=\"\${FZF_PREVIEW_COLUMNS:-50}\" -v d=\"${D}\" -v r=\"${R}\" '
                BEGIN { l_count = 0; max_lines = 8; done = 0 }
                {
                    if (done) next;
                    if (\$0 ~ /^==/) { done = 1; next }
                    
                    gsub(/\[[^]]*\]/, \"\", \$0);
                    while(gsub(/\\([^()]*\\)/, \"\", \$0));
                    
                    gsub(/[[:space:]]+/, \" \", \$0); sub(/^[[:space:]]+/, \"\", \$0);
                    if (length(\$0) < 5) next;
                    
                    n = split(\$0, words, \" \"); line = \"  \"
                    for (i = 1; i <= n; i++) {
                        if (length(line words[i]) > (pw - 6)) {
                            print line; l_count++; line = \"  \" words[i] \" \"
                            if (l_count >= max_lines) { done = 1; break }
                        } else { line = line words[i] \" \" }
                    }
                    if (!done && line != \"  \") { 
                        print line; l_count++;
                    }
                    if (l_count >= max_lines) done = 1
                }
                END { if (l_count > 0) print \"\n${D}  ... (Enter for full article)${R}\" }'
          ")

if [ -n "$SELECTED" ]; then
    T_ENC=$(printf '%s' "$SELECTED" | jq -sRr @uri)
    URL="$API?action=query&titles=$T_ENC&prop=extracts&explaintext=1&format=json&redirects=1"
    RAW=$(curl -fsSL -A "$UA" "$URL")
    EXTRACT=$(echo "$RAW" | jq -r '.query.pages | to_entries[0].value.extract // ""' 2>/dev/null)
    [ -n "$EXTRACT" ] && render "$SELECTED" "$EXTRACT"
fi
