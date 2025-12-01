param(
    [Parameter(Mandatory = $true)]
    [string]$WebhookUrl,

    [Parameter(Mandatory = $true)]
    [string]$FilePath
)

# Datei prüfen
if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
    Write-Error "❌ Datei nicht gefunden: $FilePath"
    exit 1
}

# Datei lesen
$fileName = Split-Path -Path $FilePath -Leaf
$fileBytes = [System.IO.File]::ReadAllBytes($FilePath)

# JSON-Metadaten
$meta = @{
    fileName  = $fileName
    host      = $env:COMPUTERNAME
    timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}
$metaJson = $meta | ConvertTo-Json

# Multipart Datei
$fileContent = [System.Net.Http.ByteArrayContent]::new(@($fileBytes))
$fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::new("application/octet-stream")
$fileContent.Headers.ContentDisposition = New-Object System.Net.Http.Headers.ContentDispositionHeaderValue "form-data"
$fileContent.Headers.ContentDisposition.Name = "file"
$fileContent.Headers.ContentDisposition.FileName = $fileName

# Multipart JSON
$jsonContent = New-Object System.Net.Http.StringContent($metaJson, [System.Text.Encoding]::UTF8, "application/json")
$jsonContent.Headers.ContentDisposition = New-Object System.Net.Http.Headers.ContentDispositionHeaderValue "form-data"
$jsonContent.Headers.ContentDisposition.Name = "data"

# Multipart Body
$form = @{
    file = $fileContent
    data = $jsonContent
}

Write-Host "📤 Sende Datei '$fileName' an n8n ..."

try {
    Invoke-RestMethod -Uri $WebhookUrl -Method Post -Form $form
    Write-Host "✅ Upload erfolgreich!"
}
catch {
    Write-Error "❌ Fehler beim Upload: $($_.Exception.Message)"
}
