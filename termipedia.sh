#!/bin/sh
set -eu

API="https://en.wikipedia.org/w/api.php"
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

B=$(printf '\033[1m') G=$(printf '\033[32m') Y=$(printf '\033[33m') 
C=$(printf '\033[36m') R=$(printf '\033[0m') D=$(printf '\033[2m')
BL=$(printf '\033[34m') M=$(printf '\033[35m') U=$(printf '\033[4m')

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] <query>
Search and view Wikipedia articles from the terminal.

Examples:
  $(basename "$0") linux
  $(basename "$0") "quantum mechanics"
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
    W_VAL=$(awk -v c="$(get_width)" 'BEGIN { print int(c * 0.98) }')
    (
      printf "${C}${B} %s${R}\n${D} ─────────────────────────────────────────${R}\n" "$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
      printf "%s\n" "$2" | awk -v q="$QUERY" -v g="$G" -v y="$Y" -v c="$C" -v b="$B" -v r="$R" -v m="$M" -v bl="$BL" -v u="$U" -v w="$W_VAL" -v d="$D" '
      BEGIN { e = 1; skip = 0; current_lvl = "  " }
      function h(l) {
          if (l ~ /^==== /) { sub(/^==== /, "    ▪ ", l); sub(/ ====$/, "", l); return c b toupper(l) r }
          if (l ~ /^=== /)  { sub(/^=== /, "  ▸ ", l); sub(/ ===$/, "", l);   return y b toupper(l) r }
          if (l ~ /^== /)   { sub(/^== /, "── ", l); sub(/ ==$/, "", l);    return "\n" g b toupper(l) r }
          return l
      }
      function wr(s, wd, wrds, ln, i, n, indent) {
          gsub(/[[:space:]]+/, " ", s); sub(/^[[:space:]]+/, "", s);
          if (s == "") return;
          wd = w - 6; n = split(s, wrds, " "); ln = indent
          for (i = 1; i <= n; i++) {
              if (length(ln wrds[i]) > wd) { print ln; ln = indent wrds[i] " " }
              else { ln = ln wrds[i] " " }
          }
          print ln
      }
      {
          if ($0 ~ /^==+ (See also|Notes|References|External links|Further reading)/) { skip = 1; next }
          if (skip && $0 ~ /^==+ /) { skip = 0 }
          if (skip) next
          if ($0 ~ /^[[:space:]]*$/) { if (!e) { print ""; e = 1 }; next }
          e = 0; 
          if ($0 ~ /^==+ /) { 
              print h($0); 
              current_lvl = ($0 ~ /^====/) ? "      " : (($0 ~ /^===/) ? "    " : "  ");
              next 
          }
          gsub(/\[[0-9 ]*\]/, "", $0); gsub(/\(\s*\)|\[\s*\]/, "", $0);
          wr($0, w, x, y, z, a, current_lvl)
      }'
    ) | less -R
}

check_deps

if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    usage
fi

QUERY="$*"

SEARCH_URL="$API?action=query&list=search&srsearch=$(printf '%s' "$QUERY" | jq -sRr @uri)&srlimit=40&format=json"
SEARCH_RAW=$(curl -fsSL -A "$UA" "$SEARCH_URL")
TITLES=$(echo "$SEARCH_RAW" | jq -r '.query.search[].title' 2>/dev/null)

if [ -z "$TITLES" ] || [ "$TITLES" = "null" ]; then
    echo "${Y}${B}[!]${R} No results found."
    exit 1
fi

SELECTED=$(echo "$TITLES" | fzf --prompt="${BL}${B}Wiki ❯ ${R}" \
          --layout=reverse --border=rounded --no-info \
          --preview-window="right:65%:wrap:border-left" \
          --preview "
            _T_ENC=\$(printf {} | jq -sRr @uri);
            _URL=\"$API?action=query&titles=\$_T_ENC&prop=extracts&explaintext=1&format=json&redirects=1\";
            
            # Header removed, showing only All-Caps Label
            printf \"${Y}${B}SUMMARY${R}\n${D}──────────────────────────────────────────${R}\n\n\";
            
            curl -sL --connect-timeout 2 \"\$_URL\" | \
            jq -r '.query.pages | to_entries[0].value.extract // \"\"' | \
            awk -v pw=\"\${FZF_PREVIEW_COLUMNS:-50}\" -v d=\"${D}\" -v r=\"${R}\" '
                BEGIN { l_count = 0; max_l = 6; done = 0 }
                {
                    if (done) next;
                    if (\$0 ~ /^== /) { done = 1; next }
                    gsub(/\([^)]*\)/, \"\"); gsub(/\[[^]]*\]/, \"\");
                    gsub(/[[:space:]]+/, \" \", \$0);
                    if (length(\$0) < 3) next;
                    n=split(\$0, words, \" \"); line=\"  \"
                    for(i=1; i<=n; i++) {
                        if(length(line words[i]) > (pw-5)) { 
                            print line; l_count++; line=\"  \" words[i] \" \" 
                            if (l_count >= max_l) { done = 1; break }
                        } else { line=line words[i] \" \" }
                    }
                    if(!done && line != \"  \") { print line; l_count++ }
                    if(l_count >= max_l) done = 1
                }
                END { if (done) print \"\n  ... (Enter for full article)\" r }'
          ")

if [ -n "$SELECTED" ]; then
    T_ENC=$(printf '%s' "$SELECTED" | jq -sRr @uri)
    URL="$API?action=query&titles=$T_ENC&prop=extracts&explaintext=1&format=json&redirects=1"
    RAW=$(curl -fsSL -A "$UA" "$URL")
    EXTRACT=$(echo "$RAW" | jq -r '.query.pages | to_entries[0].value.extract // ""' 2>/dev/null)
    [ -n "$EXTRACT" ] && render "$SELECTED" "$EXTRACT"
fi
