#!/bin/bash
set -e

# Integration test for chaos notes scripts
# Creates a test note, performs all operations, then deletes it

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL_ROOT="$(dirname "$TEST_DIR")"
SCRIPTS_DIR="$SKILL_ROOT/scripts"

# Create isolated temp data directory
TEMP_DATA=$(mktemp -d)
mkdir -p "$TEMP_DATA/notes" "$TEMP_DATA/assets"
cd "$TEMP_DATA" && git init -q && git config user.email "test@test.com" && git config user.name "Test"
export CHAOS_DATA_DIR="$TEMP_DATA"

# Cleanup on exit
cleanup() {
  rm -rf "$TEMP_DATA"
}
trap cleanup EXIT

DATA_DIR="$TEMP_DATA"
NOTES_DIR="$DATA_DIR/notes"
TIMESTAMP=$(date +%s)
TEST_TITLE="Test Note $TIMESTAMP"

PASSED=0
FAILED=0

green() { printf "\033[32m%s\033[0m\n" "$1"; }
red() { printf "\033[31m%s\033[0m\n" "$1"; }
yellow() { printf "\033[33m%s\033[0m\n" "$1"; }

assert_equals() {
  local expected="$1"
  local actual="$2"
  local msg="$3"
  if [ "$expected" = "$actual" ]; then
    green "  ✓ $msg"
    PASSED=$((PASSED + 1))
  else
    red "  ✗ $msg"
    red "    expected: $expected"
    red "    actual:   $actual"
    FAILED=$((FAILED + 1))
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="$3"
  if echo "$haystack" | grep -q "$needle"; then
    green "  ✓ $msg"
    PASSED=$((PASSED + 1))
  else
    red "  ✗ $msg"
    red "    '$needle' not found in output"
    FAILED=$((FAILED + 1))
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="$3"
  if ! echo "$haystack" | grep -q "$needle"; then
    green "  ✓ $msg"
    PASSED=$((PASSED + 1))
  else
    red "  ✗ $msg"
    red "    '$needle' should not be in output"
    FAILED=$((FAILED + 1))
  fi
}

assert_file_exists() {
  local file="$1"
  local msg="$2"
  if [ -f "$file" ]; then
    green "  ✓ $msg"
    PASSED=$((PASSED + 1))
  else
    red "  ✗ $msg"
    red "    file not found: $file"
    FAILED=$((FAILED + 1))
  fi
}

assert_file_not_exists() {
  local file="$1"
  local msg="$2"
  if [ ! -f "$file" ]; then
    green "  ✓ $msg"
    PASSED=$((PASSED + 1))
  else
    red "  ✗ $msg"
    red "    file should not exist: $file"
    FAILED=$((FAILED + 1))
  fi
}

echo ""
yellow "=== Chaos Notes Integration Test ==="
echo ""

# --- TEST: Create note ---
yellow "1. Testing new-note.sh"

OUTPUT=$("$SCRIPTS_DIR/new-note.sh" "$TEST_TITLE" 2>&1)
FILE_PATH=$(echo "$OUTPUT" | tail -1)
FILE_NAME=$(basename "$FILE_PATH")
NOTE_ID=$(echo "$FILE_NAME" | cut -d'-' -f1)

assert_contains "$OUTPUT" "created note" "commit message present"
assert_file_exists "$FILE_PATH" "note file created"

CONTENT=$(cat "$FILE_PATH")
assert_contains "$CONTENT" "id: $NOTE_ID" "frontmatter has correct id"
assert_contains "$CONTENT" "title: $TEST_TITLE" "frontmatter has correct title"
assert_not_contains "$CONTENT" "status:" "no status by default"
assert_not_contains "$CONTENT" "tags:" "no tags by default"

echo ""

# --- TEST: Update content only ---
yellow "2. Testing update-note.sh (content only)"

TEST_CONTENT="# Hello World

This is test content for note $TIMESTAMP."

