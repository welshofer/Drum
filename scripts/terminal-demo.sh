#!/bin/bash
# Deterministic fixture output. Run inside a disposable Drum shell, then select row 6.
set -euo pipefail
demo_cols="${1:-$(tput cols 2>/dev/null || true)}"
demo_rows="${2:-$(tput lines 2>/dev/null || true)}"
if [[ ! "$demo_cols" =~ ^[0-9]{1,3}$ || ! "$demo_rows" =~ ^[0-9]{1,3}$ ]]; then
  printf 'Usage: terminal-demo.sh [columns 32..500] [rows 12..200]\n' >&2
  exit 2
fi
demo_cols=$((10#$demo_cols))
demo_rows=$((10#$demo_rows))
if (( demo_cols < 32 || demo_cols > 500 || demo_rows < 12 || demo_rows > 200 )); then
  printf 'Usage: terminal-demo.sh [columns 32..500] [rows 12..200]\n' >&2
  exit 2
fi
demo_inner=$((demo_cols - 2))
demo_rule=''
demo_ruler=''
for ((col=1; col<=demo_inner; col++)); do
  demo_rule+='─'
  demo_ruler+="$((col % 10))"
done
printf '\033[0m\033[2J\033[H┌%s┐' "$demo_rule"
for ((row=2; row<demo_rows; row++)); do
  case "$row" in
    2) demo_text='DRUM VISUAL FIXTURE v1 - default / ribbon' ;;
    3) demo_text='Normal text: Aa Bb 0123456789 !? () [] {}' ;;
    4) demo_text="$demo_ruler" ;;
    5) demo_text='Contrast: thin strokes il1 | broad strokes MW#' ;;
    6) demo_text='SELECT THIS TEXT: native selection reference' ;;
    7) demo_text='Box corners and both edge columns must remain legible.' ;;
    8) demo_text='Bloom must preserve counters in e a 8 B @.' ;;
    9) demo_text='Scanlines / grille: inspect at native display scale.' ;;
    10) demo_text='Cursor: focus here; compare block on / blink off.' ;;
    *) demo_text="Row $row: left | centre | right - resize reference" ;;
  esac
  demo_text="${demo_text:0:demo_inner}"
  printf '\033[%d;1H│%-*s│' "$row" "$demo_inner" "$demo_text"
done
printf '\033[%d;1H└%s┘\033[10;9H' "$demo_rows" "$demo_rule"
