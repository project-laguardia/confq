param (
    [string] $Upstream = (& {
        throw "Upstream parameter is required. Please provide a valid repository URL."
    }),
    [string] $Repository = (& {
        throw "Repository parameter is required. Please provide a valid repository path."
    }),
    [string] $Output = (& {
        $default = "tracking"
        New-Item -Path -Path $default -ItemType Directory -Force | Out-Null
        $default
    }),
    [switch] $Verbose
)

function global:Get-UnmergedCommits {
    param (
        [string] $Upstream = (& {
            throw "Upstream parameter is required. Please provide a valid repository URL."
        }),
        [string] $Repository = (& {
            throw "Repository parameter is required. Please provide a valid repository path."
        }),
        [switch] $InProgress, # reviewed .. in-progress
        [switch] $Pending, # in-progress .. upstream head
        [switch] $Verbose
    )

    pushd $Repository
    # ensure upstream is set

    # Hack to reset $LASTEXITCODE to 0
    & (Resolve-Path "$PSHome\p*w*sh*" | Where-Object {
        $Path = "$_"

        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            return $false
        }

        if ($IsWindows) {
            $ext = [IO.Path]::GetExtension($Path)
            $pathext = ($env:PATHEXT -split ';') -replace '^\.', ''
            return $pathext -contains $ext.TrimStart('.').ToUpperInvariant()
        } else {
            $escapedPath = $Path.Replace("'", "''")

            # Prefer bash, fallback to sh
            $shell = if (Get-Command bash -ErrorAction SilentlyContinue) { "bash" } else { "sh" }

            & $shell -c "test -x '$escapedPath'"
            return ($LASTEXITCODE -eq 0)
        }
    } | Select-Object -First 1) -v | Out-Null

    $remotes = @{}
    git remote -v 2>$null | ForEach-Object {
        if ($_ -match '^(\S+)\s+(\S+)') {
            $remotes[$matches[1]] = $matches[2]
        }
    }
    $remote = $remotes.Keys | ForEach-Object { $_ } | Where-Object {
        $remotes."$_" -eq $Upstream
    }
    If( "$remote".Trim() -eq "" ){
        $remote = "upstream"
        git remote set-url $remote $Upstream 2>&1 | ForEach-Object {
            If( $LASTEXITCODE -ne 0 ){
                throw "$_"
            }
            If( $_ -is [System.Management.Automation.ErrorRecord] ) {
                throw $_.Exception
            }
            If( $Verbose ) {
                If ( $_ -is [System.Management.Automation.WarningRecord] ) {
                    Write-Host $_.Message -ForegroundColor Yellow
                } else {
                    Write-Host "$Repository`: $_" -ForegroundColor DarkGray
                }
            }
        }
    }

    git remote set-url upstream $Upstream

    git fetch --tags

    $range = if (([bool]$InProgress) -eq ([bool]$Pending)) {
        "full"
    } elseif ($InProgress) {
        "in-progress"
    } else {
        "pending"
    }

    $reviewed = git tag --list "reviewed/*" | Select-Object -Last 1
    $in_progress = git tag --list "in-progress/*" | Select-Object -Last 1

    $start = if( ($range -eq "pending") -and ("$in_progress".Trim() -ne "") ) {
        $in_progress
    } else {
        if ("$reviewed".Trim() -ne "") {
            $reviewed
        } else {
            "fork"
        }
    }
    $end = if( ($range -eq "in-progress") -and ("$in_progress".Trim() -ne "")) {
        $in_progress
    } else {
        "upstream/main"
    }

    $commits = git rev-list --reverse "$start..$end"

    $diffs = [ordered]@{}
    # get the diffs
    foreach ($commit in $commits) {
        $diff = git show --format= --no-prefix $sha
        if ("$diff".Trim() -ne "") {
            $diffs[$commit] = $diff
        }
    }
    popd
    return @{
        Start = $start
        End = $end
        Range = $range
        Commits = $commits
        Diffs = $diffs
    }
}

If( $FunctionOnly ) {
    return
}

$location = (& {
    $location = New-Object @{
        Path = $null
        Origin = $null
    }
    $location | Add-Member -MemberType ScriptMethod -Name "Update" -Value {
        If( Test-Path $this.Path -ErrorAction SilentlyContinue ){
            $path = Resolve-Path "$($this.Path)/.."
            $this.Path = git -C "$path" rev-parse --show-toplevel 2>$null
            $this.Origin = git -C "$path" remote get-url origin 2>$null
        } Else {
            $this.Path = git rev-parse --show-toplevel 2>$null
            $this.Origin = git remote get-url origin 2>$null
        }
        return $this
    }
    $location.Update()
})

While( "$($location.Origin)".Trim() -ne $SDKOrigin.Trim() ) {
    $location.Update()
    If( "$($location.Path)".Trim() -eq "" ){
        $location.Path = Get-Location
        break
    }
}

pushd $location.Path

# In-Progress
& {
    $params = @{
        Upstream = $Upstream
        Repository = $Repository
        InProgress = $true
    }
    If( $Verbose ) {
        $params.Verbose = $true
        Write-Host "Aggregating in-progress commits..." -ForegroundColor Green
    }
    Get-UnmergedCommits @params | ConvertTo-Json -Depth 10 | Out-File -FilePath "$Output/in-progress.json" -Encoding utf8 -Force
}

# Pending
& {
    $params = @{
        Upstream = $Upstream
        Repository = $Repository
        Pending = $true
    }
    If( $Verbose ) {
        $params.Verbose = $true
        Write-Host "Aggregating pending commits..." -ForegroundColor Green
    }
    Get-UnmergedCommits @params | ConvertTo-Json -Depth 10 | Out-File -FilePath "$Output/pending.json" -Encoding utf8 -Force
}

# Full
& {
    $params = @{
        Upstream = $Upstream
        Repository = $Repository
    }
    If( $Verbose ) {
        $params.Verbose = $true
        Write-Host "Aggregating all unmerged commits..." -ForegroundColor Green
    }
    Get-UnmergedCommits @params | ConvertTo-Json -Depth 10 | Out-File -FilePath "$Output/full.json" -Encoding utf8 -Force
}

popd