OUTPUT=$("$SCRIPTS_DIR/update-note.sh" "$NOTE_ID" "$TEST_CONTENT" 2>&1)
assert_contains "$OUTPUT" "updated note" "commit message present"

CONTENT=$(cat "$FILE_PATH")
assert_contains "$CONTENT" "# Hello World" "content updated"
assert_contains "$CONTENT" "$TIMESTAMP" "content has timestamp"

echo ""

# --- TEST: Update status ---
yellow "3. Testing update-note.sh (--status=building)"

OUTPUT=$("$SCRIPTS_DIR/update-note.sh" "$NOTE_ID" --status=building 2>&1)
assert_contains "$OUTPUT" "updated note" "commit message present"

CONTENT=$(cat "$FILE_PATH")
assert_contains "$CONTENT" "status: building" "status set to building"
assert_contains "$CONTENT" "# Hello World" "content preserved"

echo ""

# --- TEST: Update tags ---
yellow "4. Testing update-note.sh (--tags=test,integration)"

OUTPUT=$("$SCRIPTS_DIR/update-note.sh" "$NOTE_ID" --tags=test,integration 2>&1)
assert_contains "$OUTPUT" "updated note" "commit message present"

CONTENT=$(cat "$FILE_PATH")
assert_contains "$CONTENT" "tags: \[test, integration\]" "tags set correctly"
assert_contains "$CONTENT" "status: building" "status preserved"

echo ""

# --- TEST: Update status to done ---
yellow "5. Testing update-note.sh (--status=done)"

OUTPUT=$("$SCRIPTS_DIR/update-note.sh" "$NOTE_ID" --status=done 2>&1)
assert_contains "$OUTPUT" "updated note" "commit message present"

CONTENT=$(cat "$FILE_PATH")
assert_contains "$CONTENT" "status: done" "status changed to done"

echo ""

# --- TEST: Update all at once ---
yellow "6. Testing update-note.sh (all options together)"

NEW_CONTENT="# Updated Content

All options test."

OUTPUT=$("$SCRIPTS_DIR/update-note.sh" "$NOTE_ID" --status=building --tags=final,test "$NEW_CONTENT" 2>&1)
assert_contains "$OUTPUT" "updated note" "commit message present"

CONTENT=$(cat "$FILE_PATH")
assert_contains "$CONTENT" "status: building" "status updated"
assert_contains "$CONTENT" "tags: \[final, test\]" "tags updated"
assert_contains "$CONTENT" "# Updated Content" "content updated"
assert_contains "$CONTENT" "All options test" "content body updated"

echo ""

# --- TEST: Clear status ---
yellow "7. Testing update-note.sh (--status=clear)"

OUTPUT=$("$SCRIPTS_DIR/update-note.sh" "$NOTE_ID" --status=clear 2>&1)
assert_contains "$OUTPUT" "updated note" "commit message present"

CONTENT=$(cat "$FILE_PATH")
assert_not_contains "$CONTENT" "status:" "status cleared"
assert_contains "$CONTENT" "tags:" "tags preserved"

echo ""

# --- TEST: Clear tags ---
yellow "8. Testing update-note.sh (--tags=)"

OUTPUT=$("$SCRIPTS_DIR/update-note.sh" "$NOTE_ID" --tags= 2>&1)
assert_contains "$OUTPUT" "updated note" "commit message present"

CONTENT=$(cat "$FILE_PATH")
assert_not_contains "$CONTENT" "tags:" "tags cleared"

echo ""

# --- TEST: Rename note ---
yellow "9. Testing rename-note.sh"

NEW_TITLE="Renamed Test Note $TIMESTAMP"
OUTPUT=$("$SCRIPTS_DIR/rename-note.sh" "$NOTE_ID" "$NEW_TITLE" 2>&1)
assert_contains "$OUTPUT" "renamed note" "commit message present"

