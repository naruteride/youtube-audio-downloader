#!/bin/bash
# 사용법: bash youtube-audio.sh ["유튜브 URL"]
set -euo pipefail

# si 쿼리파라미터만 제거
# 나머지 쿼리파라미터랑 # 뒤의 조각 식별자는 유지
remove_si() {
  local url="$1" fragment="" base query part key
  local cleaned_query="" kept=0 more

  if [[ "$url" == *'#'* ]]; then
    fragment="#${url#*#}"
    url="${url%%#*}"
  fi

  if [[ "$url" != *'?'* ]]; then
    printf '%s%s\n' "$url" "$fragment"
    return
  fi

  base="${url%%\?*}"
  query="${url#*\?}"

  while :; do
    if [[ "$query" == *'&'* ]]; then
      part="${query%%&*}"
      query="${query#*&}"
      more=1
    else
      part="$query"
      more=0
    fi

    key="${part%%=*}"
    if [[ "$key" != "si" ]]; then
      if (( kept > 0 )); then
        cleaned_query+="&"
      fi
      cleaned_query+="$part"
      kept=$((kept + 1))
    fi

    if (( more == 0 )); then
      break
    fi
  done

  printf '%s' "$base"
  if (( kept > 0 )); then
    printf '?%s' "$cleaned_query"
  fi
  printf '%s\n' "$fragment"
}

if (( $# > 1 )); then
  printf '사용법: bash %s ["유튜브 URL"]\n' "${0##*/}" >&2
  exit 2
elif (( $# == 1 )); then
  url="$1"
else
  printf '유튜브 URL을 입력하십시오: ' >&2
  if ! IFS= read -r url; then
    printf '\nURL을 읽을 수 없습니다.\n' >&2
    exit 1
  fi
fi

# 붙여넣을 때 생긴 앞뒤 공백 제거
url="${url#"${url%%[![:space:]]*}"}"
url="${url%"${url##*[![:space:]]}"}"

case "$url" in
  http://*|https://*) ;;
  *) printf 'http:// 혹은 https://로 시작하는 URL을 입력하십시오.\n' >&2; exit 2 ;;
esac
if [[ "$url" == *$'\n'* || "$url" == *$'\r'* ]]; then
  printf 'URL은 한 줄로 입력하십시오.\n' >&2
  exit 2
fi

for dependency in yt-dlp ffmpeg ffprobe; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    printf '%s를 찾을 수 없습니다. 먼저 다음 명령을 실행하십시오:\nbrew install yt-dlp ffmpeg\n' "$dependency" >&2
    exit 127
  fi
done

cleaned_url="$(remove_si "$url")"
printf '\n다운로드 URL: %s\n저장 위치: %s/Music/YouTube\n\n' "$cleaned_url" "$HOME"

exec yt-dlp \
  --no-playlist \
  -f "bestaudio/best" \
  -x --audio-format best \
  --embed-metadata \
  --embed-thumbnail \
  --convert-thumbnails jpg \
  -P "$HOME/Music/YouTube" \
  -o "%(artist,uploader)s - %(track,title)s [%(id)s].%(ext)s" \
  -- "$cleaned_url"
