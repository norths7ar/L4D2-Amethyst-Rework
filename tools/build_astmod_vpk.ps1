param(
    [string]$SourceRoot = (Join-Path $PSScriptRoot '..\assets\astmod_vpk'),
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\addons\astmod.vpk')
)

$ErrorActionPreference = 'Stop'

function Write-CString {
    param(
        [System.IO.BinaryWriter]$Writer,
        [string]$Value
    )

    $Writer.Write([Text.Encoding]::UTF8.GetBytes($Value))
    $Writer.Write([byte]0)
}

function New-Crc32Table {
    $table = [uint32[]]::new(256)
    $polynomial = [uint64]3988292384
    for ($i = 0; $i -lt 256; $i++) {
        $value = [uint64]$i
        for ($bit = 0; $bit -lt 8; $bit++) {
            if (($value -band 1) -ne 0) {
                $value = (($value -shr 1) -bxor $polynomial) -band [uint64]4294967295
            }
            else {
                $value = ($value -shr 1) -band [uint64]4294967295
            }
        }
        $table[$i] = [uint32]$value
    }
    return $table
}

function Get-Crc32 {
    param(
        [byte[]]$Data,
        [uint32[]]$Table
    )

    $crc = [uint64]4294967295
    foreach ($value in $Data) {
        $index = [int](($crc -bxor [uint64]$value) -band 0xFF)
        $crc = (($crc -shr 8) -bxor [uint64]$Table[$index]) -band [uint64]4294967295
    }
    return [uint32](($crc -bxor [uint64]4294967295) -band [uint64]4294967295)
}

$resolvedSource = (Resolve-Path -LiteralPath $SourceRoot).Path
$fullOutput = [IO.Path]::GetFullPath($OutputPath)
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $fullOutput.StartsWith($repoRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Output path must remain inside the repository: $fullOutput"
}

$crcTable = New-Crc32Table
$entries = [System.Collections.Generic.List[object]]::new()
$sourceFiles = Get-ChildItem -LiteralPath $resolvedSource -File -Recurse | Sort-Object FullName
foreach ($file in $sourceFiles) {
    $relativePath = [IO.Path]::GetRelativePath($resolvedSource, $file.FullName).Replace('\', '/')
    $extension = $file.Extension.TrimStart('.')
    if ([string]::IsNullOrWhiteSpace($extension)) { throw "VPK entry has no extension: $relativePath" }
    $fileName = [IO.Path]::GetFileNameWithoutExtension($file.Name)
    $directory = [IO.Path]::GetDirectoryName($relativePath)
    if ([string]::IsNullOrWhiteSpace($directory)) { $directory = ' ' } else { $directory = $directory.Replace('\', '/') }
    $data = [IO.File]::ReadAllBytes($file.FullName)
    $entries.Add([pscustomobject]@{
        Extension = $extension
        Directory = $directory
        FileName = $fileName
        RelativePath = $relativePath
        Data = $data
        CRC = Get-Crc32 -Data $data -Table $crcTable
        Offset = [uint32]0
    })
}
if ($entries.Count -eq 0) { throw "No source files found under $resolvedSource" }

$dataOffset = [uint32]0
foreach ($entry in $entries) {
    $entry.Offset = $dataOffset
    $dataOffset = [uint32]($dataOffset + $entry.Data.Length)
}

$treeStream = [IO.MemoryStream]::new()
$treeWriter = [IO.BinaryWriter]::new($treeStream, [Text.Encoding]::UTF8, $true)
try {
    $extensionGroups = $entries | Group-Object Extension | Sort-Object Name
    foreach ($extensionGroup in $extensionGroups) {
        Write-CString -Writer $treeWriter -Value $extensionGroup.Name
        $directoryGroups = $extensionGroup.Group | Group-Object Directory | Sort-Object Name
        foreach ($directoryGroup in $directoryGroups) {
            Write-CString -Writer $treeWriter -Value $directoryGroup.Name
            $directoryEntries = $directoryGroup.Group | Sort-Object FileName
            foreach ($entry in $directoryEntries) {
                Write-CString -Writer $treeWriter -Value $entry.FileName
                $treeWriter.Write([uint32]$entry.CRC)
                $treeWriter.Write([uint16]0)
                $treeWriter.Write([uint16]0x7FFF)
                $treeWriter.Write([uint32]$entry.Offset)
                $treeWriter.Write([uint32]$entry.Data.Length)
                $treeWriter.Write([uint16]0xFFFF)
            }
            $treeWriter.Write([byte]0)
        }
        $treeWriter.Write([byte]0)
    }
    $treeWriter.Write([byte]0)
    $treeWriter.Flush()
    $treeBytes = $treeStream.ToArray()
}
finally {
    $treeWriter.Dispose()
    $treeStream.Dispose()
}

$outputDirectory = Split-Path -Parent $fullOutput
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    [void](New-Item -ItemType Directory -Path $outputDirectory)
}
$temporaryOutput = "$fullOutput.tmp"
$outputStream = [IO.File]::Create($temporaryOutput)
$writer = [IO.BinaryWriter]::new($outputStream)
try {
    $writer.Write([uint32]0x55AA1234)
    $writer.Write([uint32]1)
    $writer.Write([uint32]$treeBytes.Length)
    $writer.Write($treeBytes)
    foreach ($entry in $entries) { $writer.Write([byte[]]$entry.Data) }
}
finally {
    $writer.Dispose()
    $outputStream.Dispose()
}

Move-Item -LiteralPath $temporaryOutput -Destination $fullOutput -Force
"Built $fullOutput with $($entries.Count) entries"
