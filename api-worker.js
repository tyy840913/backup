let keyUsage = {};

function escapeHtml(s) {
  return ('' + (s || '')).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

const DEFAULT_CONFIG = {
  apiUrl: 'https://generativelanguage.googleapis.com/v1beta',
  keys: [],
  clientToken: ''
};

function normalizeApiUrl(url) {
  return (url || DEFAULT_CONFIG.apiUrl).replace(/\/+$/, '');
}

function stripVersion(path) {
  const m = path.match(/^\/(v\d+[a-z]*)(?:\/|$)/);
  if (m) {
    const rest = path.slice(m[0].length);
    return rest ? '/' + rest.replace(/^\/+/, '') : '';
  }
  return path;
}

function buildTargetUrl(apiUrl, clientPath, queryString) {
  const base = apiUrl.replace(/\/+$/, '');
  const baseVerMatch = base.match(/\/(v\d+[a-z]*)$/);
  if (baseVerMatch) {
    const stripped = stripVersion(clientPath);
    return base + stripped + queryString;
  }
  return base + clientPath + queryString;
}

async function loadConfig(env) {
  const raw = await env.GEMINI_CONFIG.get('config', 'json');
  const cfg = raw ? { ...DEFAULT_CONFIG, ...raw } : { ...DEFAULT_CONFIG };
  cfg.apiUrl = normalizeApiUrl(cfg.apiUrl);
  return cfg;
}

function saveConfig(env, cfg) {
  keyUsage = {};
  cfg.keys.forEach(k => { keyUsage[k] = 0; });
  return env.GEMINI_CONFIG.put('config', JSON.stringify(cfg));
}

function generateToken() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  let result = '';
  const arr = new Uint8Array(32);
  crypto.getRandomValues(arr);
  for (let i = 0; i < 32; i++) {
    result += chars[arr[i] % chars.length];
  }
  return result;
}

