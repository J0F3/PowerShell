﻿<#
.SYNOPSIS 
Requests a certificate from a Windows CA

.DESCRIPTION
Requests a certificates with the specified subject name from am Windows CA and saves the resulting certificate with the private key in the local computer store.

You must specify at least the CN for the subject name.

With the SAN parameter you can also specify values for subject alternative name to request a SAN certificate.
The CA must support this type of certificate otherwise the request will fail.

With the Export parameter it's also possible to export the requested certificate (with private key) directly to a .pfx file instead of storing it in the local computer store.

You can also use the Import-CSV cmdlet with Request-Certificate.ps1 to request multiple certificates. 
To do this, use the Import-CSV cmdlet to create custom objects from a comma-separated value (CSV) file that contains a list of object properties (such as CN, SAN etc. ). Then pass these objects through the pipeline to Request-Certificate.ps1 to request the certificates.
    
.PARAMETER CN
Specifies the common name for the subject of the certificate(s).
Mostly its the FQDN of a website or service.
e.g. test.jofe.ch

.PARAMETER SAN
Specifies a comma separated list of subject alternate names (FQDNs) for the certificate
The syntax is {tag}={value}.
Valid tags are: email, upn, dns, guid, url, ipaddress, oid 
e.g. dns=test.jofe.ch,email=jfeller@jofe.ch

.PARAMETER TemplateName
Specifies the name for the temple of the CA to issue the certificate(s). 
The default value is "WebServer".

.PARAMETER CAName
Specifies the name of the CA to send the request to in the format FQDN\CAName
If the CAName is not specified, then certutil -dump is used to retrieve a list of enterprise CAs.
If more than one is returned the user is prompted to choose an enterprise CA from the local Active Directory.

.PARAMETER Export
Exports the certificate and private key to a pfx file instead of installing it in the local computer store.
By default the certificate will be installed in the local computer store.

.PARAMETER ExportPath
Path to wich the pfx file should be saved when -Export is specified.

.PARAMETER Country
Specifies two letter for the optional country value in the subject of the certificate(s).
e.g. CH

.PARAMETER State
Specifies the optional state value in the subject of the certificate(s).
e.g. Berne

.PARAMETER City
Specifies the optional city value in the subject of the certificate(s).
e.g. Berne

.PARAMETER Organisation
Specifies the optional organisation value in the subject of the certificate(s).
e.g. jofe.ch

.PARAMETER Department
Specifies the optional department value in the subject of the certificate(s).
e.g. IT

.INPUTS
System.String
Common name for the subject, SAN , Country, State etc. of the certificate(s) as a string 

.OUTPUTS
None. Request-Certificate.ps1 does not generate any output.

.EXAMPLE
C:\PS> .\Request-Certificate.ps1

Description
-----------
This command requests a certificate form the enterprise CA in the local Active Directory.
The user will be asked for the value for the CN of the certificate.

.EXAMPLE
C:\PS> .\Request-Certificate.ps1 -CAName "testsrv.test.ch\Test CA"

Description
-----------
This command requests a certificate form the CA testsrv.test.ch\Test CA.
The user will be asked for the value for the CN of the certificate.

.EXAMPLE
C:\PS> .\Request-Certificate.ps1 -CN "webserver.test.ch" -CAName "testsrv.test.ch\Test CA" -TemplateName "Webservercert"
 
Description
-----------
This command requests a certificate form the CA testsrv.test.ch\Test CA with the certificate template "Webservercert"
and a CN of webserver.test.ch
The user will be asked for the value for the SAN of the certificate. 

 
.EXAMPLE
Get-Content .\certs.txt | .\Request-Certificate.ps1 -Export

Description
-----------
Gets common names from the file certs.txt and request for each a certificate. 
Each certificate will then be saved withe the private key in a .pfx file.

.EXAMPLE
C:\PS> .\Request-Certificate.ps1 -CN "webserver.test.ch" -SAN "DNS=webserver.test.ch,DNS=srvweb.test.local"
 
Description
-----------
This command requests a certificate with a CN of webserver.test.ch and subject alternative names (SANs)
The SANs of the certificate are the DNS names webserver.test.ch and srvweb.test.local.

.EXAMPLE
C:\PS> Import-Csv .\sancertificates.csv -UseCulture | .\Request-Certificate.ps1 -verbose -Export -CAName "testsrv.test.ch\Test CA"
 
Description
-----------
This example requests multiple SAN certificates from the "Test CA" CA running on the server "testsrv.test.ch".
The first command creates custom objects from a comma-separated value (CSV) file thats contains a list of object properties. The objects are then passed through the pipeline to Request-Certificate.ps1 to request the certificates form the "J0F3's Issuing CA" CA.
Each certificate will then be saved with the private key in a .pfx file.

