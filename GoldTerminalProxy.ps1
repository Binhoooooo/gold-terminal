# Gold Terminal Local Proxy
# Lance un serveur HTTP sur localhost:7432 qui redirige vers Vercel
# MT4 peut acceder localhost sans restriction WebRequest

param([int]$Port = 7432)

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "✅ Gold Terminal Proxy démarré sur http://localhost:$Port"
Write-Host "   MT4 API URL: http://localhost:$Port/signal?symbol=GC%3DF"
Write-Host "   Ctrl+C pour arrêter`n"

while ($listener.IsListening) {
    try {
        $ctx = $listener.GetContext()
        $req = $ctx.Request
        $resp = $ctx.Response

        $path = $req.Url.PathAndQuery
        $vercelUrl = "https://gold-terminal-silk.vercel.app/api$path"

        try {
            $webReq = [System.Net.WebRequest]::Create($vercelUrl)
            $webReq.Timeout = 10000
            $webResp = $webReq.GetResponse()
            $reader = New-Object System.IO.StreamReader($webResp.GetResponseStream())
            $body = $reader.ReadToEnd()
            $reader.Close()
            $webResp.Close()

            $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)
            $resp.ContentType = "application/json"
            $resp.ContentLength64 = $bodyBytes.Length
            $resp.Headers.Add("Access-Control-Allow-Origin", "*")
            $resp.OutputStream.Write($bodyBytes, 0, $bodyBytes.Length)
            Write-Host "$(Get-Date -Format 'HH:mm:ss') → $path | $($body.Substring(0,[Math]::Min(80,$body.Length)))..."
        } catch {
            $err = '{"error":"proxy error"}'
            $errBytes = [System.Text.Encoding]::UTF8.GetBytes($err)
            $resp.StatusCode = 503
            $resp.ContentLength64 = $errBytes.Length
            $resp.OutputStream.Write($errBytes, 0, $errBytes.Length)
            Write-Host "$(Get-Date -Format 'HH:mm:ss') ERREUR: $_"
        }
        $resp.OutputStream.Close()
    } catch {}
}