function getHtmlPage(cfg) {
  const safeUrl = escapeHtml(cfg.apiUrl);
  const safeToken = escapeHtml(cfg.clientToken);
  const keysText = (cfg.keys || []).join('\n');
  const safeKeys = escapeHtml(keysText);
  return `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>API Proxy</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:linear-gradient(135deg,#f5f7fa,#e4e9f0);color:#1a1a2e;padding:32px 20px;min-height:100vh}
.container{max-width:680px;margin:0 auto}
.header{text-align:center;margin-bottom:32px}
.header h1{font-size:1.75rem;font-weight:700;letter-spacing:-.5px}
.header p{color:#6b7280;font-size:.9rem;margin-top:6px}
.card{background:#fff;border-radius:16px;padding:28px;margin-bottom:16px;box-shadow:0 1px 3px rgba(0,0,0,.04),0 4px 16px rgba(0,0,0,.06)}
.card h2{font-size:1rem;font-weight:600;margin-bottom:16px;padding-bottom:12px;border-bottom:1px solid #f0f0f0;display:flex;align-items:center;gap:8px}
.card h2 .step{display:inline-flex;align-items:center;justify-content:center;width:22px;height:22px;border-radius:6px;background:#eef2ff;color:#4f46e5;font-size:.75rem;font-weight:700}
label{display:block;font-size:.82rem;font-weight:600;margin-bottom:5px;color:#374151}
input,textarea{width:100%;padding:11px 14px;border:1.5px solid #e2e5ea;border-radius:10px;font-size:.9rem;transition:all .2s;background:#fafbfc;color:#1a1a2e;font-family:inherit}
input:focus,textarea:focus{outline:none;border-color:#4f46e5;box-shadow:0 0 0 3px rgba(79,70,229,.12);background:#fff}
textarea{font-family:'SF Mono',Consolas,monospace;resize:vertical;min-height:110px;font-size:.85rem;line-height:1.5}
.desc{font-size:.78rem;color:#9ca3af;margin-top:5px;line-height:1.4}
.row{display:flex;gap:8px}
.row input{flex:1}
.btn{display:inline-flex;align-items:center;justify-content:center;gap:6px;padding:11px 24px;background:#4f46e5;color:#fff;border:none;border-radius:10px;font-size:.9rem;font-weight:600;cursor:pointer;transition:all .15s;white-space:nowrap;user-select:none}
.btn:hover{background:#4338ca;box-shadow:0 4px 12px rgba(79,70,229,.3)}
.btn:active{transform:scale(.97)}
.btn-sm{padding:9px 16px;font-size:.82rem;border-radius:8px}
.btn-green{background:#059669}
.btn-green:hover{background:#047857;box-shadow:0 4px 12px rgba(5,150,105,.3)}
.btn:disabled{opacity:.5;cursor:not-allowed;box-shadow:none}
.btn:disabled:active{transform:none}
.btn-primary{width:100%;padding:14px;font-size:1rem;margin-top:8px}
.spinner{display:none;width:16px;height:16px;border:2px solid rgba(255,255,255,.3);border-top-color:#fff;border-radius:50%;animation:spin .6s linear infinite;flex-shrink:0}
.btn.loading .spinner{display:inline-block}
.btn.loading .btn-text{display:none}
@keyframes spin{to{transform:rotate(360deg)}}
#toast{position:fixed;top:24px;left:50%;transform:translateX(-50%) translateY(-80px);padding:14px 28px;border-radius:12px;font-size:.9rem;font-weight:500;color:#fff;z-index:999;transition:transform .4s cubic-bezier(.22,1,.36,1),opacity .3s;opacity:0;pointer-events:none;box-shadow:0 8px 32px rgba(0,0,0,.15);max-width:90vw;text-align:center}
#toast.show{transform:translateX(-50%) translateY(0);opacity:1}
#toast.success{background:#059669}
#toast.error{background:#dc2626}
@media(max-width:640px){body{padding:16px 12px}.card{padding:20px}.header h1{font-size:1.4rem}}
</style>
</head>
<body>
<div class="container">
<div class="header">
<h1>API Proxy</h1>
<p>统一管理多个 Key，客户端通过一个令牌接入任意 API</p>
</div>

<form id="configForm">
<div class="card">
<h2><span class="step">1</span>接口地址</h2>
<label for="apiUrl">请求转发目标 URL</label>
<input type="text" id="apiUrl" name="apiUrl" value="${safeUrl}" placeholder="https://api.openai.com/v1" />
<p class="desc">任意 AI API 或自定义后端接口</p>
</div>

<div class="card">
<h2><span class="step">2</span>API Key 列表</h2>
<label for="keys">Keys（每行一个）</label>
<textarea id="keys" name="keys" placeholder="sk-...">${safeKeys}</textarea>
<p class="desc">多个 Key 自动轮询，每次请求选择使用次数最少的一个</p>
</div>

<div class="card">
<h2><span class="step">3</span>客户端令牌</h2>
<label for="clientToken">统一认证令牌</label>
<div class="row">
<input type="text" id="clientToken" name="clientToken" value="${safeToken}" placeholder="点击生成或手动输入" readonly onclick="copyToken()" />
<button type="button" class="btn btn-green btn-sm" onclick="genToken()">生成</button>
</div>
<p class="desc">客户端在任何请求头中携带此值即可通过认证，点击输入框复制</p>
</div>

<button type="submit" class="btn btn-primary" id="saveBtn">
<span class="spinner"></span>
<span class="btn-text">保存配置</span>
</button>
</form>
</div>

<div id="toast"></div>

<script>
function showToast(msg,type='success'){
  const t=document.getElementById('toast');
  t.textContent=msg;
  t.className=type;
  t.classList.add('show');
  clearTimeout(t._timer);
  t._timer=setTimeout(()=>t.classList.remove('show'),2500);
}

function genToken(){
  const chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  let r='';
  const arr=new Uint8Array(32);
  crypto.getRandomValues(arr);
  for(let i=0;i<32;i++)r+=chars[arr[i]%chars.length];
  document.getElementById('clientToken').value=r;
  showToast('令牌已生成');
}

function copyToken(){
  const el=document.getElementById('clientToken');
  if(!el.value)return;
  navigator.clipboard.writeText(el.value).then(()=>showToast('已复制到剪贴板')).catch(()=>{el.select();document.execCommand('copy');showToast('已复制')});
}

const tok=document.getElementById('clientToken');
fetch('/config',{headers:{'Authorization':'Bearer '+(tok.value||'')}}).then(r=>r.json()).then(d=>{
  if(d.apiUrl) document.getElementById('apiUrl').value=d.apiUrl;
  if(d.keys) document.getElementById('keys').value=d.keys.join('\\n');
  if(d.clientToken) tok.value=d.clientToken;
  if(d.authed===false) showToast('令牌无效，配置为只读','error');
}).catch(()=>{});

document.getElementById('configForm').onsubmit=async e=>{
  e.preventDefault();
  const btn=document.getElementById('saveBtn');
  btn.classList.add('loading');
  btn.disabled=true;
  try{
    const fd=new FormData(e.target);
    const res=await fetch('/configure',{method:'POST',body:fd});
    const data=await res.json();
    showToast(data.message,data.success?'success':'error');
  }catch(err){
    showToast('请求失败: '+err.message,'error');
  }finally{
    btn.classList.remove('loading');
    btn.disabled=false;
  }
};
</script>
</body>
</html>`;
}

function selectKey(cfg) {
  const keys = cfg.keys;
  if (keys.length === 0) return null;
  let minUsage = Infinity, selectedKey = keys[0];
  for (const key of keys) {
    const usage = keyUsage[key] || 0;
    if (usage < minUsage) { minUsage = usage; selectedKey = key; }
  }
  return selectedKey;
}

let headerNameCache = null;