The CSV file look something like this:
CN;SAN
test1.test.ch;DNS=test1san1.test.ch,DNS=test1san2.test.ch
test2.test.ch;DNS=test2san1.test.ch,DNS=test2san2.test.ch
test3.test.ch;DNS=test3san1.test.ch,DNS=test3san2.test.ch
		   
.NOTES
Version    : 1.3, 10/20/2018
Changes    : Improvements in temp file handling, Additional parameter to specify the export path for pfx file, Requesting SAN certs with Extensions instead of Attributes
File Name  : Request-Certificate.ps1
Requires   : PowerShell V2 or higher

.LINK
© Jonas Feller c/o J0F3, May 2011 / October 2018
www.jfe.cloud

#>

[CmdletBinding()]
Param(
    [Parameter(Mandatory = $True, ValueFromPipeline = $True, ValueFromPipelineByPropertyName = $True)]
    [string]$CN,
    [Parameter(Mandatory = $False, ValueFromPipelineByPropertyName = $True)]
    [string[]]$SAN,
    [Parameter(Mandatory = $False, ValueFromPipelineByPropertyName = $True)]
    [String]$TemplateName = "WebServer",
    [Parameter(Mandatory = $False, ValueFromPipelineByPropertyName = $True)]
    [string]$CAName,
    [Parameter(Mandatory = $False, ValueFromPipelineByPropertyName = $True)]
    [switch]$Export,
    [Parameter(Mandatory = $False, ValueFromPipelineByPropertyName = $True)]
    [ValidateScript( {Resolve-Path -Path $_})]
    [string]$ExportPath,
    [Parameter(Mandatory = $False, ValueFromPipelineByPropertyName = $True)]
    [string]$Country,
    [Parameter(Mandatory = $False, ValueFromPipelineByPropertyName = $True)]
    [string]$State,
    [Parameter(Mandatory = $False, ValueFromPipelineByPropertyName = $True)]
    [string]$City,
    [Parameter(Mandatory = $False, ValueFromPipelineByPropertyName = $True)]
    [string]$Organisation,
    [Parameter(Mandatory = $False, ValueFromPipelineByPropertyName = $True)]
    [string]$Department
)
BEGIN {
    #internal function to do some cleanup
    function Remove-ReqTempfiles() {
        param(
            [String[]]$tempfiles
        )
        Write-Verbose "Cleanup temp files..."
        Remove-Item -Path $tempfiles -Force -ErrorAction SilentlyContinue
    }

    function Remove-ReqFromStore {
        param(
            [String]$CN
        )
        Write-Verbose "Remove pending certificate request form cert store..."

        #delete pending request (if a request exists for the CN)
        $certstore = new-object system.security.cryptography.x509certificates.x509Store('REQUEST', 'LocalMachine')
        $certstore.Open('ReadWrite')
        foreach ($certreq in $($certstore.Certificates)) {
            if ($certreq.Subject -eq "CN=$CN") {
                $certstore.Remove($certreq)
            }
        }
        $certstore.close()
    }
}

