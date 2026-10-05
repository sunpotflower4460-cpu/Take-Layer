/**
 * Minimal read-only home: Goal / Releases / Today / Attention. No framework, no external
 * assets. The page holds no data; it fetches the Operator API with a token the person
 * types in (kept in sessionStorage only). Accuracy of state > polish.
 */
export function renderHomePage(): string {
  return `<!doctype html>
<html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Artist OS</title>
<style>
:root{--bg:#fff;--fg:#1a1a1a;--mute:#666;--line:#ddd;--warn:#b45309;--bad:#b91c1c;--ok:#15803d}
@media (prefers-color-scheme:dark){:root{--bg:#111;--fg:#eee;--mute:#aaa;--line:#333;--warn:#fbbf24;--bad:#f87171;--ok:#4ade80}}
body{margin:0;padding:16px;background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,sans-serif;max-width:860px;margin-inline:auto}
h1{font-size:20px}h2{font-size:15px;margin:24px 0 8px;border-bottom:1px solid var(--line);padding-bottom:4px}
.mute{color:var(--mute)}.row{padding:6px 0;border-bottom:1px solid var(--line)}.warn{color:var(--warn)}.bad{color:var(--bad)}.ok{color:var(--ok)}
input,button{font:inherit;padding:6px 8px}
</style></head><body>
<h1>Artist OS</h1>
<form id="f"><input id="t" type="password" placeholder="Operator token" autocomplete="off"> <button>Load</button></form>
<div id="out" class="mute">Enter the operator token to load.</div>
<script>
const el=(s)=>document.querySelector(s);
const esc=(s)=>String(s??'').replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const tk=()=>{try{return sessionStorage.getItem('aos')||''}catch{return ''}};
async function post(p){const r=await fetch(p,{method:'POST',headers:{authorization:'Bearer '+tk()}});if(!r.ok)throw new Error(p+' '+r.status);return r.json()}
const BLOCK_LABEL={blocked:'ブロック中 / Blocked',reconcile_requested:'照合を依頼済み / Reconcile requested',waiting_for_studio_mac:'Studio Mac を待っています / Waiting for Studio Mac',ambiguous_needs_human:'判定不能：人の確認が必要 / Ambiguous — needs a human'};
const BLOCK_WHY={LOCAL_SIDE_EFFECT_UNKNOWN:'Mac上のファイルが書き込まれたか不明です。Macに確認させます（成功/失敗を推測で選びません）。',LEASE_EXPIRED_OUTCOME_UNKNOWN:'外部への変更が反映されたか不明です。人が証拠を見て判断します。'};
async function api(p){const r=await fetch(p,{headers:{authorization:'Bearer '+tk()}});if(!r.ok)throw new Error(p+' '+r.status);return r.json()}
async function load(){
  const out=el('#out');out.textContent='Loading…';
  try{
    const [home,today]=await Promise.all([api('/api/home'),api('/api/today')]);
    const sec=(t,rows,empty)=>'<h2>'+t+'</h2>'+(rows.length?rows.join(''):'<div class="mute">'+empty+'</div>');
    const e=(x)=>'<div class="row">'+esc(x.summary)+' <span class="mute">['+esc(x.sourceSystem)+']</span>'+(x.progress!=null?' '+Math.round(x.progress*100)+'%':'')+'</div>';
    out.className='';
    out.innerHTML=
      '<h2>Goal</h2>'+(home.goal?'<div>'+esc(home.goal.title)+' <span class="mute">('+esc(home.goal.priority)+')</span></div>':'<div class="mute">No active goal.</div>')+
      sec('Releases',home.releases.map(r=>'<div class="row">'+esc(r.title)+' <span class="mute">'+esc(r.status)+'</span></div>'),'No releases.')+
      sec('Needs you ('+today.needsYou.length+')',today.needsYou.map(x=>e(x).replace('</div>',' <span class="warn">'+esc(x.actionCapability)+'</span></div>')),'Nothing needs you.')+
      sec('Running',today.running.map(e),'Nothing running.')+
      sec('Scheduled',today.scheduled.map(e),'Nothing scheduled.')+
      sec('Auto-completed',today.autoCompleted.map(e),'Nothing yet.')+
      sec('Unreadable sources',today.unreadableSources.map(s=>'<div class="row bad">'+esc(s.system)+': '+esc(s.reason)+'</div>'),'All configured sources readable.')+
      sec('Blocked Mac jobs ('+home.blockedJobs.length+')',home.blockedJobs.map(b=>'<div class="row"><b>'+esc(b.jobType)+'</b> <span class="warn">'+esc(BLOCK_LABEL[b.state]||b.state)+'</span>'+
        '<div class="mute">'+esc(BLOCK_WHY[b.blockedReason]||b.blockedReason)+' ['+esc(b.blockedReason)+']</div>'+
        '<div class="mute">Mac: '+esc(b.runnerId||'-')+' '+(b.runnerOnline?'<span class="ok">online</span>':'<span class="warn">offline</span>')+'</div>'+
        (b.reconcile&&b.reconcile.evidence?'<div class="mute">evidence: '+esc(b.reconcile.evidence)+'</div>':'')+
        (b.canReconcile&&b.state!=='reconcile_requested'&&b.state!=='waiting_for_studio_mac'?'<button data-reconcile="'+esc(b.jobId)+'">照合する / Request Reconciliation</button> ':'')+
        '<button data-detail="'+esc(b.jobId)+'">詳細 / Details</button><pre class="mute" id="d-'+esc(b.jobId)+'" hidden></pre></div>'),'No blocked Mac jobs.')+
      sec('Mac Runner',home.runners.map(r=>'<div class="row">'+esc(r.runnerId)+' '+(r.online?'<span class="ok">online</span>':'<span class="warn">offline</span>')+'</div>'),'No runner has reported in. Queued jobs wait.');
    for(const btn of document.querySelectorAll('[data-reconcile]'))btn.addEventListener('click',async()=>{btn.disabled=true;try{await post('/api/mac-jobs/'+encodeURIComponent(btn.dataset.reconcile)+'/reconcile')}catch(err){alert(String(err.message||err))}load()});
    for(const btn of document.querySelectorAll('[data-detail]'))btn.addEventListener('click',()=>{const pre=document.getElementById('d-'+btn.dataset.detail);const b=home.blockedJobs.find(x=>x.jobId===btn.dataset.detail);pre.textContent=JSON.stringify(b,null,2);pre.hidden=!pre.hidden});
  }catch(err){out.className='bad';out.textContent=String(err.message||err)}
}
el('#f').addEventListener('submit',(ev)=>{ev.preventDefault();try{sessionStorage.setItem('aos',el('#t').value)}catch{}el('#t').value='';load()});
if(tk())load();
</script></body></html>`
}
