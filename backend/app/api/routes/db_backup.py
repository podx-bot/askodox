"""Owner-only encrypted database backup (``app.services.db_backup``).

Only the owner key (``X-ASKODOX-Admin-Key``) may export -- staff tokens and
sessions are refused even with full permissions. Nothing here returns row
contents: the export answers with a manifest (table names + row counts,
hashes, restore-test result) and a one-time token; the download returns the
ENCRYPTED file once, then it is deleted. The page at /admin/backup holds no
secrets and no data.
"""
from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import FileResponse, HTMLResponse
from pydantic import BaseModel, Field
from starlette.background import BackgroundTask

from app.api.routes.command_center import _principal, command_center
from app.services import db_backup, rate_limit

router = APIRouter(tags=["db-backup"])

EXPORT_LIMIT = 3          # verified exports per client ...
EXPORT_WINDOW = 3600      # ... per hour


class ExportBody(BaseModel):
    # Length is checked in code: a schema 422 would echo the value back.
    passphrase: str = Field(default="")


def _owner(request: Request) -> dict[str, Any]:
    principal = _principal(request)
    if principal.get("id") != "owner":
        raise HTTPException(status_code=403, detail="Only the owner key may export or download backups")
    return principal


def _audit(request: Request, action: str, backup_id: str, after: Any = None, result: str = "OK") -> None:
    try:
        command_center(request.app.state.container).audit(
            "owner", action, "database_backup", backup_id, None, after, risk="RED", result=result)
    except Exception:
        pass


@router.post("/admin/cc/backup/export")
def export_backup(body: ExportBody, request: Request) -> dict[str, Any]:
    _owner(request)
    if not db_backup.MIN_PASSPHRASE <= len(body.passphrase) <= 256:
        raise HTTPException(status_code=422,
                            detail=f"Passphrase must be {db_backup.MIN_PASSPHRASE}-256 characters")
    if rate_limit.blocked(request, "db_backup_export", limit=EXPORT_LIMIT, window_seconds=EXPORT_WINDOW):
        raise HTTPException(status_code=429, detail="Too many backups this hour -- try again later")
    rate_limit.hit(request, "db_backup_export")
    try:
        result = db_backup.create_backup(request.app.state.container.settings.database_path, body.passphrase)
    except db_backup.BackupError as exc:
        _audit(request, "db_backup_export", "-", {"error": str(exc)}, result="FAILED")
        raise HTTPException(status_code=422, detail=str(exc)) from None
    _audit(request, "db_backup_export", result["backup_id"],
           {k: result[k] for k in ("encrypted_sha256", "database_sha256", "table_count", "row_total",
                                   "restore_test")})
    return result


@router.get("/admin/cc/backup/download/{backup_id}")
def download_backup(backup_id: str, request: Request) -> FileResponse:
    _owner(request)
    token = (request.headers.get("x-askodox-backup-token") or "").strip()
    try:
        path = db_backup.take_download(backup_id, token)
    except db_backup.BackupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from None
    _audit(request, "db_backup_download", backup_id)
    return FileResponse(path, media_type="application/octet-stream", filename=path.name,
                        headers={"Cache-Control": "no-store"},
                        background=BackgroundTask(lambda: path.unlink(missing_ok=True)))


@router.delete("/admin/cc/backup/{backup_id}")
def discard_backup(backup_id: str, request: Request) -> dict[str, Any]:
    _owner(request)
    removed = db_backup.discard(backup_id)
    if removed:
        _audit(request, "db_backup_discard", backup_id)
    return {"backup_id": backup_id, "removed": removed}


_PAGE = """<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex">
<title>ASKODOX Backup</title><style>
body{font-family:system-ui,sans-serif;max-width:640px;margin:0 auto;padding:16px;background:#f8fafc;color:#0f172a}
label{display:block;margin:12px 0 4px;font-weight:600}input{width:100%;box-sizing:border-box;padding:10px;font-size:16px}
button{margin-top:14px;padding:10px 16px;font-size:16px;cursor:pointer}pre{background:#fff;padding:12px;overflow:auto;font-size:12px}
.note{font-size:14px;color:#475569}.err{color:#b91c1c}.ok{color:#15803d}
</style></head><body>
<h1>Database backup</h1>
<p class="note">Owner only. The server copies the database read-only, encrypts it with YOUR passphrase,
restores the encrypted copy into a separate test database to prove it works, then offers the
encrypted file once. The passphrase is never stored -- keep it in your password manager; without it
the backup cannot be opened.</p>
<label for="k">Owner admin key</label><input id="k" type="password" autocomplete="off">
<label for="p">Backup passphrase (16+ characters)</label><input id="p" type="password" autocomplete="new-password">
<label for="p2">Repeat passphrase</label><input id="p2" type="password" autocomplete="new-password">
<button id="go">Create verified backup</button>
<p id="msg"></p><pre id="out" hidden></pre>
<button id="dl" hidden>Download encrypted backup (once)</button>
<script>
const $=s=>document.querySelector(s);let job=null;
function say(t,c){$("#msg").textContent=t;$("#msg").className=c||""}
$("#go").onclick=async()=>{
 const k=$("#k").value.trim(),p=$("#p").value;
 if(p.length<16){say("Passphrase must be at least 16 characters","err");return}
 if(p!==$("#p2").value){say("Passphrases do not match","err");return}
 say("Creating and verifying the backup... this can take a minute.");$("#go").disabled=true;
 try{const r=await fetch("/admin/cc/backup/export",{method:"POST",headers:{"Content-Type":"application/json","X-ASKODOX-Admin-Key":k},body:JSON.stringify({passphrase:p})});
  const d=await r.json();if(!r.ok){say(d.detail||("Failed: HTTP "+r.status),"err");return}
  job={id:d.backup_id,token:d.download_token,name:d.file_name};delete d.download_token;
  $("#out").textContent=JSON.stringify(d,null,2);$("#out").hidden=false;$("#dl").hidden=false;
  say("Backup verified (restore test passed). Download it now -- the link works once and expires in 30 minutes.","ok");
 }catch(e){say("Request failed","err")}finally{$("#p").value="";$("#p2").value="";$("#go").disabled=false}};
$("#dl").onclick=async()=>{
 if(!job)return;const r=await fetch("/admin/cc/backup/download/"+encodeURIComponent(job.id),{headers:{"X-ASKODOX-Admin-Key":$("#k").value.trim(),"X-ASKODOX-Backup-Token":job.token}});
 if(!r.ok){say("Download failed: HTTP "+r.status,"err");return}
 const b=await r.blob(),a=document.createElement("a");a.href=URL.createObjectURL(b);a.download=job.name;a.click();
 job=null;$("#dl").hidden=true;say("Downloaded. Check the file size and SHA-256 against the manifest above, then store it (e.g. Google Drive).","ok")};
</script></body></html>"""


@router.get("/admin/backup", response_class=HTMLResponse, include_in_schema=False)
def backup_page() -> HTMLResponse:
    return HTMLResponse(_PAGE, headers={"Cache-Control": "no-store", "X-Robots-Tag": "noindex"})
