$serversFile = "C:\path\to\serverlist.txt"
function Write-Log {
    [cmdletbinding()]
    param (
        [string]$Server,
        [string]$Service,
        [string]$Reason,
        [switch]$Err,
        [switch]$Depend,
        [switch]$Reach
    )
    $logTime = (Get-Date -Format yyyy-MM-dd-HHmm)
    if($PSBoundParameters["Err"]) {
        "[$logTime]`t$server - Failed to start the $Service service - $Reason" | Out-File -FilePath $logFile -Append
    } elseif($PSBoundParameters["Depend"]) {
        "[$logTime]`t$server - Failed to start the $Service service - service depends on other services with start type set to $Reason" | Out-File -FilePath $logFile -Append
    } elseif($PSBoundParametersp["Reach"]) {
        "[$logTime]`t$server - Server cannot be reached" | Out-File -FilePath $logFile -Append
    } else {
        "[$logTime]`t$server - Failed to start the $Service service - start type is set to $Reason" | Out-File -FilePath $logFile -Append
    }
    
}

if(Test-Path -Path $serversFile) {
    $txtTime = (Get-Date -Format yyyy-MM-dd-HHmm)
    $Script:logFile = "$((Get-Location).Path)\" + $txtTime + "_SQLServer_Report.txt"
    New-Item -ItemType File -Path $logFile -Force | Out-Null

    [array]$serverList = Get-Content -Path $serversFile
    $serverCount = 1
    if($serverList.Count -gt 0) {
        foreach($server in $serverList) {
            #---Progress bar---#
            $itemPercent = [math]::round((($serverCount/$serverList.Count) * 100), 0)
            Write-Progress -Activity:"Processing $server" -Status:"Processing $serverCount of $($serverList.Count) servers ($itemPercent%)" -PercentComplete:$itemPercent -Id 1

            if(Test-Connection -ComputerName $server -Count 1 -ErrorAction SilentlyContinue) {
                try {
                    [array]$sqlServices = Get-Service -ComputerName $server -ErrorAction Stop | Where-Object {$_.DisplayName -like "*sql*"}
                } catch {
                    Write-Warning "Failed to get SQL services from $server --> $($_.Exception.Message)"
                }
                
                if($sqlServices.Count -gt 0) {
                    $filterSql = $sqlServices | Where-Object {$_.DisplayName -match "Integration|Analysis|Reporting|Agent" -or $_.DisplayName -like "*SQL Server (*)*"}
                    $filterCount = 1
                    foreach($sql in $filterSql) {
                        #---Progress bar---#
                        $sqlPercent = [math]::round((($filterCount/$filterSql.Count) * 100), 0)
                        Write-Progress -Activity:"Starting $($sql.DisplayName)" -Status:"Starting $filterCount of $($filterSql.Count) SQL services ($sqlPercent%)" -PercentComplete:$sqlPercent -Id 2 -ParentId 1
    
                        if(($sql.StartType -eq "Automatic" -and $sql.Status -ne "Running") -and $sql.ServicesDependedOn.StartType -notcontains "Manual") {
                            try {
                                Get-Service -Name $sql.Name -ComputerName $server | Set-Service -Status Running -ErrorAction Stop
                            } catch {
                                if($sql.ServicesDependedOn.StartType -contains "Disabled" -and ($sql.DisplayName -like "*SQL Server (*)" -or $sql.DisplayName -match "Agent")) {
                                    Write-Log -Server $server -Service $sql.DisplayName -Reason "Disabled" -Depend
                                } else {
                                    if($sql.DisplayName -like "*SQL Server (*)" -or $sql.DisplayName -match "Agent") {
                                        Write-Log -Server $server -Service $sql.DisplayName -Reason $_.Exception.Message -Err
                                    }
                                }
                            }
                        } elseif($sql.StartType -ne "Automatic" -and ($sql.DisplayName -like "*SQL Server (*)" -or $sql.DisplayName -match "Agent")) {
                            Write-Log -Server $server -Service $sql.DisplayName -Reason $sql.StartType
                        } elseif($sql.ServicesDependedOn.StartType -contains "Manual" -and $sql.ServicesDependedOn.DisplayName -like "*sql*" -and ($sql.DisplayName -like "*SQL Server (*)" -or $sql.DisplayName -match "Agent")) {
                            Write-Log -Server $server -Service $sql.DisplayName -Reason "Manual" -Depend
                        }
    
                        $filterCount++
                    }
                }
            } else {
                Write-Warning "Unable to reach $server - Skipped."
                Write-Log -Server $server -Reach
            }

            $serverCount++
        }
    }
} else {
    Write-Warning "Server list does not exists. Plese provide a valid path."
}