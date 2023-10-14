Import-Module PowerArubaIAP
Import-Module Posh-SSH

$global:SSHSession = $null
$global:SSHStream = $null
$global:credentials = $null
$global:numberdigits = $null

function get-aps() {
  $apsCmd = Get-ArubaIAPShowCmd "show aps"
  $apsStr = $apsCmd."Command output"
  
  # split the output into lines
  $apsStrArr = $apsStr -split "`n"

  $apList = @()
  
  # loop through lines
  foreach ($ap in $apsStrArr) {
    # regex match for ap name and ip
    $info = $ap | Select-String -Pattern '(.+?)\s*((?:[0-9]{1,3}\.){3}[0-9]{1,3}).*([A-Z0-9]{10})' 

    # if no match, skip
    if (!$info.Matches.Groups) { continue }

    # get the name and ip
    $apName = $info.Matches.Groups[1].Value
    $apIp = $info.Matches.Groups[2].Value
    $apSn = $info.Matches.Groups[3].Value

    # write ap ip and name to list
    $apList += [PSCustomObject]@{
      Name = $apName
      Ip   = $apIp
      Sn   = $apSn
    }
  }

  return $apList | Sort-Object -Property Sn
}

function send-commands { 
  Param(
    [Parameter(mandatory = $true)]$command,
    [Parameter(mandatory = $false)]$silent = $false
  )

  # loop through 3 times and try to execute the command, if it fails, try again
  $tries = 3
  for ($i = 0; $i -lt $tries - 1; $i++) {
    try {
      if (!$silent) {
        Write-Host "sending command $command ($($i + 1)/$tries)"
      }
      $global:SSHStream.read() | out-null
      Invoke-SSHStreamShellCommand -Command $command -ShellStream $global:SSHStream
      $result_stream = $global:SSHStream.read()
      return $result_stream
    }
    catch {
      # if this is the last try, throw error
      if ($i -eq $tries - 1) {
        throw "Could not execute ssh command ""$command"" on ap"
      }
      continue
    }
  }

 
}

function get-ap-name {
  Param(
    [Parameter(mandatory = $true)]$prefix,
    [Parameter(mandatory = $true)]$number
  )

  $apnumberStr = $number.ToString()

  # add leading zeros if numberdigits is set
  if ($numberdigits -gt 1) {
    $apnumberStr = $number.ToString("0" * $numberdigits)
  }

  $apName = $prefix + $apnumberStr
  return $apName
}

function write-ap-info {
  Param(
    [Parameter(mandatory = $true)]$ap,
    [Parameter(mandatory = $true)]$newApName
  )

  Write-Host ""
  Write-Host ("-" * 40)
  Write-Host "new name: $newApName" -ForegroundColor Green
  Write-Host ""
  Write-Host "old name: $($ap.Name)" -ForegroundColor Red
  Write-Host "IP: $($ap.Ip), SN: $($ap.Sn)" -ForegroundColor Red
  Write-Host ("-" * 40)
  Write-Host ""
}

