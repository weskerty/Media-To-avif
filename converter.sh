#!/usr/bin/env bash
# ─── CONFIG ───────────────────────────────────────────
CRF=40          # Calidad (0=mejor, 63=peor)
FPS_ANIM=25     # FPS para webp animado → avif
SIZE_MIN=0      # Tamaño mínimo en KB 
# ──────────────────────────────────────────────────────

RED='\033[0;31m'
NC='\033[0m'

missing=0
for tool in ffmpeg magick avifenc; do
 if ! command -v "$tool" &>/dev/null; then
  echo -e "${RED}[ERROR] Falta: $tool${NC}"
  missing=1
 fi
done
[[ $missing -eq 1 ]] && exit 1

DIR_IN="$(pwd)/ImagesHere"
DIR_OUT="$(pwd)/Convertido"
VALID_SRC="jpg jpeg png webp gif"
SIZE_BYTES=$((SIZE_MIN * 1024))

mkdir -p "$DIR_OUT"

is_animated_webp(){
 dd if="$1" bs=1 count=200 2>/dev/null | grep -qP 'ANIM'
}

convert_static(){
 ffmpeg -y -loglevel error -i "$1" -map_metadata -1 -c:v libaom-av1 -crf "$CRF" -b:v 0 "$2"
}

convert_gif(){
 ffmpeg -y -loglevel error -i "$1" -map_metadata -1 -c:v libaom-av1 -crf "$CRF" -b:v 0 -pix_fmt yuv420p "$2"
}

convert_anim_webp(){
 local tmp
 tmp=$(mktemp -d /tmp/webpframes-XXXXXX)
 magick "$1" -coalesce "$tmp/frame_%04d.png"
 local frames=("$tmp"/frame_*.png)
 if [[ ${#frames[@]} -eq 0 ]]; then rm -rf "$tmp"; return 1; fi
 avifenc --fps "$FPS_ANIM" --qcolor "$CRF" --jobs all "${frames[@]}" "$2"
 local r=$?
 rm -rf "$tmp"
 return $r
}

process_file(){
 local f="$1"
 local ext="${f##*.}"; ext="${ext,,}"
 local ok=0
 for e in $VALID_SRC; do [[ "$ext" == "$e" ]] && ok=1 && break; done
 [[ $ok -eq 0 ]] && return

 if [[ $SIZE_BYTES -gt 0 ]]; then
  local sz; sz=$(stat -c%s "$f")
  [[ $sz -lt $SIZE_BYTES ]] && return
 fi

 local rel="${f#$DIR_IN/}"
 local out="$DIR_OUT/${rel%.*}.avif"
 mkdir -p "$(dirname "$out")"

 local sz_in; sz_in=$(stat -c%s "$f")
 local ok_conv=0

 if [[ "$ext" == "gif" ]]; then
  convert_gif "$f" "$out" && ok_conv=1
 elif [[ "$ext" == "webp" ]] && is_animated_webp "$f"; then
  convert_anim_webp "$f" "$out" && ok_conv=1
 else
  convert_static "$f" "$out" && ok_conv=1
 fi

 if [[ $ok_conv -eq 1 ]]; then
  local sz_out; sz_out=$(stat -c%s "$out")
  if [[ $sz_out -eq 0 ]]; then
   rm -f "$out"
   echo "[FAIL] $rel -> avif vacío, original conservado"
  else
   rm -f "$f"
   echo "[CONV] $rel -> ${rel%.*}.avif $((sz_in/1024))kb -> $((sz_out/1024))kb"
  fi
 else
  [[ -f "$out" && $(stat -c%s "$out") -eq 0 ]] && rm -f "$out"
  echo "[FAIL] $rel"
 fi
}

echo "[CONV] Origen: $DIR_IN"
echo "[CONV] Destino: $DIR_OUT"
echo "[CONV] CRF:$CRF | FPS_ANIM:$FPS_ANIM"

while IFS= read -r -d '' f; do
 process_file "$f"
done < <(find "$DIR_IN" -type f -print0)

echo "[CONV] ✔ Finalizado"
