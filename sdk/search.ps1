param(
    [string] $Researching = (& {
        throw "Researching parameter is required. Please provide a valid repository URL."
    }),
    [string] $Origin = "https://github.com/project-laguardia/sdk",
    [switch] $FunctionOnly,
    [string] $Repository = (& {
        If( -not $FunctionOnly ){
            throw "Repository parameter is required. Please provide a valid repository path."
        }
    }),
    [string] $BaseURL = (& {
        $sha = (git ls-remote $Researching "HEAD").Split("`t") | Select-Object -First 1
        return "$Researching/tree/$sha"
    }),
    [string] $Output = (& {
        $default = "tracking"
        New-Item -Path $default -ItemType Directory -Force | Out-Null
        $default
    }),
    $Extensions = $null,
    $Filenames = $null,
    $Shebangs = $null,
    $Languages = $null,
    $OmitLanguages = $null,
    [switch] $Verbose,
    [switch] $Force
)

$ErrorActionPreference = "Stop"

New-Module -Name "Laguardia.SDK.Search" {
    param(
        [string] $DefaultRepository
    )

    # These are files you are not certain you want to omit or include from the search, but don't want to review
    # $global:DEBUGGING_LANGUAGE = "Menuconfig Makefile JSON XML Shell Perl C# Java Lex Yacc Diff INI CMake Python"
    $_DEBUGGING_LANGUAGE = If( -not ([string]::IsNullOrWhitespace( $global:DEBUGGING_LANGUAGE )) ){
        $global:DEBUGGING_LANGUAGE
    } elseif ( -not ([string]::IsNullOrWhitespace( $env:DEBUGGING_LANGUAGE )) ){
        $env:DEBUGGING_LANGUAGE
    }
    $_DEBUGGING_LANGUAGE = $_DEBUGGING_LANGUAGE -split " "

    $cache = @{
        Path = $null
        Files = $null
        Extensions = $null
        Filenames = $null
        Shebangs = $null
        Languages = $null

        Summary = $null
        Filtered = $null

        Enry = $null
    }

    function Test-FileExecutable {
        param([string]$Path)

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
    }

    # Sometimes enry returns an empty string for the language
    # If this happens, set DEBUGGING_LANGUAGE to non-empty (or a list of languages you would like to not check), run the script again, and fix the Format-Lang function

    function Format-Lang {
        param(
            [string] $Lang,
            [string] $Path
        )
        If( "$Lang".Trim() -eq "UnrealScript" ){
            return "JavaScript" # Enry returns UnrealScript for some Ucode files
        }
        If( "$Lang".Trim() -eq "SVG" ){
            return "Image"
        }
        If( "$Lang".Trim() -eq "" ){
            switch( (gi $Path).Name ){
                "NOTICE" { return "Text" }
                "README" { return "Text" }
                { $_ -like "README.*" } { return "Text" }
                "Config.in" { return "Menuconfig" }
                "BigIntConfig.in" { return "Menuconfig" }
                "linuxconfig" { return "Makefile" }
                "win32config" { return "Makefile" }
                "makefile.conf" { return "Makefile" }
                { $_ -like "makefile.*.conf" } { return "Makefile" }
                "makefile.post" { return "Makefile" }
                { $_ -like "*.ut" } { return "JavaScript" } # Really Ucode, but ucode is a subset of JS
                { $_ -like "*.json" } { return "JSON" }
                { $_ -like "*.png" } { return "Image" }
                { $_ -like "*.gif" } { return "Image" }
                { $_ -like "*.jpg" } { return "Image" }
                { $_ -like "*.ico" } { return "Image" }
                { $_ -like "*.woff2" } { return "Font" }
                { $_ -like "*.lp" } { return "Lua" }
                { $_ -like "*.luadoc" } { return "Lua" }
                { $_ -like "*.jmx" } { return "XML" }
                { $_ -like "*.c_shipped" } { return "C" }
                { $_ -like "*.h_shipped" } { return "C" }
                { $_ -like "*.c.old" } { return "C" }
                { $_ -like "*.c.bak" } { return "C" }
                { $_ -like "*.mf" } { return "INI" }
                { $_ -like "*.pem" } { return "Certificate" }
                { $_ -like "*.cer" } { return "Certificate" }
                { $_ -like "*.p8" } { return "Certificate" }
                { $_ -like "*.p12" } { return "Certificate" }
                { $_ -like "*.pfx" } { return "Certificate" }
                { $_ -like "*.der" } { return "Certificate" }
                
                default {
                    $shebang = Get-Content -Path $Path -TotalCount 1 -ErrorAction SilentlyContinue
                    switch( $shebang ){
                        { "$_".Trim() -like "#!/usr/bin/env ucode*"} { return "JavaScript" }
                        { "$_".Trim() -like "config *" }{ return "UCI Config" }
                        { "$_".Trim() -like "'use strict';" }{ return "JavaScript" }
                        default {
                            $content = Get-Content -Path $Path -ErrorAction SilentlyContinue

                            $first_actual_line = $content | Where-Object {
                                # Skip empty lines and comments
                                $line = "$_".Trim()
                                -not (@(
                                    ($line -eq "")
                                    ($line -like "#*")
                                    ($line -like "// *")
                                ) -contains $true)
                            } | Select-Object -First 1

                            switch( "$first_actual_line" ){
                                "" {
                                    If( $Path -like "*etc/config*" ){
                                        "UCI Config"
                                    } else {
                                        "Unknown"
                                    }
                                }
                                { "$_".Trim() -like "config *" }{ return "UCI Config" }
                                { "$_".Trim() -like "'use strict';" }{ return "JavaScript" }
                                default {
                                    return "Unknown"
                                }
                            }
                        }
                    }
                }
            }
        }
        return "$Lang".Trim()
    }

    function global:Find-InSource {
        param(
            [string] $Pattern,
            [string] $Researching = (& {
                throw "Researching parameter is required. Please provide a valid repository URL."
            }),
            [string] $Repository = $DefaultRepository,
            [string[]] $Extensions = $null,
            [string[]] $Shebangs = $null,
            [string[]] $Filenames = $null,
            [string[]] $Languages = $null,
            [string[]] $OmitLanguages = $null,
            [switch] $Verbose,
            [switch] $Force
        )

        $gitRoot = (git rev-parse --show-toplevel 2>$null)

        $enry = If( Test-Path $cache.Enry -ErrorAction SilentlyContinue ) {
            $cache.Enry
        } Elseif ( (-not $Force) -and $IsWindows -and (Test-FileExecutable "./enry.exe" -ErrorAction SilentlyContinue)) {
            "./enry.exe" | Resolve-Path
        } Elseif ( (-not $Force) -and (Test-FileExecutable "./enry" -ErrorAction SilentlyContinue)) {
            "./enry" | Resolve-Path
        } Else {
            $old_sugggestions = $global:DisableCommandSuggestions
            $global:DisableCommandSuggestions = $true
            Try {
                (gcm enry -ErrorAction Stop).Path | Resolve-Path -ErrorAction Stop
            } Catch {
                If( $Verbose ) {
                    Write-Host "Enry not found! Fetching and building enry..." `
                        -BackgroundColor Yellow `
                        -ForegroundColor Black `
                        -NoNewline; Write-Host # Prevent color spillover
                }
                $tmp = New-TemporaryFile | % { rm $_; ni $_ -ItemType Directory }
                & {
                    pushd $tmp

                    # Hack to reset $LASTEXITCODE to 0
                    & (Resolve-Path "$PSHome\p*w*sh*" | Where-Object {
                        Test-FileExecutable $_
                    } | Select-Object -First 1) -v | Out-Null

                    & { # go logs to stderr, so we have to handle it independently
                        go mod init tempmod
                        go get github.com/go-enry/enry
                        go build -o ./enry github.com/go-enry/enry
                    } 2>&1 | ForEach-Object {
                        If( $LASTEXITCODE -ne 0 ){
                            throw "$_"
                        }
                        If( $Verbose ) {
                            If( $_ -is [System.Management.Automation.ErrorRecord] ) {
                                Write-Host $_.Exception.Message -ForegroundColor DarkGray
                            } elseif ( $_ -is [System.Management.Automation.WarningRecord] ) {
                                Write-Host $_.Message -ForegroundColor Yellow
                            } else {
                                Write-Host $_ -ForegroundColor DarkGray
                            }
                        }
                    }
                    popd
                    If( $IsWindows ) {
                        cp "$tmp/enry.exe" "./enry.exe"
                    } else {
                        cp "$tmp/enry" "./enry"
                    }
                    Remove-Item -Path $tmp -Recurse -Force
                } 2>&1 | ForEach-Object {
                    If( $_ -is [System.Management.Automation.ErrorRecord] ) {
                        throw $_.Exception
                    }
                    If( $Verbose ) {
                        If ( $_ -is [System.Management.Automation.WarningRecord] ) {
                            Write-Host $_.Message -ForegroundColor Yellow
                        } else {
                            Write-Host $_ -ForegroundColor DarkGray
                        }
                    }
                }
                "./enry" | Resolve-Path
            }
            $global:DisableCommandSuggestions = $old_sugggestions
        }
        $cache.Enry = $enry

        $output = [ordered]@{}

        $Repository = Resolve-Path $Repository
        $extensions_csv = $Extensions -join ','
        $filenames_csv = $Filenames -join ','
        $shebangs_csv = $Shebangs -join ','
        $languages_csv = $Languages -join ','

        If( ($cache.Path -eq $Repository) -and (-not $Force) ) {
            If( @(
                ([bool]($cache.Extensions -ne $extensions_csv))
                ([bool]($cache.Filenames -ne $filenames_csv))
                ([bool]($cache.Shebangs -ne $shebangs_csv))
                ([bool]($cache.Languages -ne $languages_csv))
            ) -contains $true ){
                If( $Verbose ) {
                    Write-Host "Cache is old. Refiltering source files with:" `
                        -BackgroundColor Yellow `
                        -ForegroundColor Black `
                        -NoNewline; Write-Host # Prevent color spillover
                    If( $Extensions.Count ) {
                        Write-Host "  - Extensions: " -ForegroundColor Yellow
                        $Extensions | ForEach-Object {
                            Write-Host "    - $_" -ForegroundColor DarkGray
                        }
                    } else {
                        Write-Host "  - Extensions: " -ForegroundColor Yellow -NoNewline
                        Write-Host "(none)" -ForegroundColor DarkGray
                    }
                    If( $Filenames.Count ) {
                        Write-Host "  - Filenames: " -ForegroundColor Yellow
                        $Filenames | ForEach-Object {
                            Write-Host "    - $_" -ForegroundColor DarkGray
                        }
                    } else {
                        Write-Host "  - Filenames: " -ForegroundColor Yellow -NoNewline
                        Write-Host "(none)" -ForegroundColor DarkGray
                    }
                    If( $Shebangs.Count ) {
                        Write-Host "  - Shebangs: " -ForegroundColor Yellow
                        $Shebangs | ForEach-Object {
                            Write-Host "    - $_" -ForegroundColor DarkGray
                        }
                    } else {
                        Write-Host "  - Shebangs: " -ForegroundColor Yellow -NoNewline
                        Write-Host "(none)" -ForegroundColor DarkGray
                    }
                    If( $Languages.Count ) {
                        Write-Host "  - Languages: " -ForegroundColor Yellow
                        $Languages | ForEach-Object {
                            Write-Host "    - $_" -ForegroundColor DarkGray
                        }
                    } else {
                        Write-Host "  - Languages: " -ForegroundColor Yellow -NoNewline
                        Write-Host "(none)" -ForegroundColor DarkGray
                    }
                    Write-Host "- Wait a moment, this may take a bit..." -ForegroundColor DarkGray
                }

                $cache.Extensions = $extensions_csv
                $cache.Filenames = $filenames_csv
                $cache.Shebangs = $shebangs_csv
                $cache.Languages = $languages_csv
                
                $cache.Summary = [ordered]@{}
            
                $total = $cache.Files.Count
                $counter = 0
                $cache.Filtered = $cache.Files | Where-Object {
                    $counter++
                    $percent = [math]::Round(($counter / $total) * 100, 2)
                    If( $Verbose ){
                        Write-Progress -Activity "Filtering files" `
                            -Status "Processing file $counter of $total ($percent%)" `
                            -CurrentOperation "$($_.FullName)" `
                            -PercentComplete $percent
                    }
                    
                    $lang = & $enry -json $_.FullName | ConvertFrom-Json -ErrorAction Stop | Select-Object -ExpandProperty language
                    # Pass through catch all
                    $lang = Format-Lang -Lang $lang -Path $_.FullName

                    $hit = (& {
                        If( $Languages.Count -and ($Languages -contains $lang) ){ return $true }
                        If( $Extensions -contains $_.Extension ){ return $true }
                        If( $Filenames.Count -and $Filenames -contains $_.Name ){ return $true }

                        $file = $_.FullName
                        $shebang = Get-Content -Path $file -TotalCount 1 -ErrorAction SilentlyContinue
                        $Shebangs | ForEach-Object {
                            if ($shebang -like "$_*") {
                                return $true
                            }
                        }

                        return $false
                    })
                    
                    If( $hit ){
                        $_ | Add-Member -MemberType NoteProperty -Name "Language" -Value $lang -Force
                        If( -not ($cache.Summary."$lang".Count) ){
                            $cache.Summary."$lang" = @()
                        }
                        $cache.Summary."$lang" = (& {
                            $cache.Summary."$lang"
                            $_.FullName.Replace($gitRoot, '').TrimStart('\/')
                        }) | Select-Object -Unique | Where-Object { "$_".Trim() -ne "" }
                        return $true
                    }
                } | Select-Object -Unique
            }
        } else {

            If( $Verbose ){
                Write-Host "Updating repository..." `
                    -BackgroundColor Green `
                    -ForegroundColor Black `
                    -NoNewline; Write-Host # Prevent color spillover
            }

            # Hack to reset $LASTEXITCODE to 0
            & (Resolve-Path "$PSHome\p*w*sh*" | Where-Object {
                Test-FileExecutable $_
            } | Select-Object -First 1) -v | Out-Null

            $remotes = @{}
            git -C $repository remote -v 2>$null | ForEach-Object {
                if ($_ -match '^(\S+)\s+(\S+)') {
                    $remotes[$matches[1]] = $matches[2]
                }
            }
            $remote = $remotes.Keys | ForEach-Object { $_ } | Where-Object {
                $remotes."$_" -eq $Researching
            }
            If( "$remote".Trim() -eq "" ){
                $remote = "researching"
                git -C $repository remote set-url $remote $Researching 2>&1 | ForEach-Object {
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

            git -C $Repository pull $remote 2>&1 | ForEach-Object {
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

            If( $Verbose ) {
                Write-Host "Cache not set. Aggregating source files..." `
                    -BackgroundColor Yellow `
                    -ForegroundColor Black `
                    -NoNewline; Write-Host # Prevent color spillover
            }
            
            $cache.Path = $Repository
            $cache.Files = Get-ChildItem -Path $Repository -File -Recurse
            $cache.Extensions = $extensions_csv
            $cache.Filenames = $filenames_csv
            $cache.Shebangs = $shebangs_csv
            $cache.Languages = $languages_csv

            $cache.Summary = [ordered]@{}

            If( $Verbose ) {
                Write-Host "Files aggregated. Filtering source files with" `
                    -BackgroundColor Magenta `
                    -ForegroundColor Black `
                    -NoNewline; Write-Host # Prevent color spillover
                If( $Extensions.Count ) {
                    Write-Host "  - Extensions: " -ForegroundColor Yellow
                    $Extensions | ForEach-Object {
                        Write-Host "    - $_" -ForegroundColor DarkGray
                    }
                } else {
                    Write-Host "  - Extensions: " -ForegroundColor Yellow -NoNewline
                    Write-Host "(none)" -ForegroundColor DarkGray
                }
                If( $Filenames.Count ) {
                    Write-Host "  - Filenames: " -ForegroundColor Yellow
                    $Filenames | ForEach-Object {
                        Write-Host "    - $_" -ForegroundColor DarkGray
                    }
                } else {
                    Write-Host "  - Filenames: " -ForegroundColor Yellow -NoNewline
                    Write-Host "(none)" -ForegroundColor DarkGray
                }
                If( $Shebangs.Count ) {
                    Write-Host "  - Shebangs: " -ForegroundColor Yellow
                    $Shebangs | ForEach-Object {
                        Write-Host "    - $_" -ForegroundColor DarkGray
                    }
                } else {
                    Write-Host "  - Shebangs: " -ForegroundColor Yellow -NoNewline
                    Write-Host "(none)" -ForegroundColor DarkGray
                }
                If( $Languages.Count ) {
                    Write-Host "  - Languages: " -ForegroundColor Yellow
                    $Languages | ForEach-Object {
                        Write-Host "    - $_" -ForegroundColor DarkGray
                    }
                } else {
                    Write-Host "  - Languages: " -ForegroundColor Yellow -NoNewline
                    Write-Host "(none)" -ForegroundColor DarkGray
                }
                Write-Host "- Wait a moment, this may take a bit..." -ForegroundColor Cyan
            }

            If( $_DEBUGGING_LANGUAGE.Count ){
                Write-Host "DEBUGGING_LANGUAGE is set!" `
                    -ForegroundColor Red `
                    -BackgroundColor Black `
                    -NoNewline; Write-Host # Prevent color spillover
            }
            
            $total = $cache.Files.Count
            $counter = 0
            $cache.Filtered = $cache.Files | Where-Object {
                $counter++
                $percent = [math]::Round(($counter / $total) * 100, 2)
                If( $Verbose ){
                    Write-Progress -Activity "Filtering files" `
                        -Status "Processing file $counter of $total ($percent%)" `
                        -CurrentOperation "$($_.FullName)" `
                        -PercentComplete $percent
                }
                
                $lang = & $enry -json $_.FullName | ConvertFrom-Json -ErrorAction Stop | Select-Object -ExpandProperty language

                # Pass through catch all
                $lang = Format-Lang -Lang $lang -Path $_.FullName

                If( $_DEBUGGING_LANGUAGE.Count ){
                    $path = $_.FullName.Replace($gitRoot, '').TrimStart('\/')
                    
                    If((-not ((& {
                        $OmitLanguages
                        $Languages
                        $_DEBUGGING_LANGUAGE
                    }) -icontains "$lang".Trim())) -or ("$lang").Trim() -eq "") {
                        Write-Host "$lang`:" $_.FullName -ForegroundColor Yellow
                        pause
                    } else {
                        Write-Host "$lang`:" $_.FullName -ForegroundColor DarkGray
                    }
                }

                $hit = (& {
                    If( $Languages.Count -and ($Languages -contains $lang) ){ return $true }
                    If( $Extensions -contains $_.Extension ){ return $true }
                    If( $Filenames.Count -and $Filenames -contains $_.Name ){ return $true }

                    $file = $_.FullName
                    $shebang = Get-Content -Path $file -TotalCount 1 -ErrorAction SilentlyContinue
                    $Shebangs | ForEach-Object {
                        if ($shebang -like "$_*") {
                            return $true
                        }
                    }

                    return $false
                })
                
                If( $hit ){
                    $_ | Add-Member -MemberType NoteProperty -Name "Language" -Value $lang -Force
                    If( -not ($cache.Summary."$lang".Count) ){
                        $cache.Summary."$lang" = @()
                    }
                    $cache.Summary."$lang" = (& {
                        $cache.Summary."$lang"
                        $_.FullName.Replace($gitRoot, '').TrimStart('\/')
                    }) | Select-Object -Unique | Where-Object { "$_".Trim() -ne "" }
                    return $true
                }
            } | Select-Object -Unique
        }

        $files = $cache.Filtered

        if ($files.Count -eq 0) {
            Write-Host "No files found with the specified extensions." -ForegroundColor Yellow
            return
        } elseif ( $Verbose ) {
            Write-Host "Searching in $($files.Count) files with extensions: $($Extensions -join ', ')" `
                -ForegroundColor Black `
                -BackgroundColor DarkYellow `
                -NoNewline; Write-Host # Prevent color spillover
        }

        $files | ForEach-Object {
            $filename = Try {
                readlink -f $_.FullName
            } Catch {}
            If( "$filename".Trim() -eq "" ){
                $filename = $_.FullName
            }
            $filename = $filename.Replace($gitRoot, '').TrimStart('\/')
            $fileContent = Get-Content $_.FullName

            $hits = for ($ln = 0; $ln -lt $fileContent.Count; $ln++) {
                $line = $fileContent | Select-Object -Index $ln
                if ($line -match $pattern) {
                    @{
                        Line = $ln + 1
                        Content = $line.Trim()
                    }
                }
            }

            if ($hits.Count -gt 0) {
                $output."$filename" = [ordered]@{}
                $output."$filename".Language = $_.Language
                $output."$filename".Lines = [ordered]@{}

                $hits | ForEach-Object {
                    $output."$filename".Lines."$($_.Line)" = $_.Content
                }

                If( $Verbose ){
                    Write-Host "$filename`:" -ForegroundColor Cyan
                    Write-Host " (Language: $($_.Language))" -ForegroundColor DarkGray

                    $hits | ForEach-Object {
                        Write-Host "L$($_.Line)" -NoNewline -ForegroundColor Gray
                        Write-Host ": $($_.Content)"
                    }
                    Write-Host ""
                }
            }
        }

        If( $Verbose ) {
            $total_files = $output.Keys.Count
            $total_hits = ($output.Values | ForEach-Object { $_.Count }) -as [int[]] | Measure-Object -Sum | Select-Object -ExpandProperty Sum

            Write-Host "Found $total_hits hits in $total_files files." -ForegroundColor Green
            
            $langs = $cache.Summary.Keys | ForEach-Object { $_ } | Where-Object {
                If( $OmitLanguages -and ($OmitLanguages -contains $_) ){ return $false }
                return $true
            }

            $total = (($langs | ForEach-Object { $cache.Summary."$_".Count }) -as [int[]]) | Measure-Object -Sum | Select-Object -ExpandProperty Sum

            $langs | ForEach-Object {
                $count = $cache.Summary."$_".Count
                If( $count -gt 0 ){
                    Write-Host "Language: $_" -ForegroundColor Magenta
                    Write-Host "  - Files: $count" -ForegroundColor DarkGray
                    $percentage = [math]::Round(($count / $total) * 100, 2)
                    $color = If( $percentage -ge 90 ) { "DarkGreen" } `
                            elseif ( $percentage -ge 80 ) { "Green" } `
                            elseif ( $percentage -ge 50 ) { "Yellow" } `
                            elseif ( $percentage -ge 20 ) { "DarkYellow" } `
                            else { "DarkGray" }
                    Write-Host "  - Percentage: $($percentage)%" -ForegroundColor $color
                }
            }
        }

        return $output
    }

    Export-ModuleMember -Function Find-InSource
} -ArgumentList $Repository | Import-Module | Out-Null

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

While( "$($location.Origin)".Trim() -ne $Origin.Trim() ) {
    $location.Update()
    If( "$($location.Path)".Trim() -eq "" ){
        $location.Path = Get-Location
        break
    }
}

pushd $location.Path

function Remove-LiteralPrefix {
    param (
        [string]$String,
        [string]$Prefix
    )

    if ($String.StartsWith($Prefix)) {
        return $String.Substring($Prefix.Length)
    } else {
        return $String
    }
}

& { # Example
    $params = @{
        Pattern = (& {
            # Put a regex pattern here to search for
        })
        Researching = $Researching
        Repository = $Repository
        Extensions = $Extensions
        Shebangs = $Shebangs
        Filenames = $Filenames
        Languages = $Languages
        OmitLanguages = $OmitLanguages
    }
    If( $Verbose ) {
        $params.Verbose = $true
        Write-Host "Searching for '<something>' in the source code..." -ForegroundColor Magenta
    }
    If( $Force ){
        $params.Force = $true
    }
    $hits = Find-InSource @params
    $hits | ConvertTo-Json -Depth 5 | Out-File "$Output/results.json" -Encoding UTF8
    $hits.Keys | ForEach-Object {
        $path = (Remove-LiteralPrefix -String $_ -Prefix $params.Repository.Trim("./\")).TrimStart('.\/')
        $base_url = $BaseURL.TrimEnd('/')
        $url = "$base_url/$path"
        return "[$path]($url)"
    } | Out-File "$Output/results.txt" -Encoding UTF8
}
popd