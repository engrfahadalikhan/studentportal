$ErrorActionPreference = 'Stop'

$repo = Split-Path -Parent $PSScriptRoot
$project = 'studentportal-36d0a'
$desktopApk = Join-Path $env:USERPROFILE 'Desktop\AUST-Student-Portal.apk'
$releaseApk = Join-Path $repo 'build\app\outputs\flutter-apk\app-release.apk'

Push-Location $repo
$oldTls = $env:NODE_TLS_REJECT_UNAUTHORIZED
$env:NODE_TLS_REJECT_UNAUTHORIZED = '0'
try {
  firebase deploy --only firestore:rules --project $project --config firebase.migration.json

  node tool\migrate_firestore_v2.mjs

  firebase deploy --only firestore:rules --project $project
  flutter build apk --release
  Copy-Item -LiteralPath $releaseApk -Destination $desktopApk -Force
  Write-Host "Activated v2 backend and updated $desktopApk"
} finally {
  $env:NODE_TLS_REJECT_UNAUTHORIZED = $oldTls
  Pop-Location
}
