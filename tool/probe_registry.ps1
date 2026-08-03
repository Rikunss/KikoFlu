$root = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render'
Get-ChildItem $root | ForEach-Object {
  $key = $_
  $props = Get-ItemProperty $key.PSPath
  Write-Output ("KEY=" + $key.PSChildName + " DeviceState=" + $props.DeviceState)
  $propPath = $key.PSPath + '\Properties'
  if (Test-Path $propPath) {
    $p = Get-ItemProperty $propPath
    $p.PSObject.Properties | ForEach-Object {
      if ($_.Name -notmatch '^PS') {
        Write-Output ("  " + $_.Name + " = " + $_.Value)
      }
    }
  }
}