PROCESS {
    #disable debug confirmation messages
    if ($PSBoundParameters['Debug']) {$DebugPreference = "Continue"}

    Write-Verbose "Generating request inf file"
    $file = @"
[NewRequest]
Subject = "CN=$CN,c=$Country, s=$State, l=$City, o=$Organisation, ou=$Department"
MachineKeySet = TRUE
KeyLength = 2048
KeySpec=1
Exportable = TRUE
RequestType = PKCS10
[RequestAttributes]
CertificateTemplate = "$TemplateName"
"@

    #check if SAN certificate is requested
    if ($PSBoundParameters.ContainsKey('SAN')) {
        #each SAN must be a array element
        #if the array has ony one element then split it on the commas.
        if (($SAN).count -eq 1) {
            $SAN = @($SAN -split ',')

            Write-Host "Requesting SAN certificate with subject $CN and SAN: $($SAN -join ',')" -ForegroundColor Green
            Write-Debug "Parameter values: CN = $CN, TemplateName = $TemplateName, CAName = $CAName, SAN = $($SAN -join ' ')"
        }

        Write-Verbose "A value for the SAN is specified. Requesting a SAN certificate." 
        Write-Debug "Add Extension for SAN to the inf file..."
        $file += @'

[Extensions]
; If your client operating system is Windows Server 2008, Windows Server 2008 R2, Windows Vista, or Windows 7
; SANs can be included in the Extensions section by using the following text format. Note 2.5.29.17 is the OID for a SAN extension.

2.5.29.17 = "{text}"

'@

        foreach ($an in $SAN) {
            $file += "_continue_ = `"$($an)&`"`n"
        }
    }
    else {
        Write-Host "Requesting certificate with subject $CN" -ForegroundColor Green
        Write-Debug "Parameter values: CN = $CN, TemplateName = $TemplateName, CAName = $CAName"
    }

    try	{
        #create temp files
        $inf = [System.IO.Path]::GetTempFileName()
        $req = [System.IO.Path]::GetTempFileName()
        $cer = Join-Path -Path $env:TEMP -ChildPath "$CN.cer"
        $rsp = Join-Path -Path $env:TEMP -ChildPath "$CN.rsp"

        Remove-ReqTempfiles -tempfiles $inf, $req, $cer, $rsp
        #create new request inf file
        Set-Content -Path $inf -Value $file 

        #show inf file if -verbose is used
        Get-Content -Path $inf | Write-Verbose

        Write-Verbose "generate .req file with certreq.exe"
        Invoke-Expression -Command "certreq -new `"$inf`" `"$req`""
        if (!($LastExitCode -eq 0)) {
            throw "certreq -new command failed"
        }

        write-verbose "Sending certificate request to CA"
        Write-Debug "CAName = $CAName"
            
        if (!$PSBoundParameters.ContainsKey('CAName')) {
            $CAs = certutil -dump | Select-String 'Config:'
            if (($CAs.Length -eq 1) -and ($CAs[0] -match '.*`(.*)''')) {
                $CAName = $matches[1]
            }
            else {
                $CAName = ""
            }
        }

        if (!$CAName -eq "") {
            $CAName = " -config `"$CAName`""
        }

        Write-Debug "certreq -submit$CAName `"$req`" `"$cer`""
        Invoke-Expression -Command "certreq -submit$CAName `"$req`" `"$cer`""

        if (!($LastExitCode -eq 0)) {
            throw "certreq -submit command failed"
        }
        Write-Debug "request was successful. Result was saved to `"$cer`""

        write-verbose "retrieve and install the certificate"
        Invoke-Expression -Command "certreq -accept `"$cer`""

        if (!($LastExitCode -eq 0)) {
            throw "certreq -accept command failed"
        }

        if (($LastExitCode -eq 0) -and ($? -eq $true)) {
            Write-Host "Certificate request successfully finished!" -ForegroundColor Green
		    	
        }
        else {
            throw "Request failed with unknown error. Try with -verbose -debug parameter"
        }


        if ($export) {
            Write-Debug "export parameter is set. => export certificate"
            Write-Verbose "exporting certificate and private key"
            $cert = Get-Childitem "cert:\LocalMachine\My" | where-object {$_.Thumbprint -eq (New-Object System.Security.Cryptography.X509Certificates.X509Certificate2((Get-Item $cer).FullName, "")).Thumbprint}
            Write-Debug "Certificate found in computerstore: $cert"

            #create a pfx export as a byte array
            $certbytes = $cert.export([System.Security.Cryptography.X509Certificates.X509ContentType]::pfx)

            #write pfx file
            if ($PSBoundParameters.ContainsKey('ExportPath')) {
                $pfxPath = Join-Path -Path (Resolve-Path -Path $ExportPath) -ChildPath "$CN.pfx" 
            }
            else {
                $pfxPath = ".\$CN.pfx"
            }
            $certbytes | Set-Content -Encoding Byte -Path $pfxPath -ea Stop
            Write-Host "Certificate successfully exported to `"$pfxPath`"!" -ForegroundColor Green
		    
            Write-Verbose "deleting exported certificate from computer store"
            # delete certificate from computer store
            $certstore = new-object system.security.cryptography.x509certificates.x509Store('My', 'LocalMachine')
            $certstore.Open('ReadWrite')
            $certstore.Remove($cert)
            $certstore.close() 
		    
        }
        else {
            Write-Debug "export parameter is not set. => script finished"
            Write-Host "The certificate with the subject $CN is now installed in the computer store !" -ForegroundColor Green
        }
    }
    catch {
        #show error message (non terminating error so that the rest of the pipeline input get processed) 
        Write-Error $_
    }
    finally {
        #tempfiles and request cleanup
        Remove-ReqTempfiles -tempfiles $inf, $req, $cer, $rsp
        Remove-ReqFromStore -CN $CN
    }
}

END {
    Remove-ReqTempfiles -tempfiles $inf, $req, $cer, $rsp
}