#!/usr/bin/env bash
# Developer ID 로 서명하고 Apple 공증까지 마친 배포용 FKMEM zip 을 만든다.
#
# 준비 (한 번만):
#   1. 키체인에 프로젝트 팀의 "Developer ID Application" 인증서가 있어야 한다.
#   2. 공증 자격 증명을 키체인에 저장한다. (Apple ID 앱 암호 필요)
#        xcrun notarytool store-credentials FKMEM --apple-id <Apple ID> --team-id <팀 ID>
#
# 사용법:
#   scripts/release.sh            빌드부터 공증, zip 까지 진행한다
#   scripts/release.sh --resume   공증이 제한 시간 안에 끝나지 않아 멈췄을 때, 다시 빌드·제출하지 않고
#                                 그 제출이 끝나기를 기다린 뒤 이어서 마무리한다
#
# 환경 변수:
#   NOTARY_PROFILE  notarytool 자격 증명 이름 (기본값: FKMEM)
#   NOTARY_TIMEOUT  공증 완료를 기다리는 최대 시간 (기본값: 30m)
#
# 결과물: build/release/FKMEM-<버전>.zip
#
# set -e 아래에서 VAR="$(cmd)" 는 cmd 가 실패하면 메시지 없이 그 줄에서 끝나고, `cmd | grep -q` 는
# pipefail 때문에 grep 이 먼저 끝나면 SIGPIPE 로 실패할 수 있다. 그래서 실패할 수 있는 명령은
# 결과를 변수에 받으면서 || 로 직접 처리한다.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT="FKMEM.xcodeproj"
SCHEME="FKMEM"
APP_NAME="FKMEM"
NOTARY_PROFILE="${NOTARY_PROFILE:-FKMEM}"
NOTARY_TIMEOUT="${NOTARY_TIMEOUT:-30m}"
OUT="$ROOT/build/release"
APP="$OUT/export/$APP_NAME.app"
SUBMISSION_ID_FILE="$OUT/submission-id"
BUILD_COMMIT_FILE="$OUT/build-commit"

step() { printf '\n==> %s\n' "$*"; }
fail() { printf '오류: %s\n' "$*" >&2; exit 1; }

case "${1:-}" in
  "") RESUME=0 ;;
  --resume) RESUME=1 ;;
  *) fail "알 수 없는 옵션: $1 (사용법은 스크립트 상단 주석 참고)" ;;
esac

if [[ "$RESUME" == 0 ]]; then
  # 커밋하지 않은 변경이 섞인 빌드가 배포되지 않도록 막는다
  DIRTY="$(git status --porcelain)" || fail "git 상태를 읽지 못했습니다."
  [[ -z "$DIRTY" ]] || fail "커밋하지 않은 변경이 있습니다. 정리한 뒤 다시 실행하세요."

  # xcodebuild 는 평소에도 stderr 에 잡음을 내므로 함께 받아 두고 실패했을 때만 보여 준다
  SETTINGS="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -showBuildSettings 2>&1)" \
    || fail "빌드 설정을 읽지 못했습니다.
$SETTINGS"
  setting() { awk -v key="$1" '$1 == key { print $3; exit }' <<<"$SETTINGS"; }
  VERSION="$(setting MARKETING_VERSION)"
  TEAM_ID="$(setting DEVELOPMENT_TEAM)"
  [[ -n "$VERSION" && -n "$TEAM_ID" ]] || fail "프로젝트에서 버전이나 팀 ID를 읽지 못했습니다."

  step "사전 점검 (버전 $VERSION, 팀 $TEAM_ID)"
  IDENTITIES="$(security find-identity -v -p codesigning)" || fail "코드 서명 인증서 목록을 읽지 못했습니다."
  grep -q "Developer ID Application: .*($TEAM_ID)" <<<"$IDENTITIES" \
    || fail "키체인에 팀 $TEAM_ID 의 Developer ID Application 인증서가 없습니다."
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || fail "notarytool 자격 증명 '$NOTARY_PROFILE' 을 찾지 못했습니다. 스크립트 상단의 준비 단계를 확인하세요."

  rm -rf "$OUT"
  mkdir -p "$OUT"
  git rev-parse HEAD > "$BUILD_COMMIT_FILE"

  step "Archive"
  xcodebuild archive \
    -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$OUT/$APP_NAME.xcarchive" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    -quiet

  step "Developer ID 로 내보내기"
  cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
</dict>
</plist>
PLIST
  xcodebuild -exportArchive \
    -archivePath "$OUT/$APP_NAME.xcarchive" \
    -exportPath "$OUT/export" \
    -exportOptionsPlist "$OUT/ExportOptions.plist" \
    -quiet

  step "서명 확인"
  codesign --verify --deep --strict --verbose=2 "$APP"
  SIGNATURE="$(codesign -dv "$APP" 2>&1)" || fail "서명 정보를 읽지 못했습니다.