function resolveClientToken(request, cfg) {
  if (!cfg.clientToken) return null;
  if (headerNameCache) {
    const val = request.headers.get(headerNameCache);
    if (val === cfg.clientToken) return val;
  }
  for (const [name, value] of request.headers) {
    const v = value.replace(/^Bearer\s+/i, '').trim();
    if (v === cfg.clientToken) {
      headerNameCache = name;
      return v;
    }
  }
  return null;
}

function isGoogleUpstream(apiUrl) {
  return /googleapis\.com/i.test(apiUrl);
}

function corsHeaders(origin) {
  return {
    'Access-Control-Allow-Origin': origin || '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, PATCH, OPTIONS',
    'Access-Control-Allow-Headers': '*',
    'Access-Control-Max-Age': '86400'
  };
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;
    const origin = request.headers.get('Origin') || '*';
    const ch = corsHeaders(origin);

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: ch });
    }

    const cfg = await loadConfig(env);

    if (path === '/' && request.method === 'GET') {
      return new Response(getHtmlPage(cfg), {
        headers: { 'Content-Type': 'text/html;charset=utf-8', ...ch }
      });
    }

    if (path === '/config' && request.method === 'GET') {
      const authed = resolveClientToken(request, cfg) !== null;
      return new Response(JSON.stringify({
        apiUrl: cfg.apiUrl,
        keys: authed ? cfg.keys : undefined,
        clientToken: cfg.clientToken || '',
        authed
      }), { headers: { 'Content-Type': 'application/json', ...ch } });
    }

    if (path === '/configure' && request.method === 'POST') {
      try {
        let apiUrl, keysText, clientToken;
        const ct = request.headers.get('Content-Type') || '';
        if (ct.includes('application/json')) {
          const body = await request.json();
          apiUrl = body.apiUrl;
          keysText = body.keys;
          clientToken = body.clientToken;
        } else {
          const fd = await request.formData();
          apiUrl = fd.get('apiUrl');
          keysText = fd.get('keys');
          clientToken = fd.get('clientToken');
        }
        const newCfg = {
          apiUrl: normalizeApiUrl(apiUrl),
          keys: (keysText || '').split('\n').map(k => k.trim()).filter(k => k.length > 0),
          clientToken: (clientToken || '').trim()
        };
        await saveConfig(env, newCfg);
        return new Response(JSON.stringify({ success: true, message: '配置保存成功' }), {
          headers: { 'Content-Type': 'application/json', ...ch }
        });
      } catch (e) {
        return new Response(JSON.stringify({ success: false, message: '保存失败: ' + e.message }), {
          headers: { 'Content-Type': 'application/json', ...ch }
        });
      }
    }

    if (path === '/gentoken' && request.method === 'GET') {
      return new Response(JSON.stringify({ token: generateToken() }), {
        headers: { 'Content-Type': 'application/json', ...ch }
      });
    }

    if (!resolveClientToken(request, cfg)) {
      return new Response(JSON.stringify({ error: '未授权：客户端令牌无效' }), {
        status: 401, headers: { 'Content-Type': 'application/json', ...ch }
      });
    }

    if (cfg.keys.length === 0) {
      return new Response(JSON.stringify({ error: '未配置 API Key' }), {
        status: 500, headers: { 'Content-Type': 'application/json', ...ch }
      });
    }

    const selectedKey = selectKey(cfg);
    keyUsage[selectedKey] = (keyUsage[selectedKey] || 0) + 1;

    const targetUrl = buildTargetUrl(cfg.apiUrl, path, url.search);

    const headers = new Headers(request.headers);
    if (isGoogleUpstream(cfg.apiUrl)) {
      headers.set('x-goog-api-key', selectedKey);
      headers.delete('Authorization');
    } else {
      headers.set('Authorization', 'Bearer ' + selectedKey);
    }
    headers.delete('Host');
    headers.delete('Referer');
    headers.delete('CF-Connecting-IP');
    headers.delete('CF-IPCountry');
    headers.delete('CF-Ray');
    headers.delete('CF-Visitor');
    headers.delete('CF-Worker');
    headers.delete('X-Forwarded-For');
    headers.delete('X-Real-IP');
    headers.delete('Content-Length');

    const proxyRequest = new Request(targetUrl, {
      method: request.method,
      headers,
      body: (request.method === 'GET' || request.method === 'HEAD' || request.method === 'OPTIONS') ? null : request.body,
      redirect: 'follow'
    });

    try {
      const response = await fetch(proxyRequest);
      const resHeaders = new Headers(response.headers);
      resHeaders.set('Access-Control-Allow-Origin', origin);
      resHeaders.set('Access-Control-Allow-Headers', '*');
      return new Response(response.body, {
        status: response.status,
        statusText: response.statusText,
        headers: resHeaders
      });
    } catch (err) {
      return new Response(JSON.stringify({ error: '代理请求失败: ' + err.message }), {
        status: 502, headers: { 'Content-Type': 'application/json', ...ch }
      });
    }
  }
};
