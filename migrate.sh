#!/bin/bash

BRANCH="${GITHUB_REF_NAME}"

echo "========================================"
echo "📦 Starting migration of old videos..."
echo "========================================"

# Find videos directly in videos/ (not inside dated folders)
DIRECT_VIDEOS=$(find videos -maxdepth 1 -type d | tail -n +2 | while read d; do
  BASENAME=$(basename "$d")
  # Skip dated folders (pattern: 8 digits_6 digits)
  if [[ "$BASENAME" =~ ^[0-9]{8}_[0-9]{6}$ ]]; then
    echo "SKIP: $BASENAME is already a dated folder" >&2
  # Skip specific recent folder
  elif [[ "$BASENAME" == "20260514_201446" ]]; then
    echo "SKIP: $BASENAME is protected (recent download)" >&2
  else
    echo "$d"
  fi
done)

if [ -z "$DIRECT_VIDEOS" ]; then
  echo "✅ No old videos found to migrate!"
  exit 0
fi

echo ""
echo "Old videos found:"
echo "$DIRECT_VIDEOS"
echo ""

# Get first commit date for each folder
for OLD_FOLDER in $DIRECT_VIDEOS; do
  FOLDER_NAME=$(basename "$OLD_FOLDER")
  
  FIRST_COMMIT_DATE=$(git log --diff-filter=A --format="%cd" --date=format:"%Y%m%d_%H%M%S" -- "$OLD_FOLDER" | tail -1)
  
  if [ -z "$FIRST_COMMIT_DATE" ]; then
    FIRST_COMMIT_DATE=$(date +"%Y%m%d_%H%M%S")
  fi
  
  DATED_FOLDER="videos/${FIRST_COMMIT_DATE}"
  mkdir -p "$DATED_FOLDER"
  
  echo "Moving $FOLDER_NAME → $DATED_FOLDER/"
  
  mv "$OLD_FOLDER" "$DATED_FOLDER/"
  
  NEW_PATH="$DATED_FOLDER/$FOLDER_NAME"
  if [ -f "$NEW_PATH/README.md" ]; then
    sed -i "s|raw.githubusercontent.com/${GITHUB_REPOSITORY_OWNER}/${GITHUB_REPOSITORY#*/}/${BRANCH}/videos/|raw.githubusercontent.com/${GITHUB_REPOSITORY_OWNER}/${GITHUB_REPOSITORY#*/}/${BRANCH}/videos/${FIRST_COMMIT_DATE}/|g" "$NEW_PATH/README.md"
    sed -i "s|github.com/${GITHUB_REPOSITORY_OWNER}/${GITHUB_REPOSITORY#*/}/tree/${BRANCH}/videos/|github.com/${GITHUB_REPOSITORY_OWNER}/${GITHUB_REPOSITORY#*/}/tree/${BRANCH}/videos/${FIRST_COMMIT_DATE}/|g" "$NEW_PATH/README.md"
  fi
done

# Rebuild master README
cat > videos/README.md << 'EOF'
# DOWNLOADED VIDEOS LIST :

----

EOF

NUM=0
for dated_folder in videos/*/; do
  [ -d "$dated_folder" ] || continue
  DATED_NAME=$(basename "$dated_folder")
  for video_folder in "$dated_folder"*/; do
    [ -d "$video_folder" ] || continue
    VID_NAME=$(basename "$video_folder")
    [ -f "$video_folder/README.md" ] || continue
    NUM=$((NUM + 1))
    DATED_ENCODED=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$DATED_NAME" 2>/dev/null || echo "$DATED_NAME")
    VID_ENCODED=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$VID_NAME" 2>/dev/null || echo "$VID_NAME")
    LINK="https://github.com/${GITHUB_REPOSITORY_OWNER}/${GITHUB_REPOSITORY#*/}/tree/${BRANCH}/videos/${DATED_ENCODED}/${VID_ENCODED}"
    printf -- "- %s - 🎬 [%s](%s)\n" "$NUM" "$VID_NAME" "$LINK" >> videos/README.md
  done
done

if [ "$NUM" -eq 0 ]; then
  echo "> No videos downloaded yet." >> videos/README.md
fi

# Create README for dated folders that don't have one
for dated_folder in videos/*/; do
  [ -d "$dated_folder" ] || continue
  DATED_NAME=$(basename "$dated_folder")
  if [ ! -f "$dated_folder/README.md" ]; then
    echo "# Archive: $DATED_NAME" > "$dated_folder/README.md"
    echo "" >> "$dated_folder/README.md"
    echo "This folder contains videos downloaded on: $(echo "$DATED_NAME" | sed 's/_/ /')" >> "$dated_folder/README.md"
    echo "" >> "$dated_folder/README.md"
    echo "| # | Video Name |" >> "$dated_folder/README.md"
    echo "|---|------------|" >> "$dated_folder/README.md"
    VID_COUNT=0
    for video_folder in "$dated_folder"*/; do
      [ -d "$video_folder" ] || continue
      VID_COUNT=$((VID_COUNT + 1))
      VID_NAME=$(basename "$video_folder")
      echo "| ${VID_COUNT} | ${VID_NAME} |" >> "$dated_folder/README.md"
    done
    echo "" >> "$dated_folder/README.md"
    echo "---" >> "$dated_folder/README.md"
    echo "Total videos: **${VID_COUNT}**" >> "$dated_folder/README.md"
  fi
done

git add -f videos/

if ! git diff --cached --quiet; then
  git commit -m "[AVASAM] Migrate old videos to dated folders [skip ci]"
  
  PUSH_RETRY=0
  while [ $PUSH_RETRY -lt 5 ]; do
    PUSH_RETRY=$((PUSH_RETRY + 1))
    if timeout 120 git push origin HEAD:"$BRANCH"; then
      echo ""
      echo "========================================"
      echo "✅ Migration completed successfully!"
      echo "========================================"
      break
    else
      echo "Push failed, retry $PUSH_RETRY/5..."
      sleep 3
      git fetch origin "$BRANCH"
      git reset --hard origin/"$BRANCH"
      git add -f videos/
      git diff --cached --quiet || git commit -m "[AVASAM] Migrate old videos [skip ci]"
    fi
  done
else
  echo "No changes to commit"
fi