NEW_FILE_PATH=$(echo "$OUTPUT" | tail -1)
assert_file_exists "$NEW_FILE_PATH" "renamed file exists"
assert_file_not_exists "$FILE_PATH" "old file removed"

CONTENT=$(cat "$NEW_FILE_PATH")
assert_contains "$CONTENT" "title: $NEW_TITLE" "title updated in frontmatter"
assert_contains "$CONTENT" "id: $NOTE_ID" "id unchanged"

# Update FILE_PATH for delete test
FILE_PATH="$NEW_FILE_PATH"

echo ""

# --- TEST: Invalid status ---
yellow "10. Testing validation (invalid status)"

OUTPUT=$("$SCRIPTS_DIR/update-note.sh" "$NOTE_ID" --status=invalid 2>&1 || true)
assert_contains "$OUTPUT" "invalid status" "invalid status rejected"

echo ""

# --- TEST: Delete note ---
yellow "11. Testing delete-note.sh"

OUTPUT=$("$SCRIPTS_DIR/delete-note.sh" "$NOTE_ID" 2>&1)
assert_contains "$OUTPUT" "deleted note" "commit message present"
assert_file_not_exists "$FILE_PATH" "note file deleted"

echo ""

# --- TEST WITHOUT GIT ---
echo ""
yellow "=== Testing without Git ==="
echo ""

# Create temp dir WITHOUT git
TEMP_DATA_NOGIT=$(mktemp -d)
mkdir -p "$TEMP_DATA_NOGIT/notes" "$TEMP_DATA_NOGIT/assets"
export CHAOS_DATA_DIR="$TEMP_DATA_NOGIT"

# Update symlink for new temp dir
# CHAOS_DATA_DIR is already exported, scripts will use it directly

NOGIT_TITLE="No Git Test $TIMESTAMP"

yellow "12. Testing new-note.sh (no git)"
OUTPUT=$($SCRIPTS_DIR/new-note.sh "$NOGIT_TITLE" 2>&1)
NOGIT_FILE=$(echo "$OUTPUT" | tail -1)
NOGIT_ID=$(basename "$NOGIT_FILE" | cut -d'-' -f1)
assert_file_exists "$NOGIT_FILE" "note created without git"
assert_not_contains "$OUTPUT" "fatal" "no git errors"

echo ""

yellow "13. Testing update-note.sh (no git)"
OUTPUT=$($SCRIPTS_DIR/update-note.sh "$NOGIT_ID" "Content without git" 2>&1)
assert_contains "$OUTPUT" "updated" "update works without git"
assert_not_contains "$OUTPUT" "fatal" "no git errors on update"

echo ""

yellow "14. Testing search-notes.sh (no git)"
OUTPUT=$($SCRIPTS_DIR/search-notes.sh "without" 2>&1)
assert_contains "$OUTPUT" "$NOGIT_ID" "search works without git"

echo ""

yellow "15. Testing rename-note.sh (no git)"
OUTPUT=$($SCRIPTS_DIR/rename-note.sh "$NOGIT_ID" "Renamed No Git" 2>&1)
assert_not_contains "$OUTPUT" "fatal" "rename works without git"

echo ""

yellow "16. Testing delete-note.sh (no git)"
NOGIT_FILE_NEW=$(echo "$OUTPUT" | tail -1)
OUTPUT=$($SCRIPTS_DIR/delete-note.sh "$NOGIT_ID" 2>&1)
assert_contains "$OUTPUT" "deleted" "delete works without git"
assert_not_contains "$OUTPUT" "fatal" "no git errors on delete"

# Cleanup no-git temp dir
rm -rf "$TEMP_DATA_NOGIT"

echo ""

# --- SUMMARY ---
echo ""
yellow "=== Test Summary ==="
green "Passed: $PASSED"
if [ $FAILED -gt 0 ]; then
  red "Failed: $FAILED"
  exit 1
else
  echo "Failed: $FAILED"
  green "All tests passed!"
fi
