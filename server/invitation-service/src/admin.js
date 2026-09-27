// Minimal admin page served at /admin. The admin token is kept only in this
// browser tab (sessionStorage) and sent as a Bearer header.
export const adminPage = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Familoq Admin</title>
<style>
  :root { --bg:#f6f7f6; --card:#fff; --text:#1c2b24; --muted:#5d6b64; --accent:#2e7d5e; --line:#dde3df; --red:#b3261e; }
  @media (prefers-color-scheme: dark) { :root { --bg:#111614; --card:#1a211e; --text:#e7efe9; --muted:#9aa8a1; --accent:#66c79a; --line:#2c3531; --red:#f2b8b5; } }
  * { box-sizing: border-box; }
  body { margin:0; font:15px/1.5 -apple-system, "Segoe UI", Roboto, sans-serif; background:var(--bg); color:var(--text); }
  main { max-width: 900px; margin: 0 auto; padding: 24px 16px 64px; }
  h1 { font-size: 22px; margin: 0 0 4px; } h2 { font-size: 17px; margin: 0 0 12px; }
  p.sub { color: var(--muted); margin: 0 0 20px; }
  section { background:var(--card); border:1px solid var(--line); border-radius:14px; padding:16px; margin-bottom:16px; }
  input, textarea { font:inherit; padding:8px 10px; border:1px solid var(--line); border-radius:8px; background:var(--bg); color:var(--text); }
  button { font:inherit; padding:8px 14px; border-radius:8px; border:0; background:var(--accent); color:#fff; cursor:pointer; }
  button.secondary { background:transparent; color:var(--accent); border:1px solid var(--line); }
  button.danger { background:transparent; color:var(--red); border:1px solid var(--line); padding:4px 10px; }
  .row { display:flex; gap:8px; flex-wrap:wrap; align-items:center; }
  table { width:100%; border-collapse: collapse; font-size:14px; }
  th, td { text-align:left; padding:8px 6px; border-bottom:1px solid var(--line); vertical-align: top; }
  th { color: var(--muted); font-weight: 600; }
  .codes { font: 600 20px/1.8 ui-monospace, Menlo, Consolas, monospace; letter-spacing: 1px; }
  .muted { color: var(--muted); }
  .scroll { overflow-x: auto; }
</style>
</head>
<body>
<main>
  <h1>Familoq invitations</h1>
  <p class="sub">Create App Invitation codes, revoke access, read invitation requests.</p>

  <section id="login">
    <h2>Admin token</h2>
    <div class="row"><input id="token" type="password" placeholder="Admin token" style="flex:1;min-width:220px"><button onclick="saveToken()">Unlock</button></div>
    <p class="muted" id="loginMsg"></p>
  </section>

  <div id="app" hidden>
    <section>
      <h2>New invitation codes</h2>
      <div class="row">
        <label>Count <input id="count" type="number" min="1" max="50" value="1" style="width:80px"></label>
        <label>Valid for days <input id="days" type="number" min="1" max="365" value="14" style="width:90px"></label>
        <input id="note" placeholder="Note, e.g. John & Sarah" style="flex:1;min-width:180px">
        <button onclick="createCodes()">Create</button>
      </div>
      <div id="newCodes" class="codes"></div>
      <p class="muted">Codes are shown only once - copy them now. Only a hash is stored.</p>
    </section>

    <section><h2>Invitations</h2><div class="scroll"><table id="invitations"></table></div></section>
    <section><h2>Activated accounts</h2><div class="scroll"><table id="users"></table></div></section>
    <section><h2>Invitation requests</h2><div class="scroll"><table id="requests"></table></div></section>
    <button class="secondary" onclick="logout()">Lock</button>
  </div>
</main>
<script>
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&":"&amp;", "<":"&lt;", ">":"&gt;", '"':"&quot;", "'":"&#39;" }[c]));
const date = (t) => t ? new Date(t * 1000).toLocaleString() : "-";
const token = () => sessionStorage.getItem("fq_admin") || "";
async function api(path, method = "GET", body) {
  const res = await fetch(path, { method, headers: { "authorization": "Bearer " + token(), "content-type": "application/json" }, body: body ? JSON.stringify(body) : undefined });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.message || res.status);
  return data;
}
function saveToken() { sessionStorage.setItem("fq_admin", document.getElementById("token").value.trim()); load(); }
function logout() { sessionStorage.removeItem("fq_admin"); location.reload(); }
async function createCodes() {
  const data = await api("/v1/admin/invitations", "POST", {
    count: +document.getElementById("count").value, expiresInDays: +document.getElementById("days").value, note: document.getElementById("note").value
  });
  document.getElementById("newCodes").innerHTML = data.codes.map(esc).join("<br>");
  load();
}
async function revokeInvitation(id) { if (confirm("Revoke this invitation?")) { await api("/v1/admin/invitations/" + id + "/revoke", "POST"); load(); } }
async function setUser(id, action) { if (confirm(action + " this account?")) { await api("/v1/admin/users/" + id + "/" + action, "POST"); load(); } }
async function done(id) { await api("/v1/admin/requests/" + id + "/done", "POST"); load(); }
async function load() {
  try {
    const [inv, users, reqs] = await Promise.all([api("/v1/admin/invitations"), api("/v1/admin/users"), api("/v1/admin/requests")]);
    document.getElementById("login").hidden = true;
    document.getElementById("app").hidden = false;
    document.getElementById("invitations").innerHTML = "<tr><th>Code</th><th>Status</th><th>Note</th><th>Created</th><th>Expires</th><th></th></tr>" +
      inv.invitations.map(i => "<tr><td>…" + esc(i.hint) + "</td><td>" + (i.expired ? "expired" : esc(i.status)) + "</td><td>" + esc(i.note) + "</td><td>" + date(i.created_at) + "</td><td>" + date(i.expires_at) + "</td><td>" +
        (i.status === "active" && !i.expired ? "<button class='danger' onclick=\\"revokeInvitation('" + esc(i.id) + "')\\">Revoke</button>" : "") + "</td></tr>").join("");
    document.getElementById("users").innerHTML = "<tr><th>Account</th><th>Status</th><th>Invitation</th><th>Activated</th><th>Last seen</th><th></th></tr>" +
      users.users.map(u => "<tr><td class='muted'>" + esc(u.id.slice(0, 8)) + "</td><td>" + esc(u.status) + "</td><td>…" + esc(u.hint) + " " + esc(u.note) + "</td><td>" + date(u.created_at) + "</td><td>" + date(u.last_seen_at) + "</td><td>" +
        "<button class='danger' onclick=\\"setUser('" + esc(u.id) + "','" + (u.status === "active" ? "revoke" : "restore") + "')\\">" + (u.status === "active" ? "Revoke" : "Restore") + "</button></td></tr>").join("");
    document.getElementById("requests").innerHTML = "<tr><th>Name</th><th>Contact</th><th>Message</th><th>Received</th><th></th></tr>" +
      reqs.requests.map(r => "<tr><td>" + esc(r.name) + "</td><td>" + esc(r.contact) + "</td><td>" + esc(r.message) + "</td><td>" + date(r.created_at) + "</td><td>" +
        (r.status === "open" ? "<button class='secondary' onclick=\\"done('" + esc(r.id) + "')\\">Done</button>" : "done") + "</td></tr>").join("");
  } catch (e) {
    document.getElementById("loginMsg").textContent = "Could not unlock: " + e.message;
    document.getElementById("login").hidden = false;
    document.getElementById("app").hidden = true;
  }
}
if (token()) load();
</script>
</body>
</html>`;
