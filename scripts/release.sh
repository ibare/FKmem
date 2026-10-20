#!/usr/bin/env bash
# Developer ID 로 서명하고 Apple 공증까지 마친 배포용 FKMEM zip 을 만든다.
#
# 준비 (한 번만):
#   1. 키체인에 프로젝트 팀의 "Developer ID Application" 인증서가 있어야 한다.
#   2. 공증 자격 증명을 키체인에 저장한다. (Apple ID 앱 암호 필요)
#        xcrun notarytool store-credentials FKMEM --apple-id <Apple ID> --team-id <팀 ID>
#
# 사용법:
#   scripts/release.sh
#
# 환경 변수:
#   NOTARY_PROFILE  notarytool 자격 증명 이름 (기본값: FKMEM)
#
# 결과물: build/release/FKMEM-<버전>.zip

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROJECT="FKMEM.xcodeproj"
SCHEME="FKMEM"
APP_NAME="FKMEM"
NOTARY_PROFILE="${NOTARY_PROFILE:-FKMEM}"
OUT="$ROOT/build/release"

step() { printf '\n==> %s\n' "$*"; }
fail() { printf '오류: %s\n' "$*" >&2; exit 1; }

# 커밋하지 않은 변경이 섞인 빌드가 배포되지 않도록 막는다
[[ -z "$(git status --porcelain)" ]] || fail "커밋하지 않은 변경이 있습니다. 정리한 뒤 다시 실행하세요."

SETTINGS="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release -showBuildSettings 2>/dev/null)"
setting() { awk -v key="$1" '$1 == key { print $3; exit }' <<<"$SETTINGS"; }
VERSION="$(setting MARKETING_VERSION)"
TEAM_ID="$(setting DEVELOPMENT_TEAM)"
[[ -n "$VERSION" && -n "$TEAM_ID" ]] || fail "프로젝트에서 버전이나 팀 ID를 읽지 못했습니다."

step "사전 점검 (버전 $VERSION, 팀 $TEAM_ID)"
# pipefail 에서 `cmd | grep -q` 는 grep 이 먼저 끝나면 cmd 가 SIGPIPE 로 실패할 수 있어 변수에 받아 검사한다
IDENTITIES="$(security find-identity -v -p codesigning)"
grep -q "Developer ID Application: .*($TEAM_ID)" <<<"$IDENTITIES" \
  || fail "키체인에 팀 $TEAM_ID 의 Developer ID Application 인증서가 없습니다."
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || fail "notarytool 자격 증명 '$NOTARY_PROFILE' 을 찾지 못했습니다. 스크립트 상단의 준비 단계를 확인하세요."

rm -rf "$OUT"
mkdir -p "$OUT"
APP="$OUT/export/$APP_NAME.app"

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
SIGNATURE="$(codesign -dv "$APP" 2>&1)"
grep -q 'flags=.*runtime' <<<"$SIGNATURE" || fail "Hardened Runtime 이 켜져 있지 않습니다."

step "공증 제출 (보통 몇 분 걸립니다)"
ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
xcrun notarytool submit "$OUT/notarize.zip" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait --timeout 30m \
  --output-format json > "$OUT/notarize.json" || true
STATUS="$(plutil -extract status raw -o - "$OUT/notarize.json" 2>/dev/null || echo "알 수 없음")"
if [[ "$STATUS" != "Accepted" ]]; then
  SUBMISSION_ID="$(plutil -extract id raw -o - "$OUT/notarize.json" 2>/dev/null || true)"
  [[ -n "$SUBMISSION_ID" ]] && xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" >&2
  fail "공증에 실패했습니다. (상태: $STATUS)"
fi
rm "$OUT/notarize.zip"

step "공증 티켓 붙이기"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

step "Gatekeeper 확인"
ASSESSMENT="$(spctl --assess --type execute --verbose=2 "$APP" 2>&1)"
echo "$ASSESSMENT"
grep -q 'source=Notarized Developer ID' <<<"$ASSESSMENT" || fail "Gatekeeper 가 공증된 앱으로 인식하지 않습니다."

step "배포용 zip 만들기"
ZIP="$OUT/$APP_NAME-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

step "완료"
echo "파일: $ZIP"
echo "아키텍처: $(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"
echo "SHA-256: $(shasum -a 256 "$ZIP" | awk '{ print $1 }')"
echo
echo "GitHub 릴리즈에 올리려면: gh release create <태그> \"$ZIP\""