$SIGNATURE"
  grep -q 'flags=.*runtime' <<<"$SIGNATURE" || fail "Hardened Runtime 이 켜져 있지 않습니다."

  step "공증 제출"
  ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
  # submit --wait 는 시간이 초과되면 제출 ID 를 stderr 로만 내므로, 기다리지 않고 제출해 ID 부터 받는다
  SUBMISSION="$(xcrun notarytool submit "$OUT/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --output-format json)" \
    || fail "공증 제출에 실패했습니다."
  SUBMISSION_ID="$(plutil -extract id raw -o - - <<<"$SUBMISSION" 2>/dev/null)" \
    || fail "공증 제출 ID를 읽지 못했습니다.
$SUBMISSION"
  # 기다리다 시간이 초과돼도 --resume 으로 이어 갈 수 있도록 남긴다
  echo "$SUBMISSION_ID" > "$SUBMISSION_ID_FILE"
  rm "$OUT/notarize.zip"
else
  [[ -d "$APP" && -f "$SUBMISSION_ID_FILE" && -f "$BUILD_COMMIT_FILE" ]] \
    || fail "이어서 진행할 공증 제출이 없습니다. 먼저 scripts/release.sh 를 실행하세요."
  SUBMISSION_ID="$(cat "$SUBMISSION_ID_FILE")"
fi

step "공증 결과 기다리기 (제출 ID: $SUBMISSION_ID, 최대 $NOTARY_TIMEOUT, 보통 몇 분 걸립니다)"
# wait 는 시간이 초과돼도 종료 코드가 일정하지 않으므로, 결과는 info 로 따로 확인한다
xcrun notarytool wait "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" --timeout "$NOTARY_TIMEOUT" || true
INFO="$(xcrun notarytool info "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" --output-format json)" \
  || fail "공증 상태를 확인하지 못했습니다. (제출 ID: $SUBMISSION_ID)
잠시 뒤 scripts/release.sh --resume 으로 다시 확인하세요."
STATUS="$(plutil -extract status raw -o - - <<<"$INFO" 2>/dev/null || echo "알 수 없음")"
case "$STATUS" in
  Accepted) ;;
  "In Progress")
    fail "공증이 $NOTARY_TIMEOUT 안에 끝나지 않았습니다. (제출 ID: $SUBMISSION_ID)
나중에 아래 명령으로 이 제출이 끝나기를 기다린 뒤 이어서 마무리하세요. 다시 빌드하거나 제출하지 않습니다.
  scripts/release.sh --resume" ;;
  *)
    xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" >&2 || true
    fail "공증에 실패했습니다. (상태: $STATUS)" ;;
esac

step "공증 티켓 붙이기"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

step "Gatekeeper 확인"
# spctl 은 거부하면 0 이 아닌 코드로 끝나므로 결과를 받은 뒤 직접 판정한다
ASSESSMENT="$(spctl --assess --type execute --verbose=2 "$APP" 2>&1)" || true
echo "$ASSESSMENT"
grep -q 'source=Notarized Developer ID' <<<"$ASSESSMENT" || fail "Gatekeeper 가 공증된 앱으로 인식하지 않습니다."

step "배포용 zip 만들기"
# --resume 일 때도 실제로 빌드한 앱의 버전을 쓴다
VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$APP/Contents/Info.plist")" \
  || fail "앱 버전을 읽지 못했습니다."
ZIP="$OUT/$APP_NAME-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

BUILD_COMMIT="$(cat "$BUILD_COMMIT_FILE")"
step "완료"
echo "파일: $ZIP"
echo "빌드한 커밋: $BUILD_COMMIT"
echo "아키텍처: $(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"
echo "SHA-256: $(shasum -a 256 "$ZIP" | awk '{ print $1 }')"
echo

# 태그가 아직 없으면 gh release create 는 빌드한 커밋이 아니라 기본 브랜치 끝에 태그를 만든다.
# 그래서 빌드한 커밋에 태그가 있으면 그 태그를, 없으면 커밋을 직접 지정하도록 안내한다.
TAGS="$(git tag --points-at "$BUILD_COMMIT")" || TAGS=""
TAG="${TAGS%%$'\n'*}"
if [[ -n "$TAG" ]]; then
  echo "GitHub 릴리즈에 올리려면 (태그 $TAG 를 먼저 push 하세요: git push origin $TAG):"
  echo "  gh release create $TAG \"$ZIP\" --verify-tag"
else
  echo "GitHub 릴리즈에 올리려면 (빌드한 커밋이 GitHub 에 push 되어 있어야 합니다):"
  echo "  gh release create <태그> \"$ZIP\" --target $BUILD_COMMIT"
fi
