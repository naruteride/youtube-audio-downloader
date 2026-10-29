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

# PATH에서 실행 가능한 yt-dlp를 찾아 경로 및 버전 표시
# 같은 파일을 가리키는 심볼릭 링크 및 중복 경로는 한 번만 표시
select_ytdlp() {
  local candidate duplicate index version answer
  local count=0
  local -a paths versions
  paths=()
  versions=()

  while IFS= read -r candidate; do
    [[ -n "$candidate" ]] || continue
    [[ -f "$candidate" && -x "$candidate" ]] || continue
    if [[ "$candidate" != /* ]]; then
      candidate="$PWD/$candidate"
    fi

    duplicate=0
    for (( index=0; index<count; index++ )); do
      if [[ "$candidate" -ef "${paths[$index]}" ]]; then
        duplicate=1
        break
      fi
    done
    if (( duplicate == 1 )); then
      continue
    fi

    if version="$("$candidate" --version 2>/dev/null)"; then
      version="${version%%$'\n'*}"
      [[ -n "$version" ]] || version="버전 정보 없음"
    else
      version="버전 확인 실패"
    fi
    paths[$count]="$candidate"
    versions[$count]="$version"
    count=$((count + 1))
  done < <(type -aP yt-dlp || true)

  if (( count == 0 )); then
    printf 'yt-dlp를 찾을 수 없습니다. 먼저 다음 명령을 실행하십시오:\nbrew install yt-dlp ffmpeg\n' >&2
    return 127
  fi

  printf '\n발견된 yt-dlp 설치본:\n' >&2
  for (( index=0; index<count; index++ )); do
    printf '  %s) 버전: %s\n     경로: %s\n' \
      "$((index + 1))" "${versions[$index]}" "${paths[$index]}" >&2
  done

  if (( count == 1 )); then
    YTDLP_BIN="${paths[0]}"
    return 0
  fi

  while :; do
    printf '사용할 yt-dlp 번호를 입력하십시오 (1~%s, q: 종료): ' "$count" >&2
    if ! IFS= read -r answer; then
      printf '\n선택을 읽을 수 없습니다.\n' >&2
      return 1
    fi
    case "$answer" in
      q|Q) printf '다운로드를 취소했습니다.\n' >&2; return 130 ;;
    esac

    # 실제 메뉴의 번호로 비교
    for (( index=0; index<count; index++ )); do
      if [[ "$answer" == "$((index + 1))" ]]; then
        YTDLP_BIN="${paths[$index]}"
        printf '선택한 yt-dlp: %s (버전: %s)\n' \
          "$YTDLP_BIN" "${versions[$index]}" >&2
        return 0
      fi
    done
    printf '1~%s 사이의 번호 또는 q를 입력하십시오.\n' "$count" >&2
  done
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

select_ytdlp

for dependency in ffmpeg ffprobe; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    printf '%s를 찾을 수 없습니다. 먼저 다음 명령을 실행하십시오:\nbrew install yt-dlp ffmpeg\n' "$dependency" >&2
    exit 127
  fi
done

cleaned_url="$(remove_si "$url")"
printf '\n다운로드 URL: %s\n저장 위치: %s/Music/YouTube\n\n' "$cleaned_url" "$HOME"

exec "$YTDLP_BIN" \
  --no-playlist \
  -f "bestaudio/best" \
  -x --audio-format best \
  --embed-metadata \
  --embed-thumbnail \
  --convert-thumbnails jpg \
  -P "$HOME/Music/YouTube" \
  -o "%(artist,uploader)s - %(track,title)s.%(ext)s" \
  -- "$cleaned_url"
