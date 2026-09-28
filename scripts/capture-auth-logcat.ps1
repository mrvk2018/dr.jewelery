# Dr. Jewelry — Wi-Fi ADB: auth/sync log capture (run from jewelry_sunlight_store)
param(
  [string]$Device = "192.168.0.9:33967",
  [int]$Seconds = 45
)

$ErrorActionPreference = "Stop"
$pkg = "com.jewelrysunlight.jewelry_sunlight_store"
$pattern = 'ProfileController|signInAnonymously|CloudDatabaseService|JewelrySunlightApp\._bootstrap|AuthException|GoTrue|Supabase.*ERROR|refreshCustomerProfile|session uid'

Write-Host "ADB devices:"
adb devices -l
Write-Host "Clear logcat, cold start $pkg, capture ${Seconds}s ..."
adb -s $Device logcat -c
adb -s $Device shell am force-stop $pkg
Start-Sleep -Seconds 1
adb -s $Device shell am start -n "$pkg/.MainActivity"
Start-Sleep -Seconds $Seconds
adb -s $Device logcat -d -v time 2>&1 |
  Select-String -Pattern $pattern |
  ForEach-Object { $_.Line }