function main() {
  # read settings from settings.json
  try {
    $settings = Get-Content -Raw -Path settings.json | ConvertFrom-Json
    $numberdigits = $settings.numberdigits
    $nameprefix = $settings.nameprefix
    $apnumber = $settings.firstnumber

    # throw error if numberdigits is not set or not a number between 1 and 4
    if (!$numberdigits -or $numberdigits -lt 1 -or $numberdigits -gt 4) {
      throw "settings.numberdigits must be set to a number between 1 and 4"
    }

    # throw error if nameprefix is not set or not a string or an empty string
    if (!$nameprefix -or $nameprefix -eq "" -or $nameprefix -isnot [string]) {
      throw "settings.nameprefix must be set to a string"
    }

    # throw error if firstnumber is not set or not a number between 1 and 9999
    if (!$apnumber -or $apnumber -lt 1 -or $apnumber -gt 9999) {
      throw "settings.firstnumber must be set to a number between 1 and 9999"
    }

  }
  catch {
    Write-Host "Could not read settings.json, aborting"
    Write-Host $_.Exception.Message
    return
  }

  $secpassword = ConvertTo-SecureString $settings.password -AsPlainText -Force
  $credentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $settings.username, $secpassword
  Connect-ArubaIAP $settings.ip -Username $settings.username -Credentials $credentials -SkipCertificateCheck  | out-null
  
  # get aps
  $aps = get-aps

  # print aps to console
  $aps | Format-Table -AutoSize

  # throw error if no aps found
  if ($aps.Count -eq 0) {
    throw "No APs found"
  }

  Write-Host "Found $($aps.Count) active APs" -ForegroundColor Green

  $skiptoapnumber = 1
  
  # ask the user if he wants to skip some already renamed aps
  Write-Host "Skip some already renamed APs? (y/n) [n]" -ForegroundColor Yellow
  $skip = Read-Host

  # if he wants to skip some aps, ask him for the first ap number to rename
  if ($skip -eq "y") {
    Write-Host ""
    Write-Host "First AP number to rename?" -ForegroundColor Yellow
    $skiptoapnumber = Read-Host

    try {  
      $skiptoapnumber = [int]$skiptoapnumber
    }
    catch {
      throw "Invalid number (not an integer)"
    }
  
    if ($skiptoapnumber -lt 1 -or $skiptoapnumber -gt $aps.Count) {
      throw "Invalid number (out of range)"
    }
    Write-Host ""
    Write-Host "Skipping to AP number $skiptoapnumber of $($aps.Count)" -ForegroundColor Green
  }
  else {
    $skiptoapnumber = $apnumber
    Write-Host ""
  }

  $firstapname = get-ap-name -prefix $nameprefix -number $skiptoapnumber  
  Write-Host "First AP name will be ${firstapname}" -ForegroundColor Green

  # ask the user if he wants to continue
  Write-Host "Continue? (y/n)" -ForegroundColor Yellow
  $continue = Read-Host
  if ($continue -ne "y") {
    Write-Host "Aborting" -ForegroundColor Red
    return
  }
  

  foreach ($ap in $aps) {
    if ($apnumber -lt $skiptoapnumber) {
      $apnumber++
      continue
    }

    $apName = get-ap-name -prefix $nameprefix -number $apnumber
    write-ap-info $ap $apName

    # try to establish ssh connection to ap
    # if it fails for 3 tries, skip the ap
    $tries = 3
    for ($i = 0; $i -lt $tries - 1; $i++) {
      try {
        Write-Host "establishing ssh connection... ($($i + 1)/$tries)"
        $global:SSHSession = New-SSHSession -ComputerName $ap.Ip -port 22 -Credential $credentials -AcceptKey
        $global:SSHStream = New-SSHShellStream -SSHSession $global:SSHSession
        $global:SSHStream.read() | out-null
        break
      }
      catch {
        # if this is the last try, write error and skip
        if ($i -eq $tries - 1) {
          Write-Host "Could not connect to AP, skipping"
        }
        continue
      }
    }

    # try to execute a dummy show command to see if the ssh connection is ready
    # if not, wait a second and try again
    # if it fails for 8 tries, throw error
    try {
      $tries = 8
      for ($i = 0; $i -lt $tries - 1; $i++) {
        $result = send-commands "show time-range" -silent $true

        if ($null -eq $result -or $result -eq "") {
          Write-Host "ssh connection not yet ready, waiting... ($($i + 1)/$tries)"
  
          # if this is the last try, throw error
          if ($i -eq $tries - 1) {
            throw "Could not connect to AP"
          }
          Start-Sleep -Seconds 1
        }
        else {
          break
        }
      }
    }
    catch {
      Write-Host "Could not execute ssh commands on ap, skipping"
      continue
    }

    # let the ap leds blink to indicate which ap is being renamed
    send-commands "ap-leds blink" | out-null
    Write-Host "AP LEDs set to blink"

    # rename the ap
    Set-ArubaIAPHostname -hostname $apName -iap_ip_addr $ap.Ip | out-null
    Write-Host "AP renamed to $apName"

    # wait for user to continue
    Write-Host "Press enter to continue" -ForegroundColor Yellow
    Read-Host | out-null

    # set ap leds back to normal mode
    send-commands "ap-leds normal" | out-null
    Write-Host "AP LEDs set to normal"
    Start-Sleep -Seconds 1

    # close ssh session to ap
    Remove-SSHSession -SSHSession $global:SSHSession | out-null

    # increment ap number
    $apnumber++
  }

  # disconnect from controller
  Disconnect-ArubaIAP -Confirm:$false

  Write-Host ""
  Write-Host "Done" -ForegroundColor Green
}

main