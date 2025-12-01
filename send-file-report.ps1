param(
    # Die Webhook-URL, obligatorisch
    [Parameter(Mandatory=$true)]
    [string]$WebhookUrl,
    
    # Der Pfad zur Datei (z.B. test.txt), obligatorisch
    [Parameter(Mandatory=$true)]
    [string]$FilePath
)

# Prüfen, ob die Datei existiert
if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
    Write-Error "❌ Fehler: Datei nicht gefunden unter: $FilePath"
    exit 1
}

# -----------------------------------------------------------
# VORBEREITUNG DER DATEN
# -----------------------------------------------------------

$fileName = Split-Path -Path $FilePath -Leaf
$fileBytes = [System.IO.File]::ReadAllBytes($FilePath)

# Metadaten als JSON
# Diese Metadaten werden im n8n Webhook-Node als JSON-Daten verfügbar sein.
$metaData = @{
    dateiname = $fileName
    host = $env:COMPUTERNAME
    zeitstempel = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
}
$metaDataJson = $metaData | ConvertTo-Json

# -----------------------------------------------------------
# MULTIPART/FORM-DATA ERSTELLEN (Korrektur für PowerShell 5.1)
# -----------------------------------------------------------

# NEU: Das Byte-Array als Argument im Array-Format übergeben, 
# um das fehlerhafte Zählverhalten von New-Object zu umgehen
$fileContentObj = [System.Net.Http.ByteArrayContent]::new(@($fileBytes))

# Hinzufügen des Dateinamens und Content-Disposition Headers
# Wichtig: Zuerst den ContentDispositionHeader erzeugen und dann zuweisen
$contentDisposition = New-Object System.Net.Http.Headers.ContentDispositionHeaderValue "form-data"

# Die Eigenschaften können jetzt gesetzt werden, da das Objekt korrekt existiert
$contentDisposition.FileName = $fileName
$contentDisposition.Name = "uploaded_file" 

# Header dem ByteArrayContent Objekt zuweisen
$fileContentObj.Headers.ContentDisposition = $contentDisposition

# Erstellen des multipart-Formulars
$form = @{
    "uploaded_file" = $fileContentObj 
    "metadata" = $metaDataJson
}

Write-Host "Sende Datei '$fileName' von Host '$($env:COMPUTERNAME)'..."

# -----------------------------------------------------------
# WEBHOOK SENDEN
# -----------------------------------------------------------
try {
    Invoke-RestMethod `
        -Uri $WebhookUrl `
        -Method Post `
        -Form $form
    
    Write-Host "✅ Bericht erfolgreich an n8n gesendet."
}
catch {
    Write-Error "❌ Fehler beim Senden: $($_.Exception.Message)"
